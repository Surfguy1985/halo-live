import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct JobRouteView: View {
    let job: FieldJob
    var onStartRoute: () -> Void = {}
    var onVerifyArrival: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: LocationService

    @State private var position: MapCameraPosition = .automatic
    @State private var destination: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var isLoadingRoute = false
    @State private var routeError: String?
    @State private var hasStartedRoute = false
    @State private var lastRouteOrigin: CLLocation?

    private let geofenceRadius: CLLocationDistance = 300

    var body: some View {
        ZStack(alignment: .bottom) {
            map
            mapChrome
            routeCard
        }
        .background(Color.black)
        .task {
            location.requestPermission()
            location.refresh()
            await resolveDestination()
            await refreshRouteIfPossible(force: true)
        }
        .onReceive(location.$location) { latest in
            guard latest != nil else { return }
            Task { await refreshRouteIfPossible(force: false) }
        }
    }

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()

            if let destination {
                MapCircle(center: destination, radius: geofenceRadius)
                    .foregroundStyle(HaloTheme.lime.opacity(0.11))
                    .stroke(HaloTheme.lime.opacity(0.55), lineWidth: 1.5)

                Annotation(job.propertyName, coordinate: destination, anchor: .bottom) {
                    destinationBeacon
                }

                if let route {
                    MapPolyline(route.polyline)
                        .stroke(
                            HaloTheme.actionBlue,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea()
    }

    private var destinationBeacon: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(HaloTheme.lime.opacity(0.18))
                    .frame(width: 54, height: 54)
                Circle()
                    .fill(HaloTheme.lime)
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(HaloTheme.ink)
            }

            Text("UNIT \(job.unit)")
                .font(HaloType.body(9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(HaloTheme.ink)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
    }

    private var mapChrome: some View {
        VStack {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .foregroundStyle(HaloTheme.ink)
                .accessibilityLabel("Close route")

                Spacer()

                locationQualityPill

                Button {
                    recenter()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .foregroundStyle(HaloTheme.ink)
                .accessibilityLabel("Recenter map")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var locationQualityPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(location.freshLocation() == nil ? HaloTheme.warning : HaloTheme.fieldLive)
                .frame(width: 7, height: 7)

            Text(locationStatusText)
                .font(HaloType.body(10, weight: .bold))
                .foregroundStyle(HaloTheme.ink.opacity(0.78))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var routeCard: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hasStartedRoute ? "ACTIVE ROUTE" : "NEXT STOP")
                            .font(HaloType.body(9, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(HaloTheme.lime)

                        Text("Unit \(job.unit)")
                            .font(HaloType.display(30, weight: .semibold))
                            .tracking(-1.0)
                            .foregroundStyle(.white)

                        Text(job.propertyName)
                            .font(HaloType.card(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))

                        Text(job.address)
                            .font(HaloType.body(11))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if let etaText {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(etaText)
                                .font(HaloType.display(24, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(distanceText ?? "ROUTE")
                                .font(HaloType.body(9, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.38))
                        }
                    } else if isLoadingRoute {
                        ProgressView()
                            .tint(HaloTheme.lime)
                            .padding(.top, 8)
                    }
                }

                HStack(spacing: 8) {
                    metricChip(
                        icon: "scope",
                        text: "\(Int(geofenceRadius))m arrival zone",
                        emphasized: isNearProperty
                    )
                    metricChip(
                        icon: "location.fill",
                        text: liveDistanceText,
                        emphasized: isNearProperty
                    )
                }

                if let routeError {
                    Label(routeError, systemImage: "exclamationmark.triangle.fill")
                        .font(HaloType.body(10, weight: .medium))
                        .foregroundStyle(HaloTheme.warning)
                }

                primaryButton

                HStack(spacing: 12) {
                    Button {
                        openInMaps()
                    } label: {
                        Label("Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(HaloType.body(12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.07))
                            .foregroundStyle(.white.opacity(0.82))
                            .clipShape(Capsule())
                    }

                    Button {
                        recenter()
                    } label: {
                        Label("Overview", systemImage: "viewfinder")
                            .font(HaloType.body(12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.07))
                            .foregroundStyle(.white.opacity(0.82))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [HaloTheme.fieldChrome.opacity(0.92), HaloTheme.fieldBackground.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: -8)
    }

    private var primaryButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            if isNearProperty {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    onVerifyArrival()
                }
            } else {
                hasStartedRoute = true
                onStartRoute()
                openInMaps()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 34, height: 34)
                    Image(systemName: isNearProperty ? "checkmark.location.fill" : "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 14, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isNearProperty ? "Verify Arrival" : (hasStartedRoute ? "Continue Route" : "Start Route"))
                        .font(HaloType.body(15, weight: .bold))
                    Text(isNearProperty ? "HALO will confirm your GPS" : routeSubtitle)
                        .font(HaloType.body(10, weight: .medium))
                        .opacity(0.58)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(0.52)
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .background(isNearProperty ? HaloTheme.lime : Color.white)
            .foregroundStyle(HaloTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func metricChip(icon: String, text: String, emphasized: Bool) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(10, weight: .bold))
            .foregroundStyle(emphasized ? HaloTheme.lime : .white.opacity(0.58))
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(emphasized ? HaloTheme.lime.opacity(0.10) : Color.white.opacity(0.055))
            .clipShape(Capsule())
    }

    private var locationStatusText: String {
        guard let fix = location.location else { return "LOCATING" }
        let age = abs(fix.timestamp.timeIntervalSinceNow)
        if age > 120 { return "REFRESHING GPS" }
        if fix.horizontalAccuracy > 100 { return "GPS ±\(Int(fix.horizontalAccuracy))m" }
        return "GPS ±\(Int(max(fix.horizontalAccuracy, 0)))m"
    }

    private var isNearProperty: Bool {
        guard let meters = liveDistanceMeters else { return false }
        // Client UX becomes arrival-ready slightly outside the authoritative
        // radius. The server remains the only authority and still enforces 300m.
        return meters <= 350
    }

    private var liveDistanceMeters: CLLocationDistance? {
        guard
            let destination,
            let current = location.location
        else { return nil }

        return current.distance(
            from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        )
    }

    private var liveDistanceText: String {
        guard let meters = liveDistanceMeters else { return "Locating…" }
        if meters < 1_000 { return "\(Int(meters.rounded()))m away" }
        return String(format: "%.1f km away", meters / 1_000)
    }

    private var etaText: String? {
        guard let route else { return nil }
        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        return "\(minutes) min"
    }

    private var distanceText: String? {
        guard let route else { return nil }
        if route.distance < 1_609.344 {
            return "\(Int((route.distance * 3.28084).rounded())) FT"
        }
        return String(format: "%.1f MI", route.distance / 1_609.344)
    }

    private var routeSubtitle: String {
        if let distanceText, let etaText {
            return "\(distanceText.lowercased()) · about \(etaText)"
        }
        return "Open turn-by-turn navigation"
    }

    private func resolveDestination() async {
        if let latitude = job.propertyLatitude, let longitude = job.propertyLongitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            await MainActor.run {
                destination = coordinate
                focusDestination(coordinate)
            }
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(job.propertyName), \(job.address)"

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate else {
                await MainActor.run { routeError = "Property location is unavailable." }
                return
            }
            await MainActor.run {
                destination = coordinate
                focusDestination(coordinate)
            }
        } catch {
            await MainActor.run {
                routeError = "Couldn’t resolve this property on the map."
            }
        }
    }

    private func refreshRouteIfPossible(force: Bool) async {
        guard
            let destination,
            let current = location.location,
            current.horizontalAccuracy >= 0
        else { return }

        if !force, let lastRouteOrigin, current.distance(from: lastRouteOrigin) < 120 {
            return
        }

        await MainActor.run {
            isLoadingRoute = true
            routeError = nil
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: current.coordinate)
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: destination)
        )
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else {
                await MainActor.run {
                    isLoadingRoute = false
                    routeError = "No driving route found."
                }
                return
            }

            await MainActor.run {
                route = best
                lastRouteOrigin = current
                isLoadingRoute = false
                fitRoute(best)
            }
        } catch {
            await MainActor.run {
                isLoadingRoute = false
                routeError = "Route unavailable. Apple Maps can still navigate you there."
            }
        }
    }

    private func recenter() {
        if let route {
            fitRoute(route)
        } else if let destination {
            focusDestination(destination)
        }
    }

    private func fitRoute(_ route: MKRoute) {
        var rect = route.polyline.boundingMapRect
        let xPadding = max(rect.size.width * 0.25, 1_000)
        let yPadding = max(rect.size.height * 0.45, 1_500)
        rect = rect.insetBy(dx: -xPadding, dy: -yPadding)
        withAnimation(.easeInOut(duration: 0.55)) {
            position = .rect(rect)
        }
    }

    private func focusDestination(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.45)) {
            position = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                )
            )
        }
    }

    private func openInMaps() {
        guard let destination else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        item.name = "\(job.propertyName) · Unit \(job.unit)"
        item.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }
}

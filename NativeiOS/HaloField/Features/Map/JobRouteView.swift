import SwiftUI
import MapKit

struct JobRouteView: View {
    let job: FieldJob
    var onStartRoute: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) { UserAnnotation() }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 42, height: 5).padding(.top, 10)
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEXT STOP").font(HaloType.body(10, weight: .bold)).tracking(1.5).foregroundStyle(HaloTheme.secondaryText)
                        Text("Unit \(job.unit) · \(job.title)").font(HaloType.card(20, weight: .bold)).foregroundStyle(HaloTheme.text)
                        Text(job.propertyName).font(HaloType.body(13)).foregroundStyle(HaloTheme.secondaryText)
                    }
                    Spacer()
                    if let minutes = job.travelMinutes {
                        Text("\(minutes) min").font(HaloType.body(12, weight: .bold))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(HaloTheme.lime.opacity(0.32)).clipShape(Capsule())
                    }
                }.padding(18)

                Button { onStartRoute(); openInMaps(job) } label: {
                    HStack { Text("Start Route"); Spacer(); Image(systemName: "location.fill") }
                        .font(HaloType.body(15, weight: .bold))
                        .padding(.horizontal, 20).frame(height: 56)
                        .background(HaloTheme.navy).foregroundStyle(.white).clipShape(Capsule())
                }.padding(.horizontal, 18).padding(.bottom, 18)
            }
            .background(.ultraThinMaterial)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .shadow(color: .black.opacity(0.12), radius: 20, y: -4)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                            .frame(width: 44, height: 44).background(.ultraThinMaterial).clipShape(Circle())
                    }.foregroundStyle(HaloTheme.ink)
                    Spacer()
                }.padding(.horizontal, 16).padding(.top, 6)
                Spacer()
            }
        }
    }

    private func openInMaps(_ job: FieldJob) {
        if let latitude = job.propertyLatitude, let longitude = job.propertyLongitude {
            let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            MKMapItem(placemark: placemark).openInMaps(
                launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
            )
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(job.propertyName), \(job.address)"
        MKLocalSearch(request: request).start { response, _ in
            response?.mapItems.first?.openInMaps(
                launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
            )
        }
    }
}
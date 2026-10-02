import SwiftData
import SwiftUI
import UIKit

struct AdditionalWorkView: View {
    let job: FieldJob

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore

    @State private var summary = ""
    @State private var detail = ""
    @State private var materialEstimate = ""
    @State private var urgent = false
    @State private var isQueued = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case summary, detail, materials
    }

    private let suggestions = [
        "Drywall / Paint",
        "Cleaning / Turn",
        "Flooring",
        "Fixture / Hardware",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    issueSection
                    detailSection
                    urgencySection
                    handoffPreview
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .background(HaloTheme.fieldBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { sendBar }
            .navigationTitle("Additional Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MAINTENANCE → TURNS")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(HaloTheme.lime)

                    Text("Hand it off once.")
                        .font(HaloType.display(30, weight: .semibold))
                        .tracking(-1)
                        .foregroundStyle(.white)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(HaloTheme.lime.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(HaloTheme.lime)
                }
            }

            Text("HALO keeps the property, unit and source job attached. The Turns team receives a ready-to-pick-up work item—no reassignment step for the field manager.")
                .font(HaloType.body(12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                chip(icon: "building.2.fill", text: job.propertyName)
                chip(icon: "door.left.hand.open", text: "Unit \(job.unit)")
            }
        }
        .padding(.top, 8)
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("WHAT NEEDS TO HAPPEN")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            summary = suggestion == "Other" ? "" : suggestion
                            if suggestion == "Other" {
                                focusedField = .summary
                            }
                        } label: {
                            Text(suggestion)
                                .font(HaloType.body(11, weight: .bold))
                                .padding(.horizontal, 13)
                                .frame(height: 38)
                                .background(summary == suggestion ? HaloTheme.lime : Color.white.opacity(0.06))
                                .foregroundStyle(summary == suggestion ? HaloTheme.ink : .white.opacity(0.74))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Short work summary", text: $summary)
                .focused($focusedField, equals: .summary)
                .font(HaloType.body(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(focusedField == .summary ? HaloTheme.lime.opacity(0.65) : HaloTheme.fieldBorder)
                }
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("FIELD CONTEXT")

            TextEditor(text: $detail)
                .focused($focusedField, equals: .detail)
                .font(HaloType.body(14))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 118)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if detail.isEmpty {
                        Text("What did you find? What should the Turns team know?")
                            .font(HaloType.body(13))
                            .foregroundStyle(.white.opacity(0.28))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(HaloTheme.lime)

                TextField("Materials / quantity, if known", text: $materialEstimate)
                    .focused($focusedField, equals: .materials)
                    .font(HaloType.body(13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var urgencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PRIORITY")

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                urgent.toggle()
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        Circle()
                            .fill(urgent ? HaloTheme.warning.opacity(0.16) : Color.white.opacity(0.06))
                            .frame(width: 42, height: 42)
                        Image(systemName: urgent ? "bolt.fill" : "clock.fill")
                            .foregroundStyle(urgent ? HaloTheme.warning : .white.opacity(0.52))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(urgent ? "Urgent handoff" : "Standard handoff")
                            .font(HaloType.body(14, weight: .bold))
                            .foregroundStyle(.white)
                        Text(urgent ? "Surface this for immediate Turns pickup." : "Add this to the Turns pickup queue.")
                            .font(HaloType.body(11))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer()

                    Image(systemName: urgent ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .foregroundStyle(urgent ? HaloTheme.warning : .white.opacity(0.24))
                }
                .padding(14)
                .haloDarkCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var handoffPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("WHAT HALO DOES")

            VStack(spacing: 0) {
                previewRow(icon: "link", title: "Keeps context", detail: "Property, unit and source maintenance job stay linked.")
                divider
                previewRow(icon: "square.stack.3d.up.fill", title: "Creates Turn work", detail: "A new unassigned Turn Handoff job appears ready for pickup.")
                divider
                previewRow(icon: "person.crop.circle.badge.checkmark", title: "No manager reassignment", detail: "The Turns side owns the next pickup action.")
            }
            .padding(.horizontal, 16)
            .haloDarkCard()
        }
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            Button {
                submit()
            } label: {
                HStack {
                    if isQueued {
                        Label("Saved to HALO", systemImage: "checkmark.circle.fill")
                    } else {
                        Text("Send to Turn Team")
                    }
                    Spacer()
                    if !isQueued {
                        Image(systemName: "arrow.right")
                    }
                }
                .font(HaloType.body(15, weight: .bold))
                .padding(.horizontal, 22)
                .frame(height: 58)
                .background(canSubmit ? HaloTheme.lime : Color.white.opacity(0.08))
                .foregroundStyle(canSubmit ? HaloTheme.ink : .white.opacity(0.3))
                .clipShape(Capsule())
            }
            .disabled(!canSubmit || isQueued)

            Text("Works offline. HALO syncs the handoff when service returns.")
                .font(HaloType.body(9, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial.opacity(0.97))
    }

    private var canSubmit: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusedField = nil

        OfflineQueue.shared.enqueue(
            jobID: job.id,
            kind: .turnHandoff,
            payload: [
                "summary": summary.trimmingCharacters(in: .whitespacesAndNewlines),
                "detail": detail.trimmingCharacters(in: .whitespacesAndNewlines),
                "urgency": urgent ? "urgent" : "standard",
                "materialEstimate": materialEstimate.trimmingCharacters(in: .whitespacesAndNewlines)
            ],
            activationToken: session.activationToken,
            context: modelContext
        )

        store.recordHandoff(jobID: job.id)
        withAnimation(.snappy) {
            isQueued = true
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            dismiss()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(HaloType.body(9, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.38))
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.64))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.white.opacity(0.055))
            .clipShape(Capsule())
            .lineLimit(1)
    }

    private func previewRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HaloTheme.lime)
                .frame(width: 26, height: 26)
                .background(HaloTheme.lime.opacity(0.09))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(HaloType.body(12, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(HaloType.body(10))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.07))
    }
}

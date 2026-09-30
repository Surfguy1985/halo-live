import ActivityKit
import SwiftUI
import WidgetKit

@main
struct HaloFieldWidgets: WidgetBundle {
    var body: some Widget {
        HaloJobLiveActivity()
    }
}

struct HaloJobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HaloJobActivityAttributes.self) { context in
            LockScreenJobView(context: context)
                .activityBackgroundTint(Color(red: 7/255, green: 16/255, blue: 29/255))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UNIT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.unit)
                            .font(.headline.weight(.bold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(red: 185/255, green: 1, blue: 102/255))
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.propertyName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        ProgressView(value: context.state.progress)
                            .tint(Color(red: 185/255, green: 1, blue: 102/255))
                        Text(context.state.nextAction)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color(red: 185/255, green: 1, blue: 102/255))
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))")
                    .font(.caption2.monospacedDigit().weight(.bold))
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color(red: 185/255, green: 1, blue: 102/255))
            }
            .keylineTint(Color(red: 185/255, green: 1, blue: 102/255))
        }
    }
}

private struct LockScreenJobView: View {
    let context: ActivityViewContext<HaloJobActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 185/255, green: 1, blue: 102/255))
                    .frame(width: 48, height: 48)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 11/255, green: 13/255, blue: 18/255))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("UNIT \(context.attributes.unit) · \(context.attributes.propertyName)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(context.attributes.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                ProgressView(value: context.state.progress)
                    .tint(Color(red: 185/255, green: 1, blue: 102/255))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("(Int(context.state.progress * 100))%")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color(red: 185/255, green: 1, blue: 102/255))
                Text(context.state.nextAction)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .padding(14)
    }
}

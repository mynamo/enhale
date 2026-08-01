import SwiftUI

/// Shown once, immediately before the iOS HealthKit permission dialog, to
/// explain in plain language what enhale reads and why. Apple looks favorably on
/// a "pre-permission" screen like this, and it measurably reduces the number of
/// users who deny the request because the system dialog alone lacks context.
struct HealthPermissionPrimer: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.pink)
                        Text("Connect Apple Health")
                            .font(.title).bold()
                        Text("enhale can read a few kinds of health data so it can connect what you eat to how your body responds.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        row("figure.run", "Workouts",
                            "Type, duration, and energy — to see how food fits around exercise.")
                        row("bed.double.fill", "Sleep",
                            "How long and how well you slept, to correlate with meals.")
                        row("waveform.path.ecg", "Activity & vitals",
                            "Steps, energy, resting heart rate, HRV, and body mass over time.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your health data is used only to give you insights.",
                              systemImage: "lock.fill")
                        Label("Never used for ads. Never sold.",
                              systemImage: "hand.raised.fill")
                        Label("You can turn this off anytime in the Health app.",
                              systemImage: "slider.horizontal.3")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
            }

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now", action: onCancel)
                    .font(.subheadline)
            }
            .padding(24)
        }
    }

    @ViewBuilder private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

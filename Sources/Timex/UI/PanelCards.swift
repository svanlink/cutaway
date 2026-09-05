import SwiftUI

/// The reason nothing is counting, and the way out of it. Lived on the
/// Timer tab; the panel is what a new user opens first, so it lives here.
struct ZeroStateCard: View {
    let state: ZeroStatePolicy.ZeroState
    let createProject: () -> Void

    var body: some View {
        VStack(spacing: DT.s2) {
            Text(ZeroStatePolicy.zeroStateTitle(state))
                .font(DT.bodyBold)
                .foregroundStyle(DT.text)
            Text(ZeroStatePolicy.zeroStateHint(state))
                .font(DT.captionMedium)
                .foregroundStyle(DT.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state == .noProject {
                Button("Create your first project", action: createProject)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.signal)
                    .padding(.top, DT.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DT.s4)
        .padding(.vertical, DT.s3)
        .accessibilityElement(children: .contain)
    }
}

/// Asked once, where the timer lives, with a real decline. Says what the
/// user gets — not what the OS calls the permission.
struct AccessibilityOfferCard: View {
    let enable: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DT.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow project switches instantly")
                    .font(DT.smallSemibold)
                    .foregroundStyle(DT.text)
                Text("Cutaway can read Resolve's window title to switch projects the moment you do. It works without this — switching is just slower.")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: DT.s1) {
                Button("Enable…", action: enable)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.signal)
                Button("Not now", action: dismiss)
                    .buttonStyle(.plain)
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.text3)
            }
            .fixedSize()
        }
        .padding(.horizontal, DT.rowInset)
        .padding(.vertical, DT.s3)
        .overlay(alignment: .top) { Rectangle().fill(DT.strokeSubtle).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

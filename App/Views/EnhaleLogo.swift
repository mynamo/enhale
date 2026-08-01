import SwiftUI

/// The enhale app logo, rounded like an app-icon chip. Reused in nav bars and
/// on the sign-in screen. Backed by the `EnhaleLogo` image asset.
struct EnhaleLogo: View {
    var size: CGFloat = 30

    var body: some View {
        Image("EnhaleLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

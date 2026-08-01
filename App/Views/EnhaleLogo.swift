import SwiftUI

/// The enhale app logo, circular-cropped around the blue border. Reused in nav
/// bars and on the sign-in screen. Backed by the `EnhaleLogo` image asset.
struct EnhaleLogo: View {
    var size: CGFloat = 32

    var body: some View {
        Image("EnhaleLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            // Zoom slightly so the crop hugs the blue circle, trimming the white
            // margin outside it.
            .scaleEffect(1.08)
            .clipShape(Circle())
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

import SwiftUI

extension View {
    /// iPad 등 regular 가로 size class에서 콘텐츠 최대 폭을 제한하고 가운데 정렬.
    /// iPhone(compact)에서는 영향을 주지 않는다.
    func readableContentWidth(_ maxWidth: CGFloat = 700) -> some View {
        modifier(ReadableContentWidthModifier(maxWidth: maxWidth))
    }
}

private struct ReadableContentWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

import SwiftUI

private struct SidebarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func trackSidebarWidth(_ width: Binding<CGFloat>) -> some View {
        modifier(SidebarWidthTracker(width: width))
    }
}

private struct SidebarWidthTracker: ViewModifier {
    @Binding var width: CGFloat
    private let shrinkThreshold: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SidebarWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(SidebarWidthPreferenceKey.self) { measuredWidth in
                guard measuredWidth >= SidebarWidthStorage.minimumWidth else { return }

                if measuredWidth > width + 0.5 {
                    width = measuredWidth
                    SidebarWidthStorage.save(measuredWidth)
                } else if measuredWidth < width - shrinkThreshold {
                    width = measuredWidth
                    SidebarWidthStorage.save(measuredWidth)
                }
            }
    }
}

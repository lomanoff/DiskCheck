import SwiftUI

struct TreeNavigationHeader: View {
    let items: [DiskNode]
    var canGoBack: Bool
    var onBack: () -> Void
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if canGoBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Назад")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Button(item.name) {
                            onSelect(index)
                        }
                        .buttonStyle(.plain)
                        .font(index == items.count - 1 ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(index == items.count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                    }
                }
            }
        }
    }
}

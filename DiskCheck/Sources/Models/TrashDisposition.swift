import Foundation

enum TrashEmptyOperation: Equatable, Sendable {
    case moveToSystemTrash
    case permanentDelete

    var title: String {
        switch self {
        case .moveToSystemTrash: "В системную корзину"
        case .permanentDelete: "Удалить навсегда"
        }
    }
}

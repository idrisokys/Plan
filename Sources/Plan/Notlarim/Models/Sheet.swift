import Foundation

/// Ana pencerenin üstünde açılan sayfalar (sheet).
enum Sheet: Int, Identifiable {
    case folder, move, placeD
    var id: Int { rawValue }
}

import SwiftUI
import AppKit

/// Pencerenin üst satırı (trafik ışıklarıyla aynı hizada). Sistem araç çubuğu (NSToolbar) kullanılmaz:
/// pencere daraltılınca simgeleri "»" menüsüne gizliyordu. Bu satır içeriğin parçasıdır, simgeler hiç kaybolmaz.
struct TitleBarRow<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 76, height: 1)      // kırmızı / sarı / yeşil düğmelerin yeri
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.trailing, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(NT.bg)
    }
}

extension TitleBarRow where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}

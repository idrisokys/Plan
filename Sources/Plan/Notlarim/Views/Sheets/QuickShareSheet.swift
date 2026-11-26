import SwiftUI
import AppKit

/// Android'deki Paylaş penceresi: seçili notların kaynak dosyaları (.txt / .url) Hızlı Paylaş ile açık cihaza gönderilir.
struct QuickShareSheet: View {
    @ObservedObject private var qs = QuickShare.shared
    let files: [URL]
    let onClose: () -> Void

    /// Hedef klasör: İndir → karşı cihazın /Download klasörü, Link → /Link klasörü
    @State private var pickedDownload = false      // varsayılan: Link seçili
    @State private var searching = true
    @State private var searchToken = 0

    private var toLink: Bool { linkAllowed && !pickedDownload }

    /// Link klasörüne yalnızca not dosyaları (.url / .txt) gider.
    private var linkAllowed: Bool {
        files.allSatisfy { ["url", "txt"].contains($0.pathExtension.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Hızlı Paylaş", "Quick Share") + (files.count > 1 ? " (\(files.count))" : ""))
                    .font(.system(size: 16)).foregroundStyle(NT.onSurface)
                Spacer()
                IconBtn(MI.refresh, help: L("Cihazları yenile", "Refresh devices")) { refresh() }
            }
            HStack(spacing: 40) {
                radio(L("İndir", "Download"), selected: !toLink) { pickedDownload = true }
                radio("Link", selected: toLink) { if linkAllowed { pickedDownload = false } }
                    .opacity(linkAllowed ? 1 : 0.38)
                Spacer()
            }
            .padding(.vertical, 2)
            if qs.devices.isEmpty {
                if searching {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(L("Cihazlar aranıyor…", "Searching for devices…")).foregroundStyle(NT.onSurface)
                    }
                } else {
                    Text(L("Açık cihaz bulunamadı (yenilemek için ⟳ simgesine basın)", "No open device found (press ⟳ to refresh)"))
                        .foregroundStyle(NT.onSurfaceVariant)
                }
                Text(L("Karşı cihazda Hızlı Paylaş açık olmalı.", "Quick Share must be on on the other device."))
                    .font(.system(size: 16)).foregroundStyle(NT.onSurfaceVariant)
            } else {
                VStack(spacing: 0) {
                    ForEach(qs.devices) { d in
                        HStack(spacing: 12) {
                            Circle().fill(NT.online).frame(width: 8, height: 8)
                            Text(d.name).font(.system(size: 16)).foregroundStyle(NT.onSurface).lineLimit(1)
                            Spacer()
                            if qs.sendingTo.contains(d.id) { ProgressView().controlSize(.small) }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { send(d) }
                    }
                }
            }
            if let i = qs.info {
                Text(i.text)
                    .font(.system(size: 16))
                    .foregroundStyle(i.kind == .failed ? NT.error : NT.onSurfaceVariant)
            }
            HStack {
                Spacer()
                Button(L("Kapat", "Close")) { close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 340)
        .background(NT.dialog)
        .onAppear {
            qs.info = nil
            qs.ensureRunning()          // "Hızlı Paylaş kapalı" ekranı yok: kendiliğinden açılır, cihazlar aranır
            armSearchTimeout()
        }
        .onChange(of: qs.info) { i in
            // Gönderim bitince pencere kısa süre sonra kapanır
            if i?.kind == .sent { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { close() } }
        }
    }

    /// Yuvarlak seçimli seçenek (seçiliyken dolu daire, değilken halka).
    private func radio(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(NT.onSurface, lineWidth: 2).frame(width: 22, height: 22)
                    if selected { Circle().fill(NT.onSurface).frame(width: 22, height: 22) }
                }
                Text(title).font(.system(size: 16)).foregroundStyle(NT.onSurface)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Birkaç saniye içinde cihaz çıkmazsa "bulunamadı" gösterilir.
    private func armSearchTimeout() {
        searching = true
        searchToken += 1
        let t = searchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if t == searchToken { searching = false } }
    }

    private func refresh() {
        qs.refreshDevices()
        armSearchTimeout()
    }

    private func send(_ d: QSDevice) {
        if qs.sendingTo.contains(d.id) { return }
        qs.send(files, to: d, toLink: toLink)
    }

    private func close() { onClose() }
}

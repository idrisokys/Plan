import SwiftUI
import AppKit

/// Android'deki Paylaş penceresi: seçili notların kaynak dosyaları (.txt / .url) Hızlı Paylaş ile açık cihaza gönderilir.
struct QuickShareSheet: View {
    @ObservedObject private var qs = QuickShare.shared
    let files: [URL]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Hızlı Paylaş", "Quick Share") + (files.count > 1 ? " (\(files.count))" : ""))
                .font(.system(size: 20)).foregroundStyle(NT.onSurface)
            if !qs.running {
                Text(L("Hızlı Paylaş kapalı. Cihazları bulmak için açın.", "Quick Share is off. Turn it on to find devices."))
                    .foregroundStyle(NT.onSurface)
                Button(L("Aç", "Turn on")) { qs.start() }
            } else if qs.devices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L("Cihazlar aranıyor…", "Searching for devices…")).foregroundStyle(NT.onSurface)
                }
                Text(L("Karşı cihazda Hızlı Paylaş açık olmalı.", "Quick Share must be on on the other device."))
                    .font(.footnote).foregroundStyle(NT.onSurfaceVariant)
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
                    .font(.footnote)
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
        .onAppear { qs.info = nil }
        .onChange(of: qs.info) { i in
            // Gönderim bitince pencere kısa süre sonra kapanır
            if i?.kind == .sent { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { close() } }
        }
    }

    private func send(_ d: QSDevice) {
        if qs.sendingTo.contains(d.id) { return }
        qs.send(files, to: d)
    }

    private func close() { onClose() }
}

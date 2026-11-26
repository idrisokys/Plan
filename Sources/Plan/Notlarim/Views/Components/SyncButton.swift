import SwiftUI

/// Link klasörünü açık cihazlarla eşitler (⇄). Alt çubukta yenile simgesinin solunda durur.
/// Pencerede cihazlar işaretlenir, eşitleme yöntemi seçilir. Hızlı Paylaş kapalıysa dokununca kendiliğinden açılır.
struct SyncButton: View {
    @ObservedObject private var qs = QuickShare.shared
    @State private var open = false
    @State private var picked = Set<String>()

    var body: some View {
        Group {
            if qs.syncing {
                ProgressView().controlSize(.small).frame(width: 34, height: 34)
            } else {
                IconBtn(MI.sync, help: L("Cihazlarla eşitle (Link klasörü)", "Sync with devices (Link folder)")) {
                    qs.ensureRunning()
                    open.toggle()
                }
            }
        }
        .popover(isPresented: $open, arrowEdge: .top) { popover }
    }

    private var popover: some View {
        let chosen = qs.devices.filter { picked.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("Nasıl eşitlensin?", "How to sync?")).font(.headline)
            if qs.devices.isEmpty {
                Text(L("Açık cihaz bulunamadı", "No open device found")).foregroundStyle(.secondary)
            } else {
                ForEach(qs.devices) { d in
                    Toggle(d.name, isOn: Binding(
                        get: { picked.contains(d.id) },
                        set: { if $0 { picked.insert(d.id) } else { picked.remove(d.id) } }))
                }
            }
            Divider()
            ForEach([(1, L("Bu cihaza göre", "Based on this device")),
                     (2, L("Karşıdaki cihaza göre", "Based on the other device")),
                     (0, L("İki cihazda aynı olsun", "Make both the same"))], id: \.0) { m in
                Button(m.1) { open = false; qs.sync(mode: m.0, with: chosen) }
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(14).frame(minWidth: 230)
    }
}

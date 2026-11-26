import AppKit
import Vision
import CoreGraphics

/// Ekrandan alan seçip içindeki yazıyı (resim ya da metin fark etmez) okur ve panoya kopyalar.
/// Seçim: sistemin kendi seçim aracı (`screencapture -i`; Esc ile iptal). Okuma: Vision (cihaz üstünde, çevrimdışı).
/// Not: macOS ilk kullanımda "Ekran Kaydı" izni ister (Sistem Ayarları → Gizlilik ve Güvenlik).
@MainActor
enum ScreenOCR {
    private static var busy = false

    static func run() {
        guard !busy else { return }
        // İzin yoksa seçilen alan boş (yalnız duvar kâğıdı) çıkar; baştan iste.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            HUD.show(L("Ekran Kaydı izni verin, sonra tekrar deneyin", "Allow Screen Recording, then try again"))
            return
        }
        busy = true
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-\(UUID().uuidString).png")
        Task.detached(priority: .userInitiated) {
            let captured = capture(to: tmp)
            let text = captured ? recognize(tmp) : nil
            try? FileManager.default.removeItem(at: tmp)
            await MainActor.run {
                busy = false
                guard captured else { return }          // seçim iptal edildi (Esc)
                guard let text, !text.isEmpty else {
                    HUD.show(L("Metin bulunamadı", "No text found")); return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                HUD.show(L("Metin kopyalandı", "Text copied") + " (\(text.count))")
            }
        }
    }

    /// Fare ile alan seçtirir; seçim yapılırsa PNG olarak kaydeder. Esc → false.
    nonisolated private static func capture(to url: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", url.path]        // -i: alan seç, -x: deklanşör sesi yok
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated private static func recognize(_ url: URL) -> String? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            req.automaticallyDetectsLanguage = true
            // Türkçe destekleniyorsa öncelik ver; değilse otomatik algılama kalır.
            let sup = (try? req.supportedRecognitionLanguages()) ?? []
            let want = ["tr-TR", "en-US"].filter { sup.contains($0) }
            if !want.isEmpty { req.recognitionLanguages = want }
        }
        let h = VNImageRequestHandler(url: url, options: [:])
        guard (try? h.perform([req])) != nil, let obs = req.results else { return nil }
        // Okuma sırası: yukarıdan aşağı (Vision'da y alttan başlar)
        let lines = obs.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
        let t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

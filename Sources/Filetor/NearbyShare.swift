import Foundation

/// Filetor'un Paylaş menüsünde "açık cihazlar" listesini göstermesi için köprü.
/// Filetor ayrı bir kitaplık olduğundan Hızlı Paylaş'a doğrudan erişemez; Plan açılışta bu alanları doldurur.
@MainActor
public enum NearbyShare {
    public struct Device {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    /// Şu an ağda bulunan açık cihazlar (Hızlı Paylaş kapalıysa boş).
    public static var devices: () -> [Device] = { [] }
    /// Dosyaları (klasörler zip'lenir) verilen cihaza gönderir.
    public static var send: ([URL], String) -> Void = { _, _ in }
    /// Cihaz seçme panelini açar (Hızlı Paylaş'ı da başlatır).
    public static var openPanel: ([URL]) -> Void = { _ in }
}

import Foundation

/// Kodda birden fazla yerde geçen sabitler. (Info.plist ve ShareExtension bunları ayrıca yazar;
/// değiştirirseniz kök `Info.plist` ve `ShareExtension/` içindekileri de güncelleyin.)
enum AppInfo {
    static let bundleID = "github.idrisokys.plan"
    static let shareExtensionID = bundleID + ".share"
    /// Adres şeması: plan://add?t=… ve plan://search?q=…
    static let urlScheme = "plan"
    static let supportFolderName = "Plan"
}

import Foundation

/// Kodda birden fazla yerde geçen sabitler. (Info.plist ve ShareExtension bunları ayrıca yazar;
/// değiştirirseniz kök `Info.plist` ve `ShareExtension/` içindekileri de güncelleyin.)
enum AppInfo {
    static let bundleID = "io.github.idrisokys.notmenu"
    static let shareExtensionID = bundleID + ".share"
    /// Yeni adres şeması. Eski Chrome eklentisi / Paylaş eklentisi `linkcepte://` kullandığı için o da kabul edilir.
    static let urlScheme = "notlarim"
    static let legacyURLScheme = "linkcepte"
    static let supportFolderName = "Notlarım"
    static let contactEmail = "sislivadi@gmail.com"
    static let githubURL = URL(string: "https://github.com/idrisokys/")!
}

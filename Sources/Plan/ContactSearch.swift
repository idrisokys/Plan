import Foundation
import Contacts

/// Arama sonucunda gösterilen kişi (macOS Rehber).
struct ContactHit: Identifiable, Sendable {
    let id: String            // CNContact.identifier
    let name: String
    let phone: String
    let email: String
    let org: String

    /// Satırın alt yazısı: telefon, yoksa e-posta, yoksa kurum.
    var detail: String {
        if !phone.isEmpty { return phone }
        if !email.isEmpty { return email }
        return org
    }
}

/// Rehber araması. İzin ilk aramada istenir; reddedilirse sessizce boş döner.
enum ContactSearch {
    private static let store = CNContactStore()

    private static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor
    ]

    /// İzin var mı? Henüz sorulmadıysa sorar.
    private static func authorized() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return true
        case .notDetermined:
            return (try? await store.requestAccess(for: .contacts)) ?? false
        default: return false
        }
    }

    /// Ada (ve rakam yazıldıysa telefona) göre en çok `limit` kişi döndürür.
    static func search(_ query: String, limit: Int = 3) async -> [ContactHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, await authorized() else { return [] }

        return await Task.detached(priority: .userInitiated) { () -> [ContactHit] in
            var found: [CNContact] = []
            var seen = Set<String>()
            func add(_ list: [CNContact]) {
                for c in list where seen.insert(c.identifier).inserted { found.append(c) }
            }

            // Ada göre (Rehber'in kendi eşleştirmesi: ad, soyad, ikinci ad…)
            if let r = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: q),
                                                 keysToFetch: keys) { add(r) }

            // Çoğunlukla rakam yazıldıysa telefona göre
            let digits = q.filter { $0.isNumber }
            if digits.count >= 3, digits.count * 2 >= q.count {
                let req = CNContactFetchRequest(keysToFetch: keys)
                req.unifyResults = true
                try? store.enumerateContacts(with: req) { c, stop in
                    if c.phoneNumbers.contains(where: {
                        $0.value.stringValue.filter { $0.isNumber }.contains(digits)
                    }) { add([c]) }
                    if found.count >= limit * 3 { stop.pointee = true }
                }
            }

            return found.prefix(limit).map { c in
                let name = CNContactFormatter.string(from: c, style: .fullName)
                    ?? (c.organizationName.isEmpty ? "—" : c.organizationName)
                return ContactHit(id: c.identifier,
                                  name: name,
                                  phone: c.phoneNumbers.first?.value.stringValue ?? "",
                                  email: (c.emailAddresses.first?.value as String?) ?? "",
                                  org: c.organizationName)
            }
        }.value
    }
}

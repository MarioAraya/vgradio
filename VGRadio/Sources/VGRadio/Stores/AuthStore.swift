import Foundation
import Observation

@Observable
final class AuthStore {
    private(set) var currentUser: UserProfile?
    var isLoggedIn: Bool { currentUser != nil }

    private static let recentEmailsKey = "vgradio.recentEmails"
    private static let maxRecentEmails = 5

    private(set) var recentEmails: [String] = UserDefaults.standard.stringArray(forKey: recentEmailsKey) ?? []

    static var recentEmailsPreview: [String] { UserDefaults.standard.stringArray(forKey: recentEmailsKey) ?? [] }

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        currentUser = try? await APIClient.shared.me()
    }

    func login(email: String, password: String) async throws {
        currentUser = try await APIClient.shared.login(email: email, password: password)
        rememberEmail(email)
    }

    func forgetEmail(_ email: String) {
        recentEmails.removeAll { $0 == email }
        UserDefaults.standard.set(recentEmails, forKey: Self.recentEmailsKey)
    }

    private func rememberEmail(_ email: String) {
        recentEmails.removeAll { $0 == email }
        recentEmails.insert(email, at: 0)
        if recentEmails.count > Self.maxRecentEmails { recentEmails.removeLast() }
        UserDefaults.standard.set(recentEmails, forKey: Self.recentEmailsKey)
    }

    func logout() async {
        try? await APIClient.shared.logout()
        currentUser = nil
    }
}

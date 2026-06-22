import Foundation
import Observation

@Observable
final class AuthStore {
    private(set) var currentUser: UserProfile?
    var isLoggedIn: Bool { currentUser != nil }

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        currentUser = try? await APIClient.shared.me()
    }

    func login(email: String, password: String) async throws {
        currentUser = try await APIClient.shared.login(email: email, password: password)
    }

    func logout() async {
        try? await APIClient.shared.logout()
        currentUser = nil
    }
}

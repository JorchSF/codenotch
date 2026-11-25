import AppKit
import Foundation
import os

/// Reads Cursor usage as the account already signed in on this Mac.
///
/// This replaced a WebView sign-in, and the reason is worth keeping: signing
/// into cursor.com inside the app created a second, empty account, so the notch
/// faithfully reported zero usage for someone who was not the user. Borrowing
/// the editor's own session — or, when that is missing, the `cursor-agent`
/// login — removes the question. There is only ever one account, the one
/// actually being used.
actor CursorLocalProvider: UsageProvider {
    nonisolated let id = "cursor"
    nonisolated let displayName = "Cursor"
    nonisolated let glyph = ProviderGlyph.cursor

    private let endpoint = URL(string: "https://cursor.com/api/usage-summary")!
    private let session: URLSession
    private let editorCredentials: @Sendable () throws -> CursorCredentials
    private let agentCredentials: @Sendable () throws -> CursorCredentials

    /// The two loaders are injected so tests can stand in for the editor store
    /// and the keychain; production reads both for real.
    init(session: URLSession = .shared,
         editorCredentials: @escaping @Sendable () throws -> CursorCredentials = {
             try CursorCredentials.load(from: CursorCredentials.storeURL)
         },
         agentCredentials: @escaping @Sendable () throws -> CursorCredentials = {
             try CursorCredentials.loadAgent()
         }) {
        self.session = session
        self.editorCredentials = editorCredentials
        self.agentCredentials = agentCredentials
    }

    nonisolated var signInRoute: SignInRoute {
        // Bundle-id lookup, not a hard-coded /Applications path: Cursor can
        // live in ~/Applications, and a miss here would hide the Open button
        // from someone who does have the editor.
        let installed = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CursorCredentials.bundleID
        ) != nil
        return CursorCredentials.signInRoute(editorInstalled: installed)
    }

    nonisolated func account() -> ProviderAccount? { CursorCredentials.account() }

    nonisolated func forgetCachedCredential() { CursorCredentials.forgetCachedAgent() }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // Re-read every time: the editor rotates this, and holding a stale copy
        // would mean signing ourselves out for no reason. The agent token is
        // cached inside `CursorAgentKeychain` so the keychain is not.
        //
        // Editor first, agent second — and the agent is reached not only when
        // the editor store is missing or signed out, but also when the web
        // endpoint *rejects* the editor's token. Recent Cursor builds keep an
        // access token in `state.vscdb` that `/api/usage-summary` answers with
        // 401, so a signed-in editor hid Cursor from the notch while signing
        // it out (which drops that token) brought it back via `cursor-agent`.
        let body: String
        do {
            body = try await usageSummary(with: try editorCredentials())
        } catch UsageProviderError.needsAuth {
            do {
                body = try await usageSummary(with: try agentCredentials())
            } catch UsageProviderError.needsAuth {
                // A rejected token is the one signal the copy in hand is wrong
                // despite not having expired — signing into a different CLI
                // account replaces the keychain item. Drop it so the next read
                // asks macOS again.
                CursorCredentials.forgetCachedAgent()
                throw UsageProviderError.needsAuth
            }
        }

        let windows = try CursorUsage.windows(fromJSON: body)
        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: CursorUsage.headlineID(in: windows),
            plan: CursorUsage.plan(fromJSON: body) ?? account()?.plan?.nonEmptyPlan
        )
    }

    /// One call to `/api/usage-summary`. 401/403 is `needsAuth` so the caller
    /// can move on to the next session; anything else non-2xx is an error.
    private func usageSummary(with credentials: CursorCredentials) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.setValue(credentials.sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 || status == 403 {
            throw UsageProviderError.needsAuth
        }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        Log.usage.debug("cursor usage -> \(body.prefix(900), privacy: .public)")
        return body
    }
}

// GCManager.swift — #51 Game Center leaderboards.
// Per-track best laps are submitted as centisecond scores (leaderboards configured
// "lowest score wins" in App Store Connect — setup steps in README):
//   sgs_classic_best  (Meadow Loop) · sgs_ridge_best  (Figure-8 Ridge)
//
// Compiled only with the GAMECENTER_ENABLED swift flag (see project.yml — off by
// default) because leaderboards need the Game Center capability (paid Developer
// Program). With the flag ON but no entitlement, authenticateHandler returns an
// error → `authenticated` stays false → the results-screen button stays hidden:
// a graceful no-op. With the flag OFF the class is an empty stub.
import Foundation

#if GAMECENTER_ENABLED
import GameKit

final class GCManager: NSObject, ObservableObject, GKGameCenterControllerDelegate {
    static let shared = GCManager()
    static let leaderboardClassic = "sgs_classic_best"
    static let leaderboardRidge = "sgs_ridge_best"

    @Published private(set) var authenticated = false

    private override init() {}

    /// Silent sign-in on launch: if Game Center would need a login sheet we simply
    /// stay unauthenticated (fail quiet — never interrupt the game).
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            DispatchQueue.main.async {
                self?.authenticated = (error == nil && GKLocalPlayer.local.isAuthenticated)
            }
        }
    }

    /// Every finished lap is submitted; Game Center keeps the best (lowest) score.
    func submitBestLap(trackId: String, seconds: Double) {
        guard authenticated else { return }
        let board = trackId == "ridge" ? Self.leaderboardRidge : Self.leaderboardClassic
        let centiseconds = Int((seconds * 100).rounded())
        GKLeaderboard.submitScore(centiseconds, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [board]) { _ in /* fail silent */ }
    }

    /// Results-screen 🏆: present the native Game Center dashboard.
    func showDashboard() {
        guard authenticated,
              let root = UIApplication.shared.connectedScenes
                  .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        let gc = GKGameCenterViewController(state: .dashboard)
        gc.gameCenterDelegate = self
        presenter.present(gc, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

#else

/// Stub when GAMECENTER_ENABLED is off: same API, everything a no-op.
final class GCManager: ObservableObject {
    static let shared = GCManager()
    @Published private(set) var authenticated = false
    private init() {}
    func authenticate() {}
    func submitBestLap(trackId: String, seconds: Double) {}
    func showDashboard() {}
}

#endif

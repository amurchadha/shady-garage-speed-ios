// CloudSync.swift — #52 iCloud save sync via NSUbiquitousKeyValueStore.
// The save blob mirrors to the ubiquitous store on every save(); on launch and on
// didChangeExternally the newer blob (by `savedAtMs`) wins — last-write-wins.
//
// Compiled only with the ICLOUD_ENABLED swift flag (see project.yml — off by
// default) because syncing requires the iCloud capability + key-value store
// entitlement (paid Developer Program; setup steps in README). With the flag ON
// but no entitlement, NSUbiquitousKeyValueStore simply never delivers changes —
// a silent no-op. With the flag OFF the class is an empty stub.
import Foundation

#if ICLOUD_ENABLED

final class CloudSync {
    static let shared = CloudSync()
    /// Set by AppState: re-read the blob into GameState + toast. Runs on main.
    var onMerged: (() -> Void)?

    private let store = NSUbiquitousKeyValueStore.default
    private let key = "sgs_save"

    private init() {}

    /// Launch: observe external changes, then run the initial merge.
    func start() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main) { [weak self] _ in
                self?.pull()
            }
        store.synchronize()
        pull()
    }

    /// Local save → cloud (system rate-limits the actual upload).
    func push(json: Data) {
        store.set(json, forKey: key)
        store.synchronize()
    }

    /// Last-write-wins by savedAtMs: a strictly newer remote blob replaces local.
    private func pull() {
        guard let remote = store.data(forKey: key),
              let raw = try? JSONDecoder().decode(RawSave.self, from: remote) else { return }
        let remoteMs = raw.savedAtMs ?? 0
        let localMs: Int64 = {
            guard let j = UserDefaults.standard.data(forKey: "sgs_save"),
                  let r = try? JSONDecoder().decode(RawSave.self, from: j) else { return 0 }
            return r.savedAtMs ?? 0
        }()
        guard remoteMs > localMs else { return }
        UserDefaults.standard.set(remote, forKey: "sgs_save")
        onMerged?() // AppState: game.load() + "Synced from your other device"
    }
}

#else

/// Stub when ICLOUD_ENABLED is off: same API, everything a no-op.
final class CloudSync {
    static let shared = CloudSync()
    var onMerged: (() -> Void)?
    private init() {}
    func start() {}
    func push(json: Data) {}
}

#endif

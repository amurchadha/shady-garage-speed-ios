// AppDelegate.swift — UIApplicationDelegate bridge for the SwiftUI lifecycle:
// #59 per-phase orientation mask, #54 home-screen quick action, and the
// DeepLinkCenter shared by quick actions and #58 App Intents.
import UIKit

/// App-internal deep links ("track-select"): posted over NotificationCenter for a
/// warm start, stashed in `pending` for a cold start (AppState drains on init).
enum DeepLinkCenter {
    static let name = Notification.Name("sgs.deeplink")
    static var pending: String?

    static func post(_ link: String) {
        pending = link
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["link": link])
    }
}

/// #59 orientation setting (Settings → Orientation, persisted in UserDefaults).
enum OrientationMode: String, CaseIterable {
    case auto           // follow the device (Info.plist set)
    case portrait       // portrait only, everywhere
    case landscapeRace  // landscape during a race, portrait elsewhere

    var label: String {
        switch self {
        case .auto:          return "Auto"
        case .portrait:      return "Portrait"
        case .landscapeRace: return "Landscape race"
        }
    }
}

enum OrientationLock {
    private static let key = "sgs_orientation"

    static var mode: OrientationMode {
        get { OrientationMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            apply()
        }
    }

    /// Set by AppState.phase didSet; only the race phase unlocks landscape.
    static var inRace = false

    static var mask: UIInterfaceOrientationMask {
        switch mode {
        case .auto:          return .all
        case .portrait:      return .portrait
        case .landscapeRace: return inRace ? .landscape : .portrait
        }
    }

    /// Re-apply the mask to every window scene (phase change or setting change).
    static func apply() {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let ws = scene as? UIWindowScene else { continue }
                ws.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
                ws.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// #59: the orientation mask can only narrow the Info.plist set.
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    /// Cold start via a quick action: stash the deep link; AppState drains it.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let link = options.shortcutItem.flatMap(Self.deepLink(for:)) {
            DeepLinkCenter.pending = link
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    /// #54 warm-start quick action ("Start a Race" → track select).
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let link = Self.deepLink(for: shortcutItem) else { return false }
        DeepLinkCenter.post(link)
        return true
    }

    static func deepLink(for item: UIApplicationShortcutItem) -> String? {
        item.type == "com.noshu.shadygaragespeed.startrace" ? "track-select" : nil
    }
}

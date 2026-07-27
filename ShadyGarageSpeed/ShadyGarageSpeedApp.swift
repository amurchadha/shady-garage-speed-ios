// ShadyGarageSpeedApp.swift — app entry point + root phase switcher.
import SwiftUI

@main
struct ShadyGarageSpeedApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var debugApplied = false

    /// Debug `-dts ax1..ax5`: force a huge content size category for screenshots
    /// (ax5 = accessibilityExtraExtraExtraLarge).
    private var debugSizeCategory: ContentSizeCategory? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-dts"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "ax1": return .accessibilityMedium
        case "ax2": return .accessibilityLarge
        case "ax3": return .accessibilityExtraLarge
        case "ax4": return .accessibilityExtraExtraLarge
        case "ax5": return .accessibilityExtraExtraExtraLarge
        default:    return nil
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch app.phase {
            case .menu:
                GarageBackground(attract: true)
                MenuView()
            case .setup:
                GarageBackground(attract: true)
                SetupView()
            case .garage:
                GarageView(scene: app.garageScene, game: app.game)
            case .build:
                BuildView(scene: app.buildScene, game: app.game)
            case .race:
                RaceView(scene: app.raceScene, thermal: app.thermalLimited)
            case .results:
                if app.showPhotoMode {
                    // #25 photo mode: scene + orbit cam, UI hidden, tap exits
                    ZStack {
                        SceneKitView(controller: app.raceScene, fps: 30, thermal: app.thermalLimited)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)
                        Text("Tap anywhere to exit photo mode")
                            .font(sgsFont(13, .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                            .padding(10)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Capsule())
                            .padding(.bottom, 28)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .accessibilityIdentifier("photo-exit-hint")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { app.exitPhotoMode() }
                    .accessibilityIdentifier("photo-mode")
                } else {
                    ResultsView()
                }
            }
            VStack {
                Spacer()
                HStack {
                    ToastOverlay(center: app.toasts)
                        .padding(.leading, 10)
                        .padding(.bottom, 10)
                    Spacer()
                }
            }
            .allowsHitTesting(false) // toasts are display-only; never block taps
        }
        .modifier(SizeCategoryOverride(category: debugSizeCategory))
        .onAppear { applyDebugArgOnce() }
        .onChange(of: scenePhase) { _, phase in
            // freeze all sims + drop inputs/audio while inactive/backgrounded
            app.setActive(phase == .active)
        }
    }

    /// The garage scene also runs (in attract mode) behind the menu/setup screens.
    private func GarageBackground(attract: Bool) -> some View {
        ZStack {
            SceneKitView(controller: app.garageScene, fps: 30, thermal: app.thermalLimited)
                .ignoresSafeArea()
                .accessibilityHidden(true) // visual-only backdrop
            Color(red: 8 / 255, green: 10 / 255, blue: 16 / 255).opacity(0.55)
                .ignoresSafeArea()
        }
    }

    private func applyDebugArgOnce() {
        guard !debugApplied else { return }
        debugApplied = true
        app.applyDebugArgs(ProcessInfo.processInfo.arguments)
    }
}

/// Applies a forced size category only when `-dts` is passed (system setting untouched otherwise).
private struct SizeCategoryOverride: ViewModifier {
    let category: ContentSizeCategory?
    func body(content: Content) -> some View {
        if let category {
            content.environment(\.sizeCategory, category)
        } else {
            content
        }
    }
}

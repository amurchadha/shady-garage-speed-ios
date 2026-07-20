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
                RaceView(scene: app.raceScene)
            case .results:
                ResultsView()
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
        .onAppear { applyDebugArgOnce() }
        .onChange(of: scenePhase) { _, phase in
            // freeze all sims + drop inputs/audio while inactive/backgrounded
            app.setActive(phase == .active)
        }
    }

    /// The garage scene also runs (in attract mode) behind the menu/setup screens.
    private func GarageBackground(attract: Bool) -> some View {
        ZStack {
            SceneKitView(controller: app.garageScene)
                .ignoresSafeArea()
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

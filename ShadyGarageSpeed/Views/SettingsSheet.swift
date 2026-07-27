// SettingsSheet.swift — ⚙️ settings (web #78): music/SFX buses, reduced-motion
// override, difficulty, save export/restore, reset-everything (double-confirm).
import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var game: GameState
    @ObservedObject private var audio = AudioEngine.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showExporter = false

    private static let diffs = ["chill", "normal", "cutthroat"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("⚙️ Settings")
                        .font(.title3.bold())
                    Spacer()
                    SGSButton(title: "Close", ghost: true, small: true, a11y: "settings-close") { dismiss() }
                }

                // audio buses (live sliders — #37)
                HStack(spacing: 10) {
                    Text("Music")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $audio.musicVol, in: 0...1)
                        .accessibilityIdentifier("set-music")
                }
                HStack(spacing: 10) {
                    Text("SFX")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $audio.sfxVol, in: 0...1)
                        .accessibilityIdentifier("set-sfx")
                }

                // reduced motion override (overrides the OS setting when ON)
                Toggle("Reduce motion",
                       isOn: Binding(get: { A11y.userOverride ?? UIAccessibility.isReduceMotionEnabled },
                                     set: { A11y.userOverride = $0 }))
                    .accessibilityIdentifier("set-rm")

                // difficulty (#61)
                HStack(spacing: 8) {
                    Text("Difficulty")
                    Spacer()
                    ForEach(Self.diffs, id: \.self) { d in
                        SGSButton(title: d.capitalized,
                                  ghost: game.difficulty != d, small: true,
                                  a11y: "set-diff-\(d)") {
                            game.difficulty = d
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.15))

                // save tools
                SGSButton(title: "Export save (JSON)", small: true, a11y: "set-export") {
                    showExporter = true
                }
                SGSButton(title: "Restore previous save", ghost: true, small: true,
                          disabled: !game.hasBackup(), a11y: "set-restore",
                          hint: "Loads the save kept before the last overwrite") {
                    if game.restorePrevious() {
                        app.toasts.push("Previous save restored", .good)
                    }
                }
                SGSButton(title: "Reset everything", small: true, tint: Color.sgsBad,
                          a11y: "set-reset",
                          hint: "Wipes the save and backup") {
                    confirmReset = true
                }
            }
            .padding(20)
        }
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .alert("Reset everything?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                game.resetEverything()
                app.goMenu()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wipes the save AND the backup. This cannot be undone.")
        }
        .sheet(isPresented: $showExporter) {
            ShareSheet(text: game.exportSaveJSON())
        }
    }
}

/// UIActivityViewController wrapper for the JSON export share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MenuView.swift — main menu + How to Play modal (mirrors #screen-menu / #modal-howto).
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var app: AppState
    @State private var showHowTo = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 18) {
                (Text("SHADY GARAGE ")
                    + Text("&").foregroundStyle(Color.sgsAccent)
                    + Text(" SPEED"))
                    .font(.system(size: 42, weight: .black))
                    .tracking(3)
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
                    .multilineTextAlignment(.center)

                Text("Fix cars. Maybe steal parts. Build a racer.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.sgsMuted)
                    .padding(.bottom, 12)

                VStack(spacing: 12) {
                    SGSButton(title: "New Game", big: true, a11y: "new-game") { app.goSetup() }
                    if app.game.hasSave() {
                        SGSButton(title: "Continue", big: true, a11y: "continue") { app.continueGame() }
                    }
                    SGSButton(title: "How to Play", ghost: true, big: true, a11y: "howto") { showHowTo = true }
                }
                .frame(maxWidth: 320)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.sgsText)
            // sit below the 3D garage sign for most of the attract orbit
            .offset(y: geo.size.height * 0.08)

            if showHowTo {
                HowToModal(show: $showHowTo)
            }
        }
    }
    }
}

struct HowToModal: View {
    @Binding var show: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .onTapGesture { show = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How to Play")
                        .font(.title2.bold())
                    Group {
                        Text("🚗 Customer cars pull into your service bay.")
                        Text("🔍 Tap a part on the car (or use the job panel) to inspect it.")
                        Text("🔧 **Fix** worn parts for safe cash.")
                        Text("🕵️ **Steal** a part to keep it for yourself — play the timing minigame, but watch the **Suspicion** meter. At 100 the customer storms off without paying!")
                        Text("🏗️ Spend cash and stolen parts in the **Build Bay** to upgrade your custom race car.")
                        Text("🏁 Prove it in a **time trial** — faster laps earn bigger prizes.")
                    }
                    .foregroundStyle(Color.sgsMuted)
                    Text("Controls")
                        .font(.headline)
                        .padding(.top, 6)
                    Group {
                        Text("👆 Tap — inspect parts, use panels.")
                        Text("⏱️ Tap the bar or SWAP — lock the stealth minigame marker.")
                        Text("🏎️ Race: hold GAS to accelerate · BRK to brake & reverse · ◀ ▶ steer · NOS to boost · ✕ to forfeit.")
                    }
                    .foregroundStyle(Color.sgsMuted)
                    HStack {
                        Spacer()
                        SGSButton(title: "Close") { show = false }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .background(Color.sgsCard)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1))
                .padding(16)
            }
        }
        .foregroundStyle(Color.sgsText)
    }
}

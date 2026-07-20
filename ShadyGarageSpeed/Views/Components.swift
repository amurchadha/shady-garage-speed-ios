// Components.swift — shared SwiftUI bits: palette, buttons, badges, bars, toasts, hold buttons.
import SwiftUI

// MARK: - palette (mirrors style.css :root)

extension Color {
    init(rgb: Int, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: opacity)
    }
    static let sgsAccent = Color(rgb: 0xff5d3b)
    static let sgsAccentDark = Color(rgb: 0xe04a2c)
    static let sgsPanel = Color(rgb: 0x0f121a, opacity: 0.86)
    static let sgsCard = Color(rgb: 0x1f2430)
    static let sgsCard2 = Color(rgb: 0x262c3a)
    static let sgsText = Color(rgb: 0xf3f4f6)
    static let sgsMuted = Color(rgb: 0x9aa3b2)
    static let sgsGood = Color(rgb: 0x22c55e)
    static let sgsWarn = Color(rgb: 0xeab308)
    static let sgsBad = Color(rgb: 0xef4444)
    static let sgsCyan = Color(rgb: 0x22d3ee)
}

func tierColor(_ tier: Int) -> Color {
    Color(rgb: GameState.tierColors[min(4, max(1, tier))])
}

// MARK: - panel container

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(Color.sgsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 15, y: 10)
    }
}

// MARK: - buttons (mirrors .btn; every tap plays the click blip)

struct SGSButton: View {
    let title: String
    var ghost = false
    var big = false
    var small = false
    var tiny = false
    var tint: Color? = nil
    var disabled = false
    var a11y: String? = nil
    var systemImage: String? = nil // SF Symbol chrome (replaces emoji where set)
    var action: () -> Void = {}

    var body: some View {
        Button {
            if !disabled { AudioEngine.shared.click() }
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: tiny ? 12 : small ? 13 : 15, weight: .bold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: tiny ? 13 : small ? 14 : big ? 18 : 16, weight: .bold))
                }
            }
            .padding(.horizontal, tiny ? 10 : small ? 14 : big ? 30 : 20)
            .padding(.vertical, tiny ? 5 : small ? 7 : big ? 14 : 10)
            .frame(minHeight: big ? 48 : nil)
            .background(ghost ? Color.clear : (tint ?? Color.sgsAccent))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: tiny ? 8 : small ? 10 : 12))
            .overlay(RoundedRectangle(cornerRadius: tiny ? 8 : small ? 10 : 12)
                .stroke(Color.white.opacity(ghost ? 0.35 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.38 : 1)
        .disabled(disabled)
        .accessibilityIdentifier(a11y ?? "")
    }
}

// MARK: - tier badge (mirrors .badge.t1..t4)

struct TierBadge: View {
    let tier: Int
    var body: some View {
        Text(GameState.tierNames[min(4, max(1, tier))])
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tierColor(tier).opacity(0.22))
            .foregroundStyle(tierColor(tier))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tierColor(tier).opacity(0.6), lineWidth: 1))
    }
}

// MARK: - stat bar (build bay)

struct StatBar: View {
    let name: String
    let value: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sgsMuted)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color.sgsAccent)
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, value))) / 100)
                }
            }
            .frame(height: 10)
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, alignment: .trailing)
                .accessibilityIdentifier("stat-\(name.lowercased())")
        }
    }
}

// MARK: - hold-to-press button (race touch controls)

struct HoldButton: View {
    let label: String
    var tint: Color = .white
    var diameter: CGFloat = 64
    var a11y: String? = nil
    @Binding var pressed: Bool
    /// @GestureState auto-resets when the gesture ends OR is cancelled by the
    /// system (home swipe, call banner) — the old onEnded-only approach could
    /// latch the button pressed forever.
    @GestureState private var held = false

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(tint.opacity(held ? 0.85 : 0.4))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
            .scaleEffect(held ? 0.92 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($held) { _, state, _ in state = true }
            )
            .onChange(of: held) { _, v in pressed = v }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(a11y ?? "")
    }
}

// MARK: - speech bubble (owner dialogue)

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Rounded bubble + tail, positioned over the owner avatar (world-projected).
struct SpeechBubble: View {
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white)
                .foregroundStyle(Color(rgb: 0x111827))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            Triangle()
                .fill(Color.white)
                .frame(width: 12, height: 6)
        }
        .accessibilityIdentifier("speech-bubble")
    }
}

/// Floating "+$X" pop that rises and fades (payment juice).
struct CashPopView: View {
    let text: String
    var negative = false
    @State private var rise = false
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(negative ? Color.sgsBad : Color.sgsGood)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .offset(y: rise ? -36 : 0)
            .opacity(rise ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) { rise = true }
            }
    }
}

// MARK: - toasts

struct ToastOverlay: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(center.toasts) { t in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bar(for: t.kind))
                        .frame(width: 4)
                        .padding(.vertical, 4)
                    Text(t.text)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .background(Color.sgsPanel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: center.toasts)
    }

    private func bar(for kind: Toast.Kind) -> Color {
        switch kind {
        case .good: return .sgsGood
        case .bad:  return .sgsBad
        case .warn: return .sgsWarn
        case .info: return .sgsAccent
        }
    }
}

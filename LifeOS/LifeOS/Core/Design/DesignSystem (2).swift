import SwiftUI

// MARK: - Cores e gradientes

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        } else { r = 0.5; g = 0.5; b = 0.5 }
        self.init(red: r, green: g, blue: b)
    }
}

enum Theme {
    static let accent = Color("AccentColor")
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 22

    enum Module {
        case agenda, study, contest, finance, fitness, body, food, growth, docs, security, reports, assistant

        var colors: [Color] {
            switch self {
            case .agenda: [Color(hex: "4F8BFF"), Color(hex: "39C6F4")]
            case .study: [Color(hex: "8B5CF6"), Color(hex: "EC4899")]
            case .contest: [Color(hex: "6366F1"), Color(hex: "8B5CF6")]
            case .finance: [Color(hex: "10B981"), Color(hex: "14B8A6")]
            case .fitness: [Color(hex: "22C55E"), Color(hex: "84CC16")]
            case .body: [Color(hex: "F97316"), Color(hex: "F43F5E")]
            case .food: [Color(hex: "F59E0B"), Color(hex: "F97316")]
            case .growth: [Color(hex: "A855F7"), Color(hex: "6366F1")]
            case .docs: [Color(hex: "64748B"), Color(hex: "475569")]
            case .security: [Color(hex: "0EA5E9"), Color(hex: "14B8A6")]
            case .reports: [Color(hex: "3B82F6"), Color(hex: "8B5CF6")]
            case .assistant: [Color(hex: "7C5CFF"), Color(hex: "C084FC")]
            }
        }
        var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
        var tint: Color { colors[0] }
    }
}

// MARK: - Cartões

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    func gradientCard(_ module: Theme.Module) -> some View {
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(module.gradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .foregroundStyle(.white)
            .shadow(color: module.tint.opacity(0.25), radius: 14, y: 8)
    }

    /// Fundo padrão das telas.
    func screenBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Componentes

struct IconBadge: View {
    let systemName: String
    var tint: Color = Theme.accent
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
            }
        }
        .padding(.top, 6)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = Theme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(systemName: icon, tint: tint, size: 32)
            Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .card(padding: 14)
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint).frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: value)
    }
}

struct RingProgress: View {
    let value: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(duration: 0.6), value: value)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct Chip: View {
    let title: String
    var isSelected: Bool = false
    var tint: Color = Theme.accent
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? tint : Theme.card, in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct ModuleTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let module: Theme.Module
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.85).lineLimit(1)
            }
        }
        .gradientCard(module)
    }
}

/// Linha de valor monetário com cor por sinal.
struct MoneyText: View {
    let value: Double
    var signed: Bool = false
    var font: Font = .body.weight(.semibold)
    var body: some View {
        Text(signed ? Fmt.signedCurrency(value) : Fmt.currency(value))
            .font(font)
            .foregroundStyle(signed ? (value >= 0 ? Color.green : Color.primary) : Color.primary)
            .monospacedDigit()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var module: Theme.Module = .assistant
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(module.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

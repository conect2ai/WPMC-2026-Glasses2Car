import SwiftUI

/// Conect2AI visual language, matching the group's App2Car app:
/// near-black navy background, slate cards, cyan accent, white type.
extension Color {
    static let c2aBackground = Color(red: 0.043, green: 0.055, blue: 0.106)   // #0B0E1B
    static let c2aCard = Color(red: 0.196, green: 0.235, blue: 0.302)          // #323C4D
    static let c2aCardDeep = Color(red: 0.106, green: 0.133, blue: 0.192)      // #1B2231
    static let c2aAccent = Color(red: 0.216, green: 0.686, blue: 0.831)        // #37AFD4
    static let c2aTextSecondary = Color(white: 0.72)
    static let c2aDanger = Color(red: 0.85, green: 0.32, blue: 0.30)
}

/// "C⊙NECT2AI" wordmark approximation: steering-wheel O, cyan accents.
struct C2ALogo: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 1) {
            Text("C")
            Image(systemName: "steeringwheel")
                .font(.system(size: size * 0.78, weight: .bold))
                .foregroundStyle(Color.c2aAccent)
                .padding(.horizontal, 1)
            Text("NECT")
            Text("2AI").foregroundStyle(Color.c2aAccent)
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .kerning(1.5)
    }
}

/// Filled cyan capsule — the App2Car "Conectar"/"Login" button.
struct C2APrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.c2aAccent.opacity(configuration.isPressed ? 0.6 : 1)))
    }
}

/// Outline capsule — the App2Car "Cadastrar" button.
struct C2AOutlineButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(tint.opacity(configuration.isPressed ? 0.5 : 1))
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Capsule().stroke(tint.opacity(0.55), lineWidth: 1.2))
    }
}

/// Slate rounded container used for every content block.
struct C2ACard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.c2aCard))
    }
}

/// App2Car-style menu row: icon badge, label, chevron.
struct C2AMenuRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.c2aAccent)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.c2aCardDeep))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.c2aTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.c2aTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Detalhes de Viagem"-style metric tile: caption above, value below, icon right.
struct C2AMetricTile: View {
    let caption: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.c2aTextSecondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.c2aAccent)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.c2aCardDeep))
    }
}

/// Dark rounded text field matching the theme.
struct C2AFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .tint(Color.c2aAccent)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }
}

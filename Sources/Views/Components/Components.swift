import SwiftUI

enum Brand {
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let gradient = LinearGradient(colors: [Color(red: 0.20, green: 0.55, blue: 1.0),
                                                  Color(red: 0.45, green: 0.30, blue: 0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Logo de l'app : enveloppe sur fond dégradé.
struct BrandMark: View {
    var size: CGFloat = 64
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Brand.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Brand.accent.opacity(0.35), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// Pastille d'un fournisseur de messagerie (sans logo de marque).
struct ProviderBadge: View {
    let provider: Provider
    var size: CGFloat = 40

    private var color: Color {
        switch provider {
        case .icloud: return Color(red: 0.25, green: 0.55, blue: 0.98)
        case .gmail: return Color(red: 0.92, green: 0.30, blue: 0.24)
        case .outlook: return Color(red: 0.05, green: 0.45, blue: 0.80)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: provider.symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Avatar rond avec l'initiale.
struct Avatar: View {
    let text: String
    var size: CGFloat = 44

    private var initial: String { String(text.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
        let sum = text.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Grande statistique (chiffre + libellé).
struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = Brand.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Barre de progression d'une tâche de fond.
struct JobProgressRow: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView().controlSize(.small)
                Text(job.label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(job.progress ?? 0) %").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: job.fraction)
                .animation(.easeOut, value: job.fraction)
            if let msg = job.message {
                Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Bouton principal avec indicateur de chargement intégré.
struct PrimaryButton: View {
    let title: String
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .disabled(busy || disabled)
    }
}

/// Message éphémère en haut de l'écran.
struct ToastOverlay: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        if let toast = app.toast {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(toast.style))
                    .foregroundStyle(color(toast.style))
                    .font(.body.weight(.semibold))
                Text(toast.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { withAnimation { app.toast = nil } }
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private func icon(_ s: Toast.Style) -> String {
        switch s {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    private func color(_ s: Toast.Style) -> Color {
        switch s {
        case .info: return Brand.accent
        case .success: return .green
        case .error: return .orange
        }
    }
}

/// État vide (aucune donnée) avec illustration et action.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Champ de formulaire avec libellé au-dessus.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Demande de mot de passe pour confirmer une action sensible.
struct PasswordPrompt: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirm: String
    let onConfirm: (String) -> Void
    @State private var password = ""

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            SecureField("Mot de passe", text: $password)
            Button("Annuler", role: .cancel) { password = "" }
            Button(confirm, role: .destructive) {
                let pw = password
                password = ""
                onConfirm(pw)
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    func passwordPrompt(_ isPresented: Binding<Bool>, title: String, message: String, confirm: String = "Confirmer",
                        onConfirm: @escaping (String) -> Void) -> some View {
        modifier(PasswordPrompt(isPresented: isPresented, title: title, message: message, confirm: confirm, onConfirm: onConfirm))
    }
}

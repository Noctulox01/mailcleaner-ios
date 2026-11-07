import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL
    @Binding var info: BillingInfo?

    @State private var key = ""
    @State private var redeeming = false
    @State private var plan = "premium"
    @State private var interval = "monthly"
    @State private var acceptCGV = false
    @State private var immediate = false
    @State private var checkingOut = false
    @State private var confirmCancel = false

    private var billing: Billing? { app.user?.billing ?? info?.billing }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(billing?.planLabel ?? "Gratuit").font(.title2.weight(.bold))
                        Spacer()
                        if let status = billing?.status {
                            Text(statusLabel(status))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                    if let end = billing?.periodEnd {
                        Text(billing?.cancelAtPeriodEnd == true ? "Prend fin le \(Format.date(end))" : "Renouvellement le \(Format.date(end))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let lic = billing?.license, lic.active == true {
                        Text(lic.lifetime == true ? "Accès à vie grâce à une clé d'activation."
                                                  : "Accès par clé jusqu'au \(Format.date(lic.until)).")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Votre offre")
            }

            Section {
                TextField("MC-XXXX-XXXX-XXXX", text: $key)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await redeem() }
                } label: {
                    HStack { Text("Activer la clé"); Spacer(); if redeeming { ProgressView() } }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).count < 8 || redeeming)
            } header: {
                Text("Clé d'activation")
            } footer: {
                Text("Vous avez reçu une clé ? Elle active Premium ou Famille pour la durée prévue.")
            }

            if billing?.isSubscribed == true {
                Section {
                    Button("Gérer mon abonnement (carte, factures)") { Task { await portal() } }
                    if billing?.cancelAtPeriodEnd != true {
                        Button("Résilier", role: .destructive) { confirmCancel = true }
                    }
                } footer: {
                    Text("La résiliation prend effet à la fin de la période déjà payée.")
                }
            } else if info?.ready == true, let plans = info?.plans {
                Section {
                    Picker("Formule", selection: $plan) {
                        ForEach(plans.keys.filter { $0 != "free" }.sorted(), id: \.self) { k in
                            Text(plans[k]?.name ?? Plan.label(k)).tag(k)
                        }
                    }
                    Picker("Fréquence", selection: $interval) {
                        Text("Mensuel").tag("monthly")
                        Text("Annuel").tag("yearly")
                    }
                    .pickerStyle(.segmented)
                    if let amount = plans[plan]?.prices?[interval]?.amount {
                        HStack {
                            Text("Prix TTC")
                            Spacer()
                            Text(price(amount) + (interval == "yearly" ? " / an" : " / mois")).font(.headline)
                        }
                    }
                    ForEach(plans[plan]?.features ?? [], id: \.self) { f in
                        Label(f, systemImage: "checkmark").font(.subheadline)
                    }
                    Toggle("J'accepte les conditions générales de vente", isOn: $acceptCGV).font(.footnote)
                    Toggle("Je demande le démarrage immédiat du service et renonce au délai de rétractation pour la période commencée", isOn: $immediate)
                        .font(.footnote)
                    Button {
                        Task { await checkout() }
                    } label: {
                        HStack { Text("S'abonner").fontWeight(.semibold); Spacer(); if checkingOut { ProgressView() } }
                    }
                    .disabled(!acceptCGV || !immediate || checkingOut)
                } header: {
                    Text("Passer à Premium")
                } footer: {
                    Text("Le paiement se fait sur la page sécurisée de Lemon Squeezy, dans Safari. Revenez ensuite dans l'app.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Abonnement")
        .navigationBarTitleDisplayMode(.inline)
        .task { info = try? await APIClient.shared.get("/api/billing") }
        .refreshable {
            info = try? await APIClient.shared.get("/api/billing")
            await app.refreshMe()
        }
        .confirmationDialog("Résilier l'abonnement ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Résilier", role: .destructive) { Task { await cancel() } }
        } message: {
            Text("Vous gardez l'accès jusqu'à la fin de la période en cours.")
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "active": return "Actif"
        case "trialing": return "Essai"
        case "past_due": return "Paiement en attente"
        case "cancelled": return "Résilié"
        default: return s
        }
    }

    private func price(_ cents: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: NSNumber(value: cents / 100)) ?? "\(cents / 100) €"
    }

    private func redeem() async {
        redeeming = true
        defer { redeeming = false }
        do {
            let r: LicenseReply = try await APIClient.shared.post("/api/license/redeem", ["code": key.trimmingCharacters(in: .whitespaces)])
            if let u = r.user { app.user = u }
            key = ""
            app.show("Clé activée : merci !", style: .success)
        } catch {
            app.show(error)
        }
    }

    private func checkout() async {
        checkingOut = true
        defer { checkingOut = false }
        do {
            let r: URLReply = try await APIClient.shared.post("/api/billing/checkout",
                                                              ["plan": plan, "interval": interval, "accept_cgv": true, "immediate_start": true])
            if let s = r.url, let url = URL(string: s) { openURL(url) }
        } catch {
            app.show(error)
        }
    }

    private func portal() async {
        do {
            let r: URLReply = try await APIClient.shared.post("/api/billing/portal")
            if let s = r.url, let url = URL(string: s) { openURL(url) }
        } catch {
            app.show(error)
        }
    }

    private func cancel() async {
        do {
            let _: BillingReply = try await APIClient.shared.post("/api/billing/cancel")
            await app.refreshMe()
            app.show("Résiliation enregistrée.", style: .success)
        } catch {
            app.show(error)
        }
    }
}

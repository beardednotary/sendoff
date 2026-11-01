import SwiftUI

/// Shown after entries have arrived, or from the note about an unpaid Plus look; never as a gate.
/// One purchase per Sendoff; contributors and recipients never pay. Copy follows docs/PRODUCT.md
/// ("Make it something they can keep").
struct PaywallView: View {
    @Environment(\.theme) private var theme
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var sendoff: Sendoff
    var entryCount: Int
    var onUpgraded: (Sendoff) -> Void

    @State private var busy: Plan?
    @State private var buyingLook = false
    @State private var buyingPack: ProductID?
    @State private var error: String?

    private var first: String { sendoff.recipientFirstName }
    private var chosenTheme: SendoffTheme { ThemeCatalog.theme(sendoff.themeID) }

    var body: some View {
        NavigationStack {
            ZStack {
                Paper()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "Make it something they can keep")
                            Text(headline)
                                .font(Typeface.display(40)).displayTracking(40)
                                .foregroundStyle(theme.inkColor)
                            Text("Pay once for this Sendoff. Nobody who adds to it or opens it ever pays.")
                                .font(Typeface.body)
                                .foregroundStyle(theme.mutedInkColor)
                        }
                        .padding(.top, 12)

                        tier(.single, bullets: [
                            "Up to \(Plan.single.entryLimit) entries",
                            "No Sendoff line on the last page",
                            "Scheduled reveal and the three included looks",
                        ])

                        tier(.plus, bullets: [
                            "Unlimited entries",
                            chosenTheme.premium ? "All Plus looks, including \(chosenTheme.name)" : "All Plus looks",
                            "Link your own music (Apple Music)",
                        ])

                        if chosenTheme.premium, !purchases.owns(sendoff.themeID), sendoff.plan < .plus,
                           let lookProduct = ProductID.theme(sendoff.themeID) {
                            lookAlone(lookProduct)
                        }

                        if sendoff.plan < .plus { packs }

                        Rule()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Free holds \(Plan.free.entryLimit) entries and adds a small Sendoff line on the last page. That's fine, too.")
                                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                            SecondaryButton(title: "Keep it free for now") { dismiss() }
                            Button("Restore purchases") { Task { await purchases.restore() } }
                                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .alert("Couldn't complete that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .task { if !purchases.loaded { await purchases.load() } }
        }
        .tint(theme.inkColor)
    }

    private var headline: String {
        switch entryCount {
        case 0: "Give \(first) something to keep."
        case 1: "One person has added to \(first)'s Sendoff."
        default: "\(entryCount) people have added to \(first)'s Sendoff."
        }
    }

    /// The look on its own: yours for every Sendoff, without Plus.
    private func lookAlone(_ product: ProductID) -> some View {
        let price = purchases.price(product)
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(chosenTheme.name) is a Plus look. It comes with Plus, or on its own\(price.map { " for \($0)" } ?? ""), yours for every Sendoff. Without either, \(first) sees \(ThemeCatalog.theme(sendoff.themeID.freeAlternative).name).")
                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                .fixedSize(horizontal: false, vertical: true)
            if buyingLook {
                ProgressView().tint(theme.inkColor).frame(maxWidth: .infinity).frame(height: 50)
            } else {
                SecondaryButton(title: "Get \(chosenTheme.name)\(price.map { ", \($0)" } ?? "")", fill: false) {
                    Task { await buyLook(product) }
                }
                .disabled(busy != nil || buyingPack != nil || price == nil)
            }
        }
    }

    private func buyLook(_ product: ProductID) async {
        buyingLook = true
        defer { buyingLook = false }
        do {
            switch try await purchases.buy(product) {
            case .completed: dismiss()
            case .pending: error = PurchaseError.pending.localizedDescription
            case .cancelled: break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// For office managers and team leads: several Sendoffs at once, as credits.
    private var packs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Doing a few of these? Buy several at once. One goes on this Sendoff, and the rest wait for your next ones.")
                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                .fixedSize(horizontal: false, vertical: true)
            packButton(.pack5, title: "5 Sendoffs")
            packButton(.pack10, title: "10 Sendoffs")
        }
    }

    @ViewBuilder
    private func packButton(_ id: ProductID, title: String) -> some View {
        let price = purchases.price(id)
        if buyingPack == id {
            ProgressView().tint(theme.inkColor).frame(maxWidth: .infinity).frame(height: 50)
        } else {
            SecondaryButton(title: price.map { "\(title), \($0)" } ?? title, fill: false) { Task { await buyPack(id) } }
                .disabled(busy != nil || buyingLook || buyingPack != nil || price == nil)
        }
    }

    private func buyPack(_ id: ProductID) async {
        buyingPack = id
        defer { buyingPack = nil }
        do {
            if let updated = try await purchases.buyPack(id, for: sendoff) {
                onUpgraded(updated)
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Tier card

    private func tier(_ plan: Plan, bullets: [String]) -> some View {
        let included = sendoff.plan >= plan
        let credit = purchases.credit(for: plan)
        let price = ProductID.credit(for: plan).flatMap { purchases.price($0) }
        let recommended = plan == .plus && (chosenTheme.premium || entryCount > Plan.single.entryLimit / 2)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.title).font(Typeface.title).foregroundStyle(theme.inkColor)
                Spacer()
                if included {
                    Eyebrow(text: "Yours")
                } else if let price {
                    Text(price).font(Typeface.name).foregroundStyle(theme.inkColor)
                } else {
                    ProgressView().tint(theme.mutedInkColor)
                }
            }
            if recommended, !included { Eyebrow(text: "Good fit for this one") }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.faintInkColor).padding(.top, 3)
                        Text(b).font(Typeface.body).foregroundStyle(theme.inkColor)
                    }
                }
            }
            if !included {
                let title = credit != nil ? "Use a credit" : (price.map { "\($0), once" } ?? plan.title)
                if busy == plan {
                    ProgressView().tint(theme.inkColor).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    PrimaryButton(title: title) { Task { await choose(plan) } }
                        .disabled(busy != nil || buyingLook || buyingPack != nil || (price == nil && credit == nil))
                }
            }
        }
        .padding(20)
        .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(recommended ? theme.inkColor.opacity(0.5) : theme.ruleColor))
    }

    private func choose(_ plan: Plan) async {
        busy = plan
        defer { busy = nil }
        do {
            if let updated = try await purchases.upgrade(sendoff, to: plan) {
                onUpgraded(updated)
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    let store = MockStore()
    return PaywallView(sendoff: MockStore.sampleCollecting, entryCount: 7) { _ in }
        .environment(\.store, store)
        .environment(PurchaseManager(store: store))
        .appTheme()
}

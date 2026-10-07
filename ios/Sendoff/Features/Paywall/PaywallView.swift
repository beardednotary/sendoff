import SwiftUI

/// Shown after entries have arrived, never before. One purchase per Sendoff; contributors and
/// recipients never pay. Copy follows docs/PRODUCT.md ("Make it something they can keep").
struct PaywallView: View {
    @Environment(\.theme) private var theme
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var sendoff: Sendoff
    var entryCount: Int
    var onUpgraded: (Sendoff) -> Void

    @State private var busy: Plan?
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
                            Stamp(text: "Make it something they can keep", tint: theme.sealColor)
                            Text(headline)
                                .font(Typeface.display(34))
                                .foregroundStyle(theme.inkColor)
                            Text("Pay once for this Sendoff. Nobody who adds to it or opens it ever pays.")
                                .font(Typeface.ui)
                                .foregroundStyle(theme.mutedInkColor)
                        }
                        .padding(.top, 12)

                        tier(.single, bullets: [
                            "Up to \(Plan.single.entryLimit) entries",
                            "No Sendoff line on the last page",
                            "Scheduled reveal and the three included papers",
                            "Save as PDF",
                        ])

                        tier(.plus, bullets: [
                            "Unlimited entries",
                            chosenTheme.premium ? "All premium papers, including \(chosenTheme.name)" : "All premium papers",
                            "Link your own music (Apple Music)",
                            "Slideshow mode for the party",
                        ])

                        if chosenTheme.premium, !purchases.owns(sendoff.themeID), sendoff.plan < .plus {
                            Text("\(chosenTheme.name) is a premium paper. It comes with Plus, or on its own\(purchases.price(ProductID.theme(sendoff.themeID) ?? .themeGoldLeaf).map { " for \($0)" } ?? "").")
                                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                        }

                        Rule()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Free holds \(Plan.free.entryLimit) entries and adds a small Sendoff line on the last page. That's fine, too.")
                                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                            QuietButton(title: "Keep it free for now") { dismiss() }
                            Button("Restore purchases") { Task { await purchases.restore() } }
                                .font(Typeface.caption).foregroundStyle(theme.sealColor)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(theme.mutedInkColor) }
                }
            }
            .alert("Couldn't complete that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .task { if !purchases.loaded { await purchases.load() } }
        }
        .sendoffTheme(theme)
    }

    private var headline: String {
        switch entryCount {
        case 0: "Give \(first) something to keep."
        case 1: "One person has added to \(first)'s Sendoff."
        default: "\(entryCount) people have added to \(first)'s Sendoff."
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
                    Stamp(text: "Yours", tint: theme.sealColor)
                } else if let price {
                    Text(price).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(theme.inkColor)
                } else {
                    ProgressView().tint(theme.mutedInkColor)
                }
            }
            if recommended, !included { Stamp(text: "Good fit for this one") }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(theme.sealColor).frame(width: 14, height: 2).padding(.top, 9)
                        Text(b).font(Typeface.ui).foregroundStyle(theme.inkColor)
                    }
                }
            }
            if !included {
                let title = credit != nil ? "Use a credit" : (price.map { "\($0), once" } ?? plan.title)
                if busy == plan {
                    ProgressView().tint(theme.sealColor).frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    SealButton(title: title) { Task { await choose(plan) } }
                        .disabled(busy != nil || (price == nil && credit == nil))
                }
            }
        }
        .padding(18)
        .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 6))
        .overlay(RoundedRectangle(cornerRadius: theme.radius + 6).stroke(recommended ? theme.sealColor : theme.ruleColor))
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
        .sendoffTheme(ThemeCatalog.theme(.letterpress))
}

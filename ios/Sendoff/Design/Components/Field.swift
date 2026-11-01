import SwiftUI

/// A labeled text field: a quiet label, then a rounded field one step up from the paper.
struct Field: View {
    @Environment(\.theme) private var theme
    var label: String
    @Binding var text: String
    var placeholder: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Typeface.caption).foregroundStyle(theme.faintInkColor)
            TextField(placeholder, text: $text, axis: axis)
                .font(axis == .vertical ? Typeface.entry : Typeface.ui)
                .foregroundStyle(theme.inkColor)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .padding(.horizontal, 16)
                .padding(.vertical, axis == .vertical ? 14 : 0)
                .frame(minHeight: 56)
                .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.ruleColor))
        }
    }
}

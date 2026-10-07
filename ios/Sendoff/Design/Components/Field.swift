import SwiftUI

/// A labeled text field on paper.
struct Field: View {
    @Environment(\.theme) private var theme
    var label: String
    @Binding var text: String
    var placeholder: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            TextField(placeholder, text: $text, axis: axis)
                .font(axis == .vertical ? Typeface.entry : Typeface.ui)
                .foregroundStyle(theme.inkColor)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .padding(12)
                .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius))
                .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.ruleColor))
        }
    }
}

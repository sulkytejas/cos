import SwiftUI

struct MetaLabel: View {
    let text: String
    var color: Color = Theme.Palette.inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.metaUpper)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct SectionHeader: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Theme.Font.metaSmall)
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
            }
            Hairline()
        }
    }
}

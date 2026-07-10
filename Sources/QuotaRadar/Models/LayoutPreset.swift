import SwiftUI

enum LayoutPreset: String, CaseIterable, Codable, Identifiable, Hashable {
    case compact
    case standard
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "紧凑"
        case .standard: "标准"
        case .spacious: "宽松"
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .compact: 12
        case .standard: 18
        case .spacious: 24
        }
    }

    var contentHorizontalPadding: CGFloat {
        switch self {
        case .compact: 16
        case .standard: 22
        case .spacious: 28
        }
    }

    var contentVerticalPadding: CGFloat {
        switch self {
        case .compact: 12
        case .standard: 18
        case .spacious: 24
        }
    }

    var panelSpacing: CGFloat {
        switch self {
        case .compact: 14
        case .standard: 18
        case .spacious: 22
        }
    }

    var panelPadding: CGFloat {
        switch self {
        case .compact: 16
        case .standard: 20
        case .spacious: 24
        }
    }

    var ringSize: CGFloat {
        switch self {
        case .compact: 178
        case .standard: 220
        case .spacious: 260
        }
    }

    var ringColumnWidth: CGFloat {
        switch self {
        case .compact: 220
        case .standard: 270
        case .spacious: 320
        }
    }

    var ringLineWidth: CGFloat {
        switch self {
        case .compact: 18
        case .standard: 22
        case .spacious: 26
        }
    }

    var ringLabelFont: Font {
        switch self {
        case .compact: .caption.weight(.bold)
        case .standard: .callout.weight(.bold)
        case .spacious: .body.weight(.bold)
        }
    }

    var ringValueFont: Font {
        switch self {
        case .compact: .headline.monospacedDigit().weight(.bold)
        case .standard: .title2.monospacedDigit().weight(.bold)
        case .spacious: .title.monospacedDigit().weight(.bold)
        }
    }

    var horizontalBlockSpacing: CGFloat {
        switch self {
        case .compact: 18
        case .standard: 26
        case .spacious: 32
        }
    }

    var cardMinWidth: CGFloat {
        switch self {
        case .compact: 190
        case .standard: 230
        case .spacious: 270
        }
    }

    var cardSpacing: CGFloat {
        switch self {
        case .compact: 12
        case .standard: 16
        case .spacious: 20
        }
    }

    var cardHeight: CGFloat {
        switch self {
        case .compact: 154
        case .standard: 188
        case .spacious: 222
        }
    }

    var cardPadding: CGFloat {
        switch self {
        case .compact: 13
        case .standard: 16
        case .spacious: 20
        }
    }

    var cardValueFontSize: CGFloat {
        switch self {
        case .compact: 28
        case .standard: 34
        case .spacious: 40
        }
    }

    var progressValueFontSize: CGFloat {
        switch self {
        case .compact: 25
        case .standard: 30
        case .spacious: 36
        }
    }

    var noteLineLimit: Int {
        switch self {
        case .compact: 2
        case .standard: 3
        case .spacious: 4
        }
    }

    var ringOnlyPanelWidth: CGFloat {
        panelPadding * 2
            + ringOnlyHeaderHeight
            + panelSpacing
            + ringSize
            + 12
            + ringOnlyLegendHeight
    }

    var cardPanelMinimumWidth: CGFloat {
        max(ringColumnWidth, cardMinWidth) + panelPadding * 2
    }

    private var ringOnlyHeaderHeight: CGFloat {
        switch self {
        case .compact: 42
        case .standard: 50
        case .spacious: 58
        }
    }

    private var ringOnlyLegendHeight: CGFloat {
        ringOnlyHeaderHeight
    }
}

enum ProviderLayoutMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical: "上下"
        case .horizontal: "左右"
        }
    }
}

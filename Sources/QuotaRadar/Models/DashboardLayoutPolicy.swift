import CoreGraphics

struct ProviderLayoutContent: Equatable {
    var provider: ProviderID
    var hasRenderedCards: Bool
}

enum DashboardScrollAxes: Equatable {
    case vertical
    case both
}

struct DashboardLayoutPolicy {
    var preset: LayoutPreset
    var providerLayoutMode: ProviderLayoutMode
    var providers: [ProviderLayoutContent]

    var minimumStackWidth: CGFloat {
        let widths = providers.map { content in
            content.hasRenderedCards ? preset.cardPanelMinimumWidth : preset.ringOnlyPanelWidth
        }

        switch providerLayoutMode {
        case .vertical:
            return widths.max() ?? 0
        case .horizontal:
            return widths.reduce(0, +)
                + CGFloat(max(0, widths.count - 1)) * preset.contentSpacing
        }
    }

    var minimumContentWidth: CGFloat {
        max(320, minimumStackWidth + preset.contentHorizontalPadding * 2)
    }

    func scrollAxes(viewportWidth: CGFloat) -> DashboardScrollAxes {
        minimumContentWidth > viewportWidth + 1 ? .both : .vertical
    }

    func panelWidth(for provider: ProviderID, viewportWidth: CGFloat) -> CGFloat? {
        guard providerLayoutMode == .horizontal,
              let content = providers.first(where: { $0.provider == provider }) else {
            return nil
        }

        let providerCount = max(1, providers.count)
        let availableWidth = viewportWidth
            - preset.contentHorizontalPadding * 2
            - CGFloat(max(0, providerCount - 1)) * preset.contentSpacing
        let widthShare = max(0, availableWidth / CGFloat(providerCount))
        let minimumWidth = content.hasRenderedCards
            ? preset.cardPanelMinimumWidth
            : preset.ringOnlyPanelWidth
        return max(widthShare, minimumWidth)
    }
}

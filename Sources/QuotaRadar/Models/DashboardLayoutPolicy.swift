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

    var isEmpty: Bool {
        providers.isEmpty
    }

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

    var minimumContentHeight: CGFloat {
        max(360, preset.ringOnlyPanelWidth + preset.contentVerticalPadding * 2)
    }

    var fitsWidth: Bool {
        !providers.isEmpty && providers.allSatisfy { !$0.hasRenderedCards }
    }

    var fitsHeight: Bool {
        guard !providers.isEmpty else { return false }
        return providers.count == 1
            || (providerLayoutMode == .horizontal && providers.allSatisfy { !$0.hasRenderedCards })
    }

    func scrollAxes(viewportWidth: CGFloat) -> DashboardScrollAxes {
        minimumContentWidth > viewportWidth + 1 ? .both : .vertical
    }

    func panelWidth(for provider: ProviderID, viewportWidth: CGFloat) -> CGFloat? {
        guard let content = providers.first(where: { $0.provider == provider }) else {
            return nil
        }

        if !content.hasRenderedCards {
            return preset.ringOnlyPanelWidth
        }

        guard providerLayoutMode == .horizontal else { return nil }

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

enum WindowFramePolicy {
    static func clampedFrame(
        currentFrame: CGRect,
        targetSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let size = CGSize(
            width: min(targetSize.width, visibleFrame.width),
            height: min(targetSize.height, visibleFrame.height)
        )
        let x = min(
            max(currentFrame.minX, visibleFrame.minX),
            visibleFrame.maxX - size.width
        )
        let proposedY = currentFrame.maxY - size.height
        let y = min(
            max(proposedY, visibleFrame.minY),
            visibleFrame.maxY - size.height
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

import SwiftUI

// MARK: - Node Content

extension WidgetNodeView {
  var itemContent: some View {
    HStack(spacing: itemSpacing) {
      imageView
      symbolView
      iconText
      labelText
    }
  }

  var sliderView: some View {
    HStack(spacing: stackSpacing) {
      iconText
      labelText

      SliderWidgetView(
        rootWidgetID: node.root,
        targetWidgetID: node.id,
        accessibilityLabel: controlAccessibilityLabel,
        minValue: minValue,
        maxValue: maxValue,
        step: stepValue,
        value: currentValue,
        tint: nodeColor,
        width: nodeWidth
      )
    }
  }

  var progressSliderView: some View {
    HStack(spacing: stackSpacing) {
      iconText
      labelText

      ProgressSliderWidgetView(
        rootWidgetID: node.root,
        targetWidgetID: node.id,
        accessibilityLabel: controlAccessibilityLabel,
        minValue: minValue,
        maxValue: maxValue,
        step: stepValue,
        value: currentValue,
        tint: nodeColor,
        width: nodeWidth
      )
    }
  }

  var progressView: some View {
    HStack(spacing: stackSpacing) {
      iconText
      labelText

      ProgressBarCanvas(
        value: currentValue,
        minValue: minValue,
        maxValue: maxValue,
        tint: nodeColor
      )
      .frame(width: progressWidth, height: progressHeight)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(progressAccessibilityLabel)
    .accessibilityValue(progressAccessibilityValue)
  }

  var sparklineView: some View {
    HStack(spacing: stackSpacing) {
      iconText
      labelText

      SparklineCanvas(
        values: node.values ?? [],
        tint: nodeColor,
        lineWidth: sparklineLineWidth
      )
      .frame(width: sparklineWidth, height: sparklineHeight)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(sparklineAccessibilityLabel)
    .accessibilityValue(sparklineAccessibilityValue)
  }

  /// Returns the spoken label for an interactive value control.
  var controlAccessibilityLabel: String {
    node.text.isEmpty ? "Slider" : node.text
  }

  /// Returns the spoken label for a progress indicator.
  var progressAccessibilityLabel: String {
    node.text.isEmpty ? "Progress" : node.text
  }

  /// Returns the normalized progress announced by assistive technologies.
  var progressAccessibilityValue: Text {
    let range = maxValue - minValue
    guard range > 0 else { return Text(currentValue, format: .number) }
    let fraction = min(1, max(0, (currentValue - minValue) / range))
    return Text(fraction, format: .percent.precision(.fractionLength(0)))
  }

  /// Returns the spoken label for a sparkline.
  var sparklineAccessibilityLabel: String {
    node.text.isEmpty ? "Trend" : node.text
  }

  /// Returns the latest sparkline value announced by assistive technologies.
  var sparklineAccessibilityValue: Text {
    guard let latestValue = node.values?.last else { return Text("No data") }
    return Text(latestValue, format: .number)
  }
}

// MARK: - Image And Text

extension WidgetNodeView {
  var hasImage: Bool {
    return node.imageSource != nil
  }

  var hasIcon: Bool {
    return !node.icon.isEmpty
  }

  var hasSymbol: Bool {
    guard let symbolName = node.symbolName else { return false }
    return !symbolName.isEmpty
  }

  var hasSymbolSecondaryColor: Bool {
    guard let secondaryColor = node.symbolSecondaryColor else { return false }
    return !secondaryColor.isEmpty
  }

  var hasLabel: Bool {
    return !node.text.isEmpty
  }

  var hasCustomSymbolFill: Bool {
    guard let fraction = node.symbolFillFraction else { return false }
    return fraction >= 0
  }

  var iconResolvedColor: Color {
    return color(node.iconColor ?? node.color)
  }

  var labelResolvedColor: Color {
    return color(node.labelColor ?? node.color)
  }

  var iconResolvedFont: Font? {
    return fontValue(size: node.iconFontSize ?? node.fontSize)
  }

  var labelResolvedFont: Font? {
    let size = node.labelFontSize ?? node.fontSize
    guard size != nil || node.labelFontFamily != nil || node.labelFontWeight != nil else {
      return nil
    }

    let resolvedSize = WidgetRenderMetrics.positive(size, fallback: 12)
    let weight = fontWeight(node.labelFontWeight)
    if let family = node.labelFontFamily, !family.isEmpty {
      return .custom(family, size: resolvedSize).weight(weight)
    }
    return .system(size: resolvedSize, weight: weight)
  }

  private func fontWeight(_ value: String?) -> Font.Weight {
    switch value {
    case "ultralight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "black": return .black
    default: return .regular
    }
  }

  var iconOffset: CGSize {
    CGSize(
      width: CGFloat(node.iconOffsetX ?? 0),
      height: CGFloat(node.iconOffsetY ?? 0)
    )
  }

  var symbolResolvedFont: Font {
    return .system(size: symbolResolvedFontSize, weight: .regular)
  }

  var symbolResolvedFontSize: CGFloat {
    return WidgetRenderMetrics.positive(node.iconFontSize ?? node.fontSize, fallback: 18)
  }

  var symbolOverlayResolvedFont: Font {
    let baseSize = symbolResolvedFontSize
    let scale = WidgetRenderMetrics.positive(node.symbolOverlayScale, fallback: 0.58)
    return .system(size: baseSize * scale, weight: .semibold)
  }

  var symbolOverlayBackdropResolvedFont: Font {
    let baseSize = symbolResolvedFontSize
    let scale = WidgetRenderMetrics.positive(
      node.symbolOverlayBackdropScale ?? node.symbolOverlayScale,
      fallback: 0.58
    )
    return .system(size: baseSize * scale, weight: .semibold)
  }

  var symbolOverlayOutlineDistance: CGFloat {
    max(
      0.35,
      (symbolOverlayBackdropResolvedFontSize - symbolOverlayResolvedFontSize) * 0.35
    )
  }

  var symbolOverlayResolvedFontSize: CGFloat {
    let baseSize = symbolResolvedFontSize
    let scale = WidgetRenderMetrics.positive(node.symbolOverlayScale, fallback: 0.58)
    return baseSize * scale
  }

  var symbolOverlayBackdropResolvedFontSize: CGFloat {
    let baseSize = symbolResolvedFontSize
    let scale = WidgetRenderMetrics.positive(
      node.symbolOverlayBackdropScale ?? node.symbolOverlayScale,
      fallback: 0.58
    )
    return baseSize * scale
  }

  var symbolOverlayOffset: CGSize {
    CGSize(
      width: CGFloat(node.symbolOverlayOffsetX ?? 0),
      height: CGFloat(node.symbolOverlayOffsetY ?? 0)
    )
  }

  var symbolCanvasSize: CGSize {
    let base = symbolResolvedFontSize
    let widthFactor = WidgetRenderMetrics.nonnegative(node.symbolCanvasWidthFactor, fallback: 1)
    let heightFactor = WidgetRenderMetrics.nonnegative(node.symbolCanvasHeightFactor, fallback: 1)
    return CGSize(width: base * widthFactor, height: base * heightFactor)
  }

  var symbolFillFractionClamped: CGFloat {
    return WidgetRenderMetrics.unitInterval(node.symbolFillFraction)
  }

  var symbolFillWidth: CGFloat {
    let widthFactor = WidgetRenderMetrics.nonnegative(node.symbolFillWidthFactor, fallback: 0)
    let maxWidth = symbolCanvasSize.width * widthFactor
    guard maxWidth > 0 else { return 0 }

    let fraction = symbolFillFractionClamped
    if fraction <= 0 {
      return 0
    }

    let rawWidth = maxWidth * fraction
    let minimumFactor = WidgetRenderMetrics.unitInterval(
      node.symbolFillMinimumVisibleWidthFactor
    )
    let minimumVisibleWidth = maxWidth * minimumFactor
    return Swift.min(maxWidth, Swift.max(rawWidth, minimumVisibleWidth))
  }

  var symbolFillHeight: CGFloat {
    let factor = WidgetRenderMetrics.nonnegative(node.symbolFillHeightFactor, fallback: 0)
    return symbolCanvasSize.height * factor
  }

  var symbolFillOffset: CGSize {
    CGSize(
      width: symbolCanvasSize.width * WidgetRenderMetrics.finite(node.symbolFillOffsetXFactor),
      height: symbolCanvasSize.height * WidgetRenderMetrics.finite(node.symbolFillOffsetYFactor)
    )
  }

  var symbolFillCornerRadius: CGFloat {
    let factor = WidgetRenderMetrics.nonnegative(node.symbolFillCornerRadiusFactor, fallback: 0)
    return symbolResolvedFontSize * factor
  }

  var imageView: some View {
    return renderedImageView()
      .offset(iconOffset)
  }

  @ViewBuilder
  var symbolView: some View {
    if hasSymbol, let symbolName = node.symbolName {
      ZStack {
        if hasCustomSymbolFill {
          customFilledSymbolView(name: symbolName)
        } else {
          baseSymbolView(name: symbolName)
        }

        if let overlayName = node.symbolOverlayName, !overlayName.isEmpty {
          overlaySymbolView(name: overlayName)
        }
      }
      .offset(iconOffset)
    }
  }

  /// Builds the base SF Symbol view.
  @ViewBuilder
  func baseSymbolView(name: String) -> some View {
    if hasSymbolSecondaryColor {
      Image(systemName: name)
        .symbolRenderingMode(.palette)
        .font(symbolResolvedFont)
        .foregroundStyle(
          iconResolvedColor,
          color(node.symbolSecondaryColor)
        )
    } else {
      Image(systemName: name)
        .symbolRenderingMode(.hierarchical)
        .font(symbolResolvedFont)
        .foregroundStyle(iconResolvedColor)
    }
  }

  /// Builds an SF Symbol with a custom filled battery interior.
  @ViewBuilder
  func customFilledSymbolView(name: String) -> some View {
    ZStack {
      Color.clear
        .frame(width: symbolCanvasSize.width, height: symbolCanvasSize.height)
        .overlay(alignment: .leading) {
          RoundedRectangle(cornerRadius: symbolFillCornerRadius)
            .fill(iconResolvedColor)
            .frame(width: symbolFillWidth, height: symbolFillHeight)
            .offset(symbolFillOffset)
        }

      if hasSymbolSecondaryColor {
        Image(systemName: name)
          .symbolRenderingMode(.palette)
          .font(symbolResolvedFont)
          .foregroundStyle(
            Color.clear,
            color(node.symbolSecondaryColor)
          )
      } else {
        Image(systemName: name)
          .symbolRenderingMode(.hierarchical)
          .font(symbolResolvedFont)
          .foregroundStyle(iconResolvedColor.opacity(0.18))
      }

      Image(systemName: name)
        .symbolRenderingMode(.monochrome)
        .font(symbolResolvedFont)
        .foregroundStyle(color(node.symbolSecondaryColor))
    }
    .frame(width: symbolCanvasSize.width, height: symbolCanvasSize.height)
  }

  /// Builds the optional overlay symbol for a custom symbol view.
  @ViewBuilder
  func overlaySymbolView(name: String) -> some View {
    let overlay = Image(systemName: name)
      .symbolRenderingMode(.monochrome)
      .font(symbolOverlayResolvedFont)
      .foregroundStyle(color(node.symbolOverlayColor))
      .offset(symbolOverlayOffset)

    if let backdropColor = node.symbolOverlayBackdropColor, !backdropColor.isEmpty {
      let outline = color(backdropColor)
      let d = symbolOverlayOutlineDistance

      overlay
        .shadow(color: outline, radius: 0, x: d, y: 0)
        .shadow(color: outline, radius: 0, x: -d, y: 0)
        .shadow(color: outline, radius: 0, x: 0, y: d)
        .shadow(color: outline, radius: 0, x: 0, y: -d)
        .shadow(color: outline, radius: 0, x: d * 0.8, y: d * 0.8)
        .shadow(color: outline, radius: 0, x: -d * 0.8, y: d * 0.8)
        .shadow(color: outline, radius: 0, x: d * 0.8, y: -d * 0.8)
        .shadow(color: outline, radius: 0, x: -d * 0.8, y: -d * 0.8)
    } else {
      overlay
    }
  }

  @ViewBuilder
  var iconText: some View {
    if hasIcon && !hasSymbol {
      OverflowSafeIconText(node.icon, trailingAllowance: iconTrailingAllowance)
        .font(iconResolvedFont)
        .foregroundStyle(iconResolvedColor)
        .fixedSize()
        .offset(iconOffset)
    }
  }

  /// Reserves room for Nerd Font and private-use glyphs whose visual bounds
  /// extend beyond the advance width reported to SwiftUI.
  private var iconTrailingAllowance: CGFloat {
    return 4
  }

  @ViewBuilder
  var labelText: some View {
    if hasLabel {
      Text(node.text)
        .font(labelResolvedFont)
        .foregroundStyle(labelResolvedColor)
    }
  }

  var imageSize: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.imageSize, fallback: 14)
  }

  var imageCornerRadius: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.imageCornerRadius, fallback: 4)
  }

  /// Builds the rendered image view for one node.
  @ViewBuilder
  func renderedImageView() -> some View {
    if let imageSource = node.imageSource {
      WidgetImageView(
        source: imageSource,
        size: imageSize,
        cornerRadius: imageCornerRadius,
        tint: (node.iconColor ?? node.color)?.isEmpty == false ? iconResolvedColor : nil
      ) { failedSource in
        logger.warn(
          "widget image could not be decoded",
          .field("widget", node.id),
          .field("source", failedSource.diagnosticLabel)
        )
      }
    }
  }

}

/// Draws glyphs into a surface wider than their typographic advance width.
///
/// Some icon fonts report an advance that is narrower than the visible glyph. A
/// regular `Text` view clips that overhang before surrounding layout padding is
/// applied. This view keeps `Text` for measurement but draws into the expanded
/// canvas itself, so the additional width protects the glyph rather than merely
/// moving the following view.
private struct OverflowSafeIconText: View {
  let value: String
  let trailingAllowance: CGFloat

  init(_ value: String, trailingAllowance: CGFloat) {
    self.value = value
    self.trailingAllowance = trailingAllowance
  }

  var body: some View {
    Text(value)
      .hidden()
      .padding(.trailing, trailingAllowance)
      .overlay(alignment: .leading) {
        Canvas { context, size in
          let text = context.resolve(Text(value))
          context.draw(
            text,
            at: CGPoint(x: 0, y: size.height / 2),
            anchor: .leading
          )
        }
      }
  }
}

import AppKit
import SwiftUI

/// Shared asynchronous renderer for cached widget images.
struct WidgetImageView: View {
  /// The source for this widget image view.
  let source: WidgetImageSource
  /// The size for this widget image view.
  let size: CGFloat
  /// The corner radius for this widget image view.
  let cornerRadius: CGFloat
  /// The tint for this widget image view.
  let tint: Color?
  /// The on load failure for this widget image view.
  let onLoadFailure: ((WidgetImageSource) -> Void)?

  @StateObject private var imageLoader = WidgetImageLoader()

  /// Returns the uses template rendering.
  static func usesTemplateRendering(source: WidgetImageSource, tint: Color?) -> Bool {
    tint != nil && source.allowsTemplateTint
  }

  /// Creates a widget image view.
  init(
    source: WidgetImageSource,
    size: CGFloat,
    cornerRadius: CGFloat = 0,
    tint: Color? = nil,
    onLoadFailure: ((WidgetImageSource) -> Void)? = nil
  ) {
    self.source = source
    self.size = size
    self.cornerRadius = cornerRadius
    self.tint = tint
    self.onLoadFailure = onLoadFailure
  }

  /// The rendered content for this view.
  var body: some View {
    let revision = WidgetImageRevision(source: source)
    Group {
      if let loadedImage = imageLoader.image(for: source) {
        if let tint, Self.usesTemplateRendering(source: source, tint: tint) {
          imageView(loadedImage.image, renderingMode: .template)
            .foregroundStyle(tint)
        } else {
          imageView(loadedImage.image, renderingMode: .original)
        }
      } else {
        Color.clear
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    .task(id: revision) {
      if await imageLoader.load(revision: revision) {
        onLoadFailure?(source)
      }
    }
  }

  /// Returns the image view.
  private func imageView(
    _ image: NSImage,
    renderingMode: Image.TemplateRenderingMode
  ) -> some View {
    Image(nsImage: image)
      .renderingMode(renderingMode)
      .resizable()
      .interpolation(.high)
      .scaledToFit()
  }
}

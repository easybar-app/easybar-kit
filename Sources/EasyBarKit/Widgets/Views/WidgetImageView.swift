import AppKit
import SwiftUI

/// Shared asynchronous renderer for cached widget images.
struct WidgetImageView: View {
  let source: WidgetImageSource
  let size: CGFloat
  let cornerRadius: CGFloat
  let tint: Color?
  let onLoadFailure: ((WidgetImageSource) -> Void)?

  @StateObject private var imageLoader = WidgetImageLoader()

  static func usesTemplateRendering(source: WidgetImageSource, tint: Color?) -> Bool {
    tint != nil && source.allowsTemplateTint
  }

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

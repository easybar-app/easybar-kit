import Foundation
import SwiftUI

/// Reusable presentation model for config-related error UIs.
public struct SharedConfigErrorPresentation: Sendable {
  /// Window title used by host shells when they present the view in a window.
  public let windowTitle: String
  /// Primary headline describing the failure.
  public let title: String
  /// Short explanation of the current fallback behavior.
  public let summary: String
  /// Section title for the config file path.
  public let fileSectionTitle: String
  /// Config file path or identifier that failed.
  public let filePath: String
  /// Optional section title for the config location.
  public let locationSectionTitle: String?
  /// Optional config key path or source location associated with the failure.
  public let locationText: String?
  /// Optional title for the problem metadata block.
  public let problemSectionTitle: String?
  /// Label shown before the problem item value.
  public let problemItemLabel: String
  /// Problem item or key associated with the failure.
  public let problemItemText: String?
  /// Label shown before the problem value.
  public let problemValueLabel: String
  /// Problem value associated with the failure.
  public let problemValueText: String?
  /// Section title for the detailed explanation.
  public let detailSectionTitle: String
  /// User-facing detailed error text.
  public let detailText: String
  /// Optional label for the file-opening action.
  public let openButtonTitle: String?
  /// Optional label for the reload or retry action.
  public let retryButtonTitle: String?
  /// Label for the close action.
  public let closeButtonTitle: String

  /// Creates one reusable config error presentation model.
  public init(
    windowTitle: String,
    title: String,
    summary: String,
    fileSectionTitle: String = "Config file",
    filePath: String,
    locationSectionTitle: String? = "Config location",
    locationText: String? = nil,
    problemSectionTitle: String? = "Problem",
    problemItemLabel: String = "item:",
    problemItemText: String? = nil,
    problemValueLabel: String = "value:",
    problemValueText: String? = nil,
    detailSectionTitle: String = "What is wrong",
    detailText: String,
    openButtonTitle: String? = nil,
    retryButtonTitle: String? = nil,
    closeButtonTitle: String = "Close"
  ) {
    self.windowTitle = windowTitle
    self.title = title
    self.summary = summary
    self.fileSectionTitle = fileSectionTitle
    self.filePath = filePath
    self.locationSectionTitle = locationSectionTitle
    self.locationText = Self.normalizedOptionalText(locationText)
    self.problemSectionTitle = problemSectionTitle
    self.problemItemLabel = problemItemLabel
    self.problemItemText = Self.normalizedOptionalText(problemItemText)
    self.problemValueLabel = problemValueLabel
    self.problemValueText = Self.normalizedOptionalText(problemValueText)
    self.detailSectionTitle = detailSectionTitle
    self.detailText = Self.normalizedText(detailText)
    self.openButtonTitle = openButtonTitle
    self.retryButtonTitle = retryButtonTitle
    self.closeButtonTitle = closeButtonTitle
  }

  /// Returns whether the problem metadata block should be shown.
  public var showsProblemBlock: Bool {
    return problemItemText != nil || problemValueText != nil
  }

  /// Collapses fallback whitespace and drops empty strings.
  private static func normalizedOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Collapses whitespace in text blocks for stable rendering.
  private static func normalizedText(_ value: String) -> String {
    return
      value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

/// Shared SwiftUI content for config load and reload errors.
public struct SharedConfigErrorView: View {
  /// Reusable presentation model.
  public let presentation: SharedConfigErrorPresentation
  /// Optional callback used by the file-opening button.
  public let onOpen: (() -> Void)?
  /// Optional callback used by the reload or retry button.
  public let onRetry: (() -> Void)?
  /// Callback used by the close button.
  public let onClose: () -> Void

  /// Creates the shared config error view.
  public init(
    presentation: SharedConfigErrorPresentation,
    onOpen: (() -> Void)? = nil,
    onRetry: (() -> Void)? = nil,
    onClose: @escaping () -> Void
  ) {
    self.presentation = presentation
    self.onOpen = onOpen
    self.onRetry = onRetry
    self.onClose = onClose
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.primary)

      Text(presentation.summary)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        Text(presentation.fileSectionTitle)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)

        Text(presentation.filePath)
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
      }

      if let locationSectionTitle = presentation.locationSectionTitle,
        let locationText = presentation.locationText
      {
        VStack(alignment: .leading, spacing: 6) {
          Text(locationSectionTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

          Text(locationText)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
        }
      }

      if let problemSectionTitle = presentation.problemSectionTitle, presentation.showsProblemBlock {
        VStack(alignment: .leading, spacing: 6) {
          Text(problemSectionTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

          VStack(alignment: .leading, spacing: 4) {
            if let problemItemText = presentation.problemItemText {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.problemItemLabel)
                  .foregroundStyle(.secondary)

                Text(problemItemText)
                  .textSelection(.enabled)
              }
            }

            if let problemValueText = presentation.problemValueText {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.problemValueLabel)
                  .foregroundStyle(.secondary)

                Text(problemValueText)
                  .textSelection(.enabled)
              }
            }
          }
          .font(.system(size: 12, design: .monospaced))
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(presentation.detailSectionTitle)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)

        ScrollView {
          Text(presentation.detailText)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
        }
        .frame(minHeight: 90, maxHeight: 180)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        )
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
      }

      HStack {
        if let openButtonTitle = presentation.openButtonTitle, let onOpen {
          Button(openButtonTitle, action: onOpen)
            .keyboardShortcut("o", modifiers: [.command])
        }

        if let retryButtonTitle = presentation.retryButtonTitle, let onRetry {
          Button(retryButtonTitle, action: onRetry)
            .keyboardShortcut("r", modifiers: [.command])
        }

        Spacer()

        Button(presentation.closeButtonTitle, action: onClose)
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(18)
    .frame(width: 560)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
  }
}

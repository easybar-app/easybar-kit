import SwiftUI

/// Renders the popover used to jump directly between years in the month popup.
struct MonthYearPickerPopover: View {
  let currentYear: Int
  @Binding var pageStartYear: Int

  let onSelectYear: (Int) -> Void
  let onClose: () -> Void
  let headerColor: Color
  let backgroundColor: Color
  let borderColor: Color
  let currentYearTextColor: Color
  let currentYearBackgroundColor: Color
  let currentYearBorderColor: Color

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

  /// Renders the full year-grid popover.
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerView
      yearGrid
    }
    .padding(14)
    .frame(width: 260)
    .background(backgroundColor)
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(borderColor, lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

// MARK: - Sections

extension MonthYearPickerPopover {
  /// Builds the top year-page navigation row.
  fileprivate var headerView: some View {
    HStack {
      Button("Previous years", systemImage: "chevron.left") {
        pageStartYear -= 12
      }
      .labelStyle(.iconOnly)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(headerColor)
      .buttonStyle(.plain)

      Spacer()

      Text("\(String(pageStartYear))-\(String(pageStartYear + 11))")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(headerColor.opacity(0.8))

      Spacer()

      Button("Next years", systemImage: "chevron.right") {
        pageStartYear += 12
      }
      .labelStyle(.iconOnly)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(headerColor)
      .buttonStyle(.plain)
    }
  }

  /// Builds the twelve-year selection grid.
  fileprivate var yearGrid: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(Array(pageYears.enumerated()), id: \.offset) { _, year in
        Button(action: { onSelectYear(year) }) {
          Text(String(year))
            .font(.system(size: 13, weight: year == currentYear ? .semibold : .medium))
            .foregroundStyle(year == currentYear ? currentYearTextColor : headerColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(year == currentYear ? currentYearBackgroundColor : Color.white.opacity(0.04))
            )
            .overlay {
              if year == currentYear {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .stroke(currentYearBorderColor, lineWidth: 1)
              }
            }
        }
        .buttonStyle(.plain)
      }
    }
  }

  /// Returns the years shown on the current page.
  fileprivate var pageYears: [Int] {
    return Array(pageStartYear..<(pageStartYear + 12))
  }
}

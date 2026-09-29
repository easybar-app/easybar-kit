import EasyBarCalendarPresentation
import SwiftUI

/// Reusable SwiftUI calendar composer view.
public struct CalendarEventComposerView: View {
  @ObservedObject public var composer: CalendarEventComposer
  /// The config for this calendar event composer view.
  public let config: CalendarComposerConfig
  /// The appointments style for this calendar event composer view.
  public let appointmentsStyle: CalendarAppointmentsStyle
  /// The on cancel for this calendar event composer view.
  public let onCancel: () -> Void
  /// The on saved for this calendar event composer view.
  public let onSaved: () -> Void
  /// The on deleted for this calendar event composer view.
  public let onDeleted: () -> Void
  @State private var showsDeleteConfirmation = false
  @State private var showsCloseConfirmation = false

  /// Creates a calendar event composer view.
  public init(
    composer: CalendarEventComposer,
    config: CalendarComposerConfig,
    appointmentsStyle: CalendarAppointmentsStyle,
    onCancel: @escaping () -> Void,
    onSaved: @escaping () -> Void,
    onDeleted: @escaping () -> Void
  ) {
    self.composer = composer
    self.config = config
    self.appointmentsStyle = appointmentsStyle
    self.onCancel = onCancel
    self.onSaved = onSaved
    self.onDeleted = onDeleted
  }

  /// The rendered content for this view.
  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      content
      footer
    }
    .padding(.horizontal, CGFloat(config.paddingX))
    .padding(.vertical, CGFloat(config.paddingY))
    .frame(width: 360)
    .background(
      RoundedRectangle(cornerRadius: CGFloat(config.cornerRadius))
        .fill(color(config.backgroundColorHex))
    )
    .overlay {
      RoundedRectangle(cornerRadius: CGFloat(config.cornerRadius))
        .stroke(color(config.borderColorHex), lineWidth: CGFloat(config.borderWidth))
    }
    .alert(config.deleteConfirmationTitle, isPresented: $showsDeleteConfirmation) {
      Button(config.cancelLabel, role: .cancel) {}
      Button(config.removeLabel, role: .destructive) {
        composer.delete(onSuccess: onDeleted)
      }
    } message: {
      Text(config.deleteConfirmationMessage)
    }
    .alert("Save changes before closing?", isPresented: $showsCloseConfirmation) {
      Button(config.cancelLabel, role: .cancel) {}
      Button("Discard", role: .destructive, action: onCancel)
      Button(primaryButtonTitle, action: saveAndClose)
        .disabled(!composer.canSave)
    } message: {
      Text("If you don’t save, your changes will be lost.")
    }
  }

  /// The header for this calendar event composer view.
  private var header: some View {
    HStack {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(color(config.headerTextColorHex))

      Spacer()

      Button(config.openCalendarLabel) {
        composer.openCalendarApp()
      }
      .buttonStyle(.plain)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(color(config.secondaryTextColorHex))
    }
  }

  /// The content for this calendar event composer view.
  private var content: some View {
    VStack(alignment: .leading, spacing: 10) {
      labeledTextField(
        label: config.titleLabel,
        placeholder: config.titlePlaceholder,
        text: $composer.title
      )

      labeledTextField(
        label: config.locationLabel,
        placeholder: config.locationPlaceholder,
        text: $composer.location
      )

      VStack(alignment: .leading, spacing: 4) {
        label(config.calendarLabel)
        Picker(config.calendarLabel, selection: $composer.selectedCalendarID) {
          ForEach(composer.calendarOptions) { option in
            Text(option.title).tag(option.id)
          }
        }
        .labelsHidden()
      }

      Toggle(config.allDayLabel, isOn: $composer.isAllDay)

      dateFields

      travelTimeField
      alertsField

      if let message = composer.errorMessage {
        Text(message)
          .font(.system(size: 11))
          .foregroundStyle(.red)
      }
    }
  }

  /// The date fields for this calendar event composer view.
  private var dateFields: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        label(config.startLabel)
        DatePicker(
          config.startLabel,
          selection: $composer.startDate,
          displayedComponents: displayedComponents
        )
        .labelsHidden()
      }

      VStack(alignment: .leading, spacing: 4) {
        label(config.endLabel)
        DatePicker(
          config.endLabel,
          selection: $composer.endDate,
          displayedComponents: displayedComponents
        )
        .labelsHidden()
      }
    }
  }

  /// The travel time field for this calendar event composer view.
  private var travelTimeField: some View {
    VStack(alignment: .leading, spacing: 4) {
      label(config.travelTimeLabel)

      Picker(config.travelTimeLabel, selection: $composer.selectedTravelTime) {
        ForEach(composer.travelTimeOptions) { option in
          Text(composer.travelTimeLabel(for: option)).tag(option)
        }
      }
      .labelsHidden()

      if composer.selectedTravelTime == .custom {
        TextField("Minutes", text: $composer.customTravelMinutesText)
          .textFieldStyle(.roundedBorder)
      }
    }
  }

  /// The alerts field for this calendar event composer view.
  private var alertsField: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        label(config.alertLabel)

        Spacer()

        Button(config.addAlertLabel) {
          composer.addAlertRow()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
      }

      ForEach($composer.alertRows) { $row in
        HStack {
          Picker(config.alertLabel, selection: $row.option) {
            ForEach(composer.alertOptions) { option in
              Text(composer.alertLabel(for: option)).tag(option)
            }
          }
          .labelsHidden()

          if row.option == .custom {
            TextField("Minutes", text: $row.customMinutesText)
              .textFieldStyle(.roundedBorder)
              .frame(width: 80)
          }

          Button(config.removeLabel, systemImage: "minus.circle") {
            composer.removeAlertRow(id: row.id)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.plain)
        }
      }
    }
  }

  /// The footer for this calendar event composer view.
  private var footer: some View {
    HStack {
      if composer.canDelete {
        Button(config.removeLabel, role: .destructive) {
          showsDeleteConfirmation = true
        }
        .disabled(composer.isSaving)
      }

      Spacer()

      Button(config.cancelLabel, action: requestClose)
        .keyboardShortcut(.cancelAction)
        .disabled(composer.isSaving)

      Button(primaryButtonTitle, action: saveAndClose)
        .keyboardShortcut(.defaultAction)
        .disabled(composer.isSaving)
    }
  }

  /// The title for this calendar event composer view.
  private var title: String {
    switch composer.mode {
    case .create:
      return config.createTitle
    case .edit:
      return config.editTitle
    }
  }

  /// The primary button title for this calendar event composer view.
  private var primaryButtonTitle: String {
    switch composer.mode {
    case .create:
      return config.saveLabel
    case .edit:
      return config.updateLabel
    }
  }

  /// The displayed components for this calendar event composer view.
  private var displayedComponents: DatePickerComponents {
    composer.isAllDay ? [.date] : [.date, .hourAndMinute]
  }

  /// Requests close.
  private func requestClose() {
    guard composer.hasUnsavedChanges else {
      onCancel()
      return
    }

    showsCloseConfirmation = true
  }

  /// Saves and close.
  private func saveAndClose() {
    composer.save(onSuccess: onSaved)
  }

  /// Returns the labeled text field.
  private func labeledTextField(
    label labelText: String,
    placeholder: String,
    text: Binding<String>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      label(labelText)
      TextField(labelText, text: text, prompt: Text(placeholder))
        .textFieldStyle(.roundedBorder)
    }
  }

  /// Returns the label.
  private func label(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(color(appointmentsStyle.secondaryTextColorHex))
  }

  /// Returns the color.
  private func color(_ hex: String) -> Color {
    Color(calendarHex: hex)
  }
}

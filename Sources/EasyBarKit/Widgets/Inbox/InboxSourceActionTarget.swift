/// One source action selected for native inbox fan-out.
struct InboxSourceActionTarget: Equatable, Sendable {
  /// The source for this inbox source action target.
  let source: String
  /// The action for this inbox source action target.
  let action: InboxAction
}

/// One source action selected for native inbox fan-out.
struct InboxSourceActionTarget: Equatable, Sendable {
  let source: String
  let action: InboxAction
}

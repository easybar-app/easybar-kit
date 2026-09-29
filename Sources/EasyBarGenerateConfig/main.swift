import EasyBarConfigSchema
import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

/// Defines the supported generator error values.
private enum GeneratorError: Error, CustomStringConvertible {
  case missingOutputPath(String)
  case unknownCommand(String)
  case writeFailed(String)

  var description: String {
    switch self {
    case .missingOutputPath(let command):
      "\(command) requires an output path"
    case .unknownCommand(let command):
      "unknown command: \(command)"
    case .writeFailed(let path):
      "failed to write \(path)"
    }
  }
}

/// Returns the output URL.
private func outputURL(for path: String) -> URL {
  if path.hasPrefix("/") {
    return URL(fileURLWithPath: path)
  }
  return root.appendingPathComponent(path)
}

/// Writes the requested value.
private func write(_ text: String, to path: String) throws {
  let url = outputURL(for: path)
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try text.write(to: url, atomically: true, encoding: .utf8)
  print("Generated \(url.path)")
}

/// Renders defaults.
private func renderDefaults() -> String {
  let lines = ConfigSchemaRegistry.lines.map { line in
    switch line {
    case .blank:
      return ""
    case .comment(let text):
      return text
    case .section(let name, let commented, let prefix, _):
      return "\(commented ? prefix : "")[\(name)]"
    case .entry(let key, let value, let description, let commented, let prefix, _):
      let suffix = description.isEmpty ? "" : " # \(description)"
      return "\(commented ? prefix : "")\(key) = \(value)\(suffix)"
    case .optionalEntry(let key, let value, let description):
      let suffix = description.isEmpty ? "" : " # \(description)"
      return "# \(key) = \(value)\(suffix)"
    }
  }

  return lines.joined(separator: "\n")
    .trimmingCharacters(in: .newlines)
    + "\n"
}

/// Generates the default configuration.
private func generateDefaults() throws {
  try write(renderDefaults(), to: "config.defaults.toml")
}

/// Generates the configuration schema.
private func generateSchema(outputPath: String = "config.schema.json") throws {
  try write(ConfigReferenceRenderer.renderCatalog(), to: outputPath)
}

/// Generates the configuration documentation.
private func generateDocs(outputPath: String) throws {
  try write(ConfigReferenceRenderer.render(), to: outputPath)
}

/// Runs the program entry point.
private func main() throws {
  let arguments = Array(CommandLine.arguments.dropFirst())
  let command = arguments.first ?? "all"

  switch command {
  case "all":
    try generateDefaults()
    try generateSchema()
  case "defaults":
    try generateDefaults()
  case "config-schema":
    try generateSchema(outputPath: arguments.dropFirst().first ?? "config.schema.json")
  case "config-docs":
    guard arguments.count == 2 else {
      throw GeneratorError.missingOutputPath(command)
    }
    try generateDocs(outputPath: arguments[1])
  default:
    throw GeneratorError.unknownCommand(command)
  }
}

do {
  try main()
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}

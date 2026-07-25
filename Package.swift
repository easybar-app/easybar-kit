// swift-tools-version: 5.10

import PackageDescription

let strictConcurrencySettings: [SwiftSetting] = [
  .enableUpcomingFeature("StrictConcurrency")
]

let package = Package(
  name: "EasyBar",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "EasyBarShared", targets: ["EasyBarShared"]),
    .library(name: "EasyBarConfigParsing", targets: ["EasyBarConfigParsing"]),
    .library(name: "EasyBarConfigSchema", targets: ["EasyBarConfigSchema"]),
    .library(name: "EasyBarCalendarConfig", targets: ["EasyBarCalendarConfig"]),
    .library(name: "EasyBarCalendarCore", targets: ["EasyBarCalendarCore"]),
    .library(name: "EasyBarCalendarPresentation", targets: ["EasyBarCalendarPresentation"]),
    .library(name: "EasyBarCalendarUI", targets: ["EasyBarCalendarUI"]),
    .library(name: "EasyBarNetworkAgentCore", targets: ["EasyBarNetworkAgentCore"]),
    .executable(name: "EasyBar", targets: ["EasyBarApp"]),
    .executable(name: "EasyBarLuaRuntime", targets: ["EasyBarLuaRuntime"]),
    .executable(name: "EasyBarCtl", targets: ["EasyBarCtl"]),
    .executable(name: "EasyBarCalendarAgent", targets: ["EasyBarCalendarAgent"]),
    .executable(name: "EasyBarNetworkAgent", targets: ["EasyBarNetworkAgent"]),
    .executable(name: "EasyBarGenerateConfig", targets: ["EasyBarGenerateConfig"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/gi8lino/SwiftTOMLEdit.git",
      exact: "0.0.2"
    )
  ],
  targets: [
    .target(
      name: "CEasyBarEventKitCompat",
      path: "Sources/CEasyBarEventKitCompat",
      publicHeadersPath: "include"
    ),
    .executableTarget(
      name: "EasyBarGenerateBuildInfo",
      path: "Sources/EasyBarGenerateBuildInfo",
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "EasyBarGenerateConfig",
      dependencies: [
        "EasyBarConfigSchema"
      ],
      path: "Sources/EasyBarGenerateConfig",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarConfigSchema",
      path: "Sources/EasyBarConfigSchema",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarShared",
      dependencies: [
        "EasyBarConfigParsing"
      ],
      path: "Sources/EasyBarShared",
      swiftSettings: strictConcurrencySettings,
      plugins: [
        .plugin(name: "EasyBarBuildInfoPlugin")
      ]
    ),
    .target(
      name: "EasyBarConfigParsing",
      dependencies: [
        .product(name: "SwiftTOMLEdit", package: "swifttomledit")
      ],
      path: "Sources/EasyBarConfigParsingCompat",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarCalendarCore",
      dependencies: [
        "EasyBarShared",
        "CEasyBarEventKitCompat",
      ],
      path: "Sources/EasyBarCalendarCore",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarCalendarPresentation",
      dependencies: [
        "EasyBarShared"
      ],
      path: "Sources/EasyBarCalendarPresentation",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarCalendarUI",
      dependencies: [
        "EasyBarShared",
        "EasyBarCalendarPresentation",
      ],
      path: "Sources/EasyBarCalendarUI",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarCalendarConfig",
      dependencies: [
        "EasyBarShared",
        "EasyBarConfigParsing",
      ],
      path: "Sources/EasyBarCalendarConfig",
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "EasyBarNetworkAgentCore",
      dependencies: [
        "EasyBarShared"
      ],
      path: "Sources/EasyBarNetworkAgentCore",
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "EasyBarApp",
      dependencies: [
        "EasyBarShared",
        "EasyBarConfigParsing",
        "EasyBarConfigSchema",
        "EasyBarCalendarConfig",
        "EasyBarCalendarPresentation",
        "EasyBarCalendarUI",
      ],
      path: "Sources/EasyBarApp",
      exclude: [
        "Info.plist",
        "Lua/easybar_api.base.lua",
        "Lua/easybar_api.events.lua",
        "Lua/easybar_api.themes.lua",
      ],
      resources: [
        .copy("Assets/easybar-menubar.svg"),
        .copy("Events/event_catalog.json"),
        .copy("Theme/theme_tokens.json"),
        .copy("Lua/runtime.lua"),
        .copy("Lua/easybar_api.lua"),
        .copy("Lua/easybar"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "EasyBarLuaRuntime",
      dependencies: [
        "EasyBarShared"
      ],
      path: "Sources/EasyBarLuaRuntime",
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "EasyBarCtl",
      dependencies: [
        "EasyBarShared"
      ],
      path: "Sources/EasyBarCtl",
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "EasyBarCalendarAgent",
      dependencies: [
        "EasyBarShared",
        "EasyBarCalendarCore",
      ],
      path: "Sources/EasyBarCalendarAgent",
      exclude: [
        "Info.plist"
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "EasyBarNetworkAgent",
      dependencies: [
        "EasyBarShared",
        "EasyBarNetworkAgentCore",
      ],
      path: "Sources/EasyBarNetworkAgent",
      exclude: [
        "Info.plist"
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "EasyBarTests",
      dependencies: [
        "EasyBarApp",
        "EasyBarCtl",
        "EasyBarLuaRuntime",
        "EasyBarShared",
        "EasyBarConfigParsing",
        "EasyBarConfigSchema",
        "EasyBarCalendarConfig",
        "EasyBarCalendarCore",
        "EasyBarCalendarPresentation",
        "EasyBarCalendarUI",
        "EasyBarNetworkAgentCore",
      ],
      path: "Tests/EasyBarTests",
      swiftSettings: strictConcurrencySettings
    ),
    .plugin(
      name: "EasyBarBuildInfoPlugin",
      capability: .buildTool(),
      dependencies: [
        "EasyBarGenerateBuildInfo"
      ]
    ),
  ]
)

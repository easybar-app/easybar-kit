#!/usr/bin/env bash
# Check Swift targets with strict concurrency enabled.
set -euo pipefail

readonly targets=(
  EasyBarConfigSchema
  EasyBarCalendarConfig
  EasyBarCalendarCore
  EasyBarCalendarPresentation
  EasyBarCalendarUI
  EasyBarNetworkAgentCore
  EasyBarShared
  EasyBarKit
  EasyBarLuaRuntime
  EasyBarCtl
  EasyBarCalendarAgent
  EasyBarNetworkAgent
  EasyBarGenerateBuildInfo
  EasyBarGenerateConfig
)

for target in "${targets[@]}"; do
  echo "Checking strict concurrency: ${target}"
  swift build --target "${target}" \
    -Xswiftc -strict-concurrency=complete \
    -Xswiftc -warnings-as-errors
done

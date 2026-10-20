#!/usr/bin/env bash
# Builds and tests Khala's Foundation-only model (Sources/App/Frontend/Khala/Model) on any machine with a Swift
# toolchain, Linux included, with no Xcode: the model files and the Khala tests are staged into a throwaway
# SwiftPM package (`@testable import HomeAssistant` becomes `@testable import KhalaModel`) and run with
# swift-testing. The SwiftUI half (Khala/UI) needs Xcode and is not covered.
#
#   Tools/Khala/linux-check.sh                 # swift test
#   Tools/Khala/linux-check.sh states.json     # also print Today + devices for a saved GET /api/states answer
#
# SWIFT_BIN may point at a toolchain's bin directory (default: whatever `swift` is on PATH).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODEL="$ROOT/Sources/App/Frontend/Khala/Model"
TESTS="$ROOT/Tests/App/Container/Khala"
if [[ -n "${SWIFT_BIN:-}" ]]; then export PATH="$SWIFT_BIN:$PATH"; fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/KhalaModel" "$WORK/Sources/KhalaDump" "$WORK/Tests/KhalaModelTests"
cp "$MODEL"/*.swift "$WORK/Sources/KhalaModel/"
for file in "$TESTS"/*.swift; do
  sed 's/^@testable import HomeAssistant$/@testable import KhalaModel/' "$file" > "$WORK/Tests/KhalaModelTests/$(basename "$file")"
done
cp "$(dirname "$0")/KhalaDump.swift" "$WORK/Sources/KhalaDump/main.swift"

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KhalaModel",
    targets: [
        .target(name: "KhalaModel", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "KhalaDump", dependencies: ["KhalaModel"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KhalaModelTests", dependencies: ["KhalaModel"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
SWIFT

cd "$WORK"
swift test 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || exit 1
if [[ $# -ge 1 ]]; then
  swift run -c debug KhalaDump "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]|^Building|^Build complete|^Compiling|^Linking'
fi

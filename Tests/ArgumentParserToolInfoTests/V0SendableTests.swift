//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Argument Parser open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import ArgumentParserToolInfo
import XCTest

final class V0SendableTests: XCTestCase {
  /// Smoke test: a V0 value crosses an actor isolation boundary. Compilation
  /// is the actual assertion — if any V0 type loses its `Sendable`
  /// conformance the test target fails to build.
  func testV0ValuesCrossIsolationBoundary() async throws {
    let argument = ArgumentInfoV0(
      kind: .option,
      shouldDisplay: true,
      sectionTitle: nil,
      isOptional: false,
      isRepeating: false,
      parsingStrategy: .default,
      names: [.init(kind: .long, name: "input")],
      preferredName: .init(kind: .long, name: "input"),
      valueName: "input",
      defaultValue: nil,
      allValueStrings: nil,
      allValueDescriptions: nil,
      completionKind: .file(extensions: ["txt"]),
      abstract: "An input file.",
      discussion: nil)
    let command = CommandInfoV0(
      superCommands: [],
      shouldDisplay: true,
      commandName: "demo",
      aliases: nil,
      abstract: "",
      discussion: "",
      defaultSubcommand: nil,
      subcommands: [],
      arguments: [argument])
    let info = ToolInfoV0(command: command)

    let echoed = await Task.detached { info }.value
    XCTAssertEqual(echoed, info)

    let header = ToolInfoHeader(serializationVersion: 0)
    let echoedHeader = await Task.detached { header }.value
    XCTAssertEqual(echoedHeader.serializationVersion, 0)
  }
}

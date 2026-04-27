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

import ArgumentParser
import ArgumentParserToolInfo
import Foundation
import XCTest

/// External-consumer simulation: this target imports `ArgumentParser`
/// without `@testable`, so anything reached here is part of the public
/// surface. If the V1 accessor compiles and runs from this file, downstream
/// packages will see the same surface.
final class ToolInfoV1AccessorTests: XCTestCase {
  func testToolInfoV1AccessorReturnsExpectedCommand() throws {
    let info = SampleCommand.toolInfoV1
    XCTAssertEqual(info.serializationVersion, 1)
    XCTAssertEqual(info.command.commandName, "sample")
    XCTAssertEqual(info.command.abstract, "Sample command for V1 tests.")
  }

  func testToolInfoV1AccessorPreservesArgumentDeclarationOrder() throws {
    let info = SampleCommand.toolInfoV1
    let children = info.command.children ?? []
    XCTAssertGreaterThanOrEqual(children.count, 2)
    if case .argument(let arg) = children.first {
      XCTAssertEqual(arg.preferredName?.name, "name")
    } else {
      XCTFail("expected first child to be the --name option")
    }
  }

  func testToolInfoV1AccessorRoundTripsThroughJSON() throws {
    let info = SampleCommand.toolInfoV1
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(ToolInfoV1.self, from: data)
    XCTAssertEqual(decoded, info)
  }
}

private struct SampleCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sample",
    abstract: "Sample command for V1 tests.")

  @Option var name: String = ""
  @Argument var input: String = ""
}

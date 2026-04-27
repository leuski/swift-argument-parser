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
import Foundation
import XCTest

final class ToolInfoV1CodableTests: XCTestCase {
  // MARK: - Round-trip

  func testToolInfoV1RoundTripsThroughJSON() throws {
    let argument = ArgumentInfoV1(
      kind: .option,
      shouldDisplay: true,
      sectionTitle: "Inputs",
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
    let group = ArgumentGroupInfoV1(
      title: "Inputs", children: [.argument(argument)])
    let command = CommandInfoV1(
      superCommands: nil,
      shouldDisplay: true,
      commandName: "demo",
      aliases: nil,
      abstract: "Demo command.",
      discussion: nil,
      defaultSubcommand: nil,
      subcommands: nil,
      children: [.group(group)])
    let tool = ToolInfoV1(command: command)

    let data = try JSONEncoder().encode(tool)
    let decoded = try JSONDecoder().decode(ToolInfoV1.self, from: data)
    XCTAssertEqual(decoded, tool)
    XCTAssertEqual(decoded.serializationVersion, 1)
  }

  // MARK: - Discriminated wire format

  func testCommandChildV1ArgumentRoundTripsWithWrapperKey() throws {
    let argument = ArgumentInfoV1(
      kind: .positional,
      shouldDisplay: true,
      sectionTitle: nil,
      isOptional: false,
      isRepeating: false,
      parsingStrategy: .default,
      names: nil,
      preferredName: nil,
      valueName: "value",
      defaultValue: nil,
      allValueStrings: nil,
      allValueDescriptions: nil,
      completionKind: nil,
      abstract: nil,
      discussion: nil)
    let child: CommandChildV1 = .argument(argument)

    let data = try JSONEncoder().encode(child)
    let object = try JSONSerialization.jsonObject(with: data)
      as? [String: Any]
    let payload = object?["argument"] as? [String: Any]
    XCTAssertNotNil(payload, "expected `argument` wrapper key")
    XCTAssertEqual(payload?["valueName"] as? String, "value")
    XCTAssertNil(object?["group"])

    let decoded = try JSONDecoder().decode(CommandChildV1.self, from: data)
    XCTAssertEqual(decoded, child)
  }

  func testCommandChildV1GroupRoundTripsWithWrapperKey() throws {
    let group = ArgumentGroupInfoV1(title: "Section", children: nil)
    let child: CommandChildV1 = .group(group)

    let data = try JSONEncoder().encode(child)
    let object = try JSONSerialization.jsonObject(with: data)
      as? [String: Any]
    let payload = object?["group"] as? [String: Any]
    XCTAssertNotNil(payload, "expected `group` wrapper key")
    XCTAssertEqual(payload?["title"] as? String, "Section")
    XCTAssertNil(object?["argument"])

    let decoded = try JSONDecoder().decode(CommandChildV1.self, from: data)
    XCTAssertEqual(decoded, child)
  }

  // MARK: - Header version sniff

  func testToolInfoHeaderRecognizesV1Payload() throws {
    let tool = ToolInfoV1(
      command: CommandInfoV1(
        superCommands: nil,
        shouldDisplay: true,
        commandName: "demo",
        aliases: nil,
        abstract: nil,
        discussion: nil,
        defaultSubcommand: nil,
        subcommands: nil,
        children: nil))
    let data = try JSONEncoder().encode(tool)

    let header = try JSONDecoder().decode(ToolInfoHeader.self, from: data)
    XCTAssertEqual(header.serializationVersion, 1)
  }

  func testToolInfoHeaderRecognizesV0Payload() throws {
    let tool = ToolInfoV0(
      command: CommandInfoV0(
        superCommands: [],
        shouldDisplay: true,
        commandName: "demo",
        aliases: nil,
        abstract: "",
        discussion: "",
        defaultSubcommand: nil,
        subcommands: [],
        arguments: []))
    let data = try JSONEncoder().encode(tool)
    let header = try JSONDecoder().decode(ToolInfoHeader.self, from: data)
    XCTAssertEqual(header.serializationVersion, 0)
  }
}

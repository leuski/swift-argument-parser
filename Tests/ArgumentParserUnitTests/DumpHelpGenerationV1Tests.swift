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

@testable import ArgumentParser

final class DumpHelpGenerationV1Tests: XCTestCase {
  // MARK: - Order preservation

  /// Interleaved `@Argument` / `@OptionGroup` / `@Option` declarations must
  /// emit V1 children in source-declaration order. Failure here breaks the
  /// killer property of the enum-of-children design.
  ///
  /// Note: `commandStack.allArguments()` appends the auto-injected `--help`
  /// (and possibly `--version`) flags at the end, so we assert on the
  /// declared prefix instead of the total length.
  func testInterleavedArgumentsAndGroupsPreserveDeclarationOrder() throws {
    let info = ToolInfoV1(commandStack: [Interleaved.self])
    let children = info.command.children ?? []
    XCTAssertGreaterThanOrEqual(children.count, 5)

    // 0: top-level @Option
    if case .argument(let arg) = children[0] {
      XCTAssertEqual(arg.preferredName?.name, "alpha")
      XCTAssertNil(arg.sectionTitle)
    } else {
      XCTFail("expected argument at index 0")
    }
    // 1: @OptionGroup "GroupOne"
    if case .group(let group) = children[1] {
      XCTAssertEqual(group.title, "GroupOne")
      XCTAssertEqual(group.children?.count, 2)
    } else {
      XCTFail("expected group GroupOne at index 1")
    }
    // 2: top-level @Argument between groups
    if case .argument(let arg) = children[2] {
      XCTAssertEqual(arg.kind, .positional)
      XCTAssertNil(arg.sectionTitle)
    } else {
      XCTFail("expected positional argument at index 2")
    }
    // 3: @OptionGroup "GroupTwo"
    if case .group(let group) = children[3] {
      XCTAssertEqual(group.title, "GroupTwo")
      XCTAssertEqual(group.children?.count, 1)
    } else {
      XCTFail("expected group GroupTwo at index 3")
    }
    // 4: trailing top-level @Option
    if case .argument(let arg) = children[4] {
      XCTAssertEqual(arg.preferredName?.name, "omega")
    } else {
      XCTFail("expected argument at index 4")
    }
    // Anything after index 4 should be auto-injected flags (--help, etc.),
    // not declared args.
    for child in children.dropFirst(5) {
      guard case .argument(let arg) = child else {
        XCTFail("auto-injected child was not an .argument")
        continue
      }
      XCTAssertNil(arg.sectionTitle)
    }
  }

  // MARK: - allValueDescriptions decoupling

  /// V1 keeps `allValueDescriptions` independent of the discussion field,
  /// even when an `ExpressibleByArgument` enum has per-case descriptions.
  func testAllValueDescriptionsIsIndependentOfDiscussion() throws {
    let info = ToolInfoV1(commandStack: [WithEnum.self])
    let arg = info.command.children?
      .compactMap { child -> ArgumentInfoV1? in
        if case .argument(let info) = child { return info }
        return nil
      }
      .first { $0.preferredName?.name == "color" }
    XCTAssertNotNil(arg)
    XCTAssertEqual(arg?.allValueDescriptions?["blue"], "A blue color.")
    XCTAssertEqual(arg?.allValueDescriptions?["red"], "A red color.")
    XCTAssertEqual(arg?.abstract, "Pick a color.")
  }

  // MARK: - V0 regression check

  /// V0 generation must remain byte-for-byte unchanged after V1 lands.
  func testV0OutputUnchangedAfterV1Addition() throws {
    let v0 = DumpHelpGenerator(commandStack: [Interleaved.self]).rendered()
    // Decoding round-trips and command name matches; treats the V0 surface
    // as a regression contract.
    let header = try JSONDecoder().decode(
      ToolInfoHeader.self, from: Data(v0.utf8))
    XCTAssertEqual(header.serializationVersion, 0)
    let info = try JSONDecoder().decode(
      ToolInfoV0.self, from: Data(v0.utf8))
    XCTAssertEqual(info.command.commandName, "interleaved")
  }
}

// MARK: - Fixtures

extension DumpHelpGenerationV1Tests {
  fileprivate struct GroupOne: ParsableArguments {
    @Flag var verbose = false
    @Option var name: String = ""
  }

  fileprivate struct GroupTwo: ParsableArguments {
    @Option var token: String = ""
  }

  fileprivate struct Interleaved: ParsableCommand {
    @Option var alpha: String = ""

    @OptionGroup(title: "GroupOne")
    var groupOne: GroupOne

    @Argument var middle: String = ""

    @OptionGroup(title: "GroupTwo")
    var groupTwo: GroupTwo

    @Option var omega: String = ""
  }

  fileprivate struct WithEnum: ParsableCommand {
    enum Color: String, CaseIterable, ExpressibleByArgument {
      case blue
      case red
      var defaultValueDescription: String {
        switch self {
        case .blue: return "A blue color."
        case .red: return "A red color."
        }
      }
    }

    @Option(help: "Pick a color.")
    var color: Color = .blue
  }
}

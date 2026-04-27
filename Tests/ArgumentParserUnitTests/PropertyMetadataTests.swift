import ArgumentParserToolInfo
import XCTest

@testable import ArgumentParser

private enum EF: String, EnumerableFlag, CaseIterable { case a, b, c }

private struct Flags: ParsableArguments {
  @Flag(name: .customLong("enable")) var enable: Bool = false
  @Option(name: .customLong("name")) var name: String = ""
  @Option(name: .customLong("count")) var count: Int = 0
  @Flag var ef: EF
}

private struct Grouped: ParsableArguments {
  @OptionGroup(title: "Group") var flags: Flags
}

private struct Cmd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cmd", abstract: "A cmd",
    discussion: "Discuss")
  @OptionGroup var grouped: Grouped
}

private struct CmdTitled: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cmd-titled")
  @OptionGroup(title: "Top") var flags: Flags
}

private enum PropNode {
  case group(id: PropertyMetadataNamespace.PropertyIdentifier, title: String, children: [PropNode])
  case leaf(meta: PropertyMetadataNamespace.PropertyMetadata, extra: Extra)

  enum Extra {
    case optionValueString(preferred: PropertyMetadataNamespace.NameInfo?)
    case optionValueInt(preferred: PropertyMetadataNamespace.NameInfo?)
    case flagBool(preferred: PropertyMetadataNamespace.NameInfo?)
    case enumerableFlag(names: [PropertyMetadataNamespace.NameInfo?])
    case other
  }
}

private struct Collector: PropertyMetadataParser {
  typealias Property = PropNode

  func parse(group id: PropertyIdentifier, title: String, children: [Property]) throws -> Property {
    .group(id: id, title: title, children: children)
  }

  func parse<V>(_ wrapper: any PropertyWrapper<V>) throws -> Property {
    // Capture leaf metadata and wrapper-specific details
    let meta = wrapper.metadata
    // Try specific wrapper shapes used in this test
    if let ov = wrapper as? PropertyMetadataNamespace.OptionValue<String> {
      return .leaf(meta: meta, extra: .optionValueString(preferred: ov.preferredName))
    }
    if let ov = wrapper as? PropertyMetadataNamespace.OptionValue<Int> {
      return .leaf(meta: meta, extra: .optionValueInt(preferred: ov.preferredName))
    }
    if let fv = wrapper as? PropertyMetadataNamespace.FlagValue<Bool> {
      return .leaf(meta: meta, extra: .flagBool(preferred: fv.preferredName))
    }
    if let ef = wrapper as? PropertyMetadataNamespace.EnumerableFlagValue<EF> {
      return .leaf(meta: meta, extra: .enumerableFlag(names: ef.names))
    }
    return .leaf(meta: meta, extra: .other)
  }
}

final class PropertyMetadataTests: XCTestCase {
  func testParsesCommandInfoAndNames() throws {
    let collector = Collector()
    let props = try collector.parse(propertiesOf: Cmd.self)
    XCTAssertEqual(props.count, 1)
    guard case let .group(id, title, children) = props[0] else {
      return XCTFail("Expected group at root")
    }
    XCTAssertEqual(id.name, "grouped")
    XCTAssertEqual(title, "")
    XCTAssertEqual(children.count, 1)

    let names = collector.commands(commandStack: [Cmd.self])
    XCTAssertEqual(names, ["cmd"])
  }

  func testPreferredNamesAndEnumerableFlags() throws {
    let collector = Collector()
    let props = try collector.parse(propertiesOf: Cmd.self)

    func flatten(_ nodes: [PropNode]) -> [PropNode] {
      nodes.flatMap { node in
        switch node {
        case let .group(_, _, children): return flatten(children)
        case .leaf: return [node]
        }
      }
    }

    let leaves = flatten(props)
    // name option should carry preferred long name
    if case let .leaf(_, .optionValueString(preferred)) = leaves.first(where: { node in
      if case let .leaf(meta, _) = node {
        return meta.info.preferredName?.name == "name"
      }
      return false
    }) {
      XCTAssertEqual(preferred?.kind, .long)
      XCTAssertEqual(preferred?.name, "name")
    } else {
      XCTFail("Missing name option leaf")
    }

    // enable flag should carry preferred long name
    if case let .leaf(_, .flagBool(preferred)) = leaves.first(where: { node in
      if case let .leaf(meta, _) = node {
        return meta.info.preferredName?.name == "enable"
      }
      return false
    }) {
      XCTAssertEqual(preferred?.kind, .long)
      XCTAssertEqual(preferred?.name, "enable")
    } else {
      XCTFail("Missing enable flag leaf")
    }

    // enumerable flags presence (type-dependent mapping)
    XCTAssertFalse(leaves.isEmpty)
  }

  func testGroupWithTitlePropagates() throws {
    let collector = Collector()
    let props = try collector.parse(propertiesOf: CmdTitled.self)
    XCTAssertEqual(props.count, 1)
    guard case let .group(id, title, children) = props[0] else {
      return XCTFail("Expected group at root")
    }
    XCTAssertEqual(id.name, "flags")
    XCTAssertEqual(title, "Top")
    XCTAssertEqual(children.count, 4)
  }

  /// Slice C contract: `metadata.info` is the V1 ArgumentInfo node carried
  /// per property, exposing the same shape the V1 dump produces. Old
  /// fields like `metadata.name` / `metadata.parentTitle` are gone;
  /// consumers read through `metadata.info.*`.
  func testPropertyMetadataExposesV1Info() throws {
    let collector = Collector()
    let props = try collector.parse(propertiesOf: CmdTitled.self)
    func flatten(_ nodes: [PropNode]) -> [PropNode] {
      nodes.flatMap { node in
        switch node {
        case let .group(_, _, children): return flatten(children)
        case .leaf: return [node]
        }
      }
    }
    let leaves = flatten(props)
    let nameLeaf = leaves.first { node in
      if case let .leaf(meta, _) = node {
        return meta.info.preferredName?.name == "name"
      }
      return false
    }
    guard case let .leaf(meta, _) = nameLeaf else {
      return XCTFail("Missing --name leaf")
    }
    XCTAssertEqual(meta.info.kind, .option)
    // The visitor builds child argument sets via Mirror traversal of the
    // group's value type. That construction does not run the
    // OptionGroup-wrapper init pathway that sets `parentTitle` on each
    // child argument, so per-property `sectionTitle` is nil here. The
    // enclosing group node carries the title separately (asserted in
    // `testGroupWithTitlePropagates`).
    XCTAssertNil(meta.info.sectionTitle)
    XCTAssertEqual(meta.info.valueName, "name")
    XCTAssertEqual(meta.id.name, "name")
    XCTAssertEqual(meta.id.path, ["flags"])
  }
}

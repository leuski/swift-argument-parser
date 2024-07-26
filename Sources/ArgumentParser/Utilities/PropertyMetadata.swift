//
//  PropertyMetadata.swift
//  ArgumentParser
//
//  Created by Anton Leuski on 11/4/20.
//

// This is created to be very similar to the
// ArgumnetInfoV0 struct. Key deifferences:
// - we store parsingStrategy for the property. We need it to generate the
//    command line correctly.
// - we can get the initial value by forcing the property to parse the
//    default value. It looks more relaible than getting the defaultValue from
//    the info structure
// - we get property id from the variable name
// - and the type of the property wrapper in case we need to warn the
//    programmer about a missing editor

public enum PropertyMetadataNamespace {
  public struct ArgumentParsing {
    public let propertyID: String
    public let strategy: ArgumentArrayParsingStrategy
    public init(id: String, strategy: ArgumentArrayParsingStrategy) {
      self.propertyID = id
      self.strategy = strategy
    }
    init(key: InputKey, strategy: ArgumentArrayParsingStrategy) {
      self.init(id: key.fullPath.joined(separator: "."), strategy: strategy)
    }
  }

  public struct OptionParsing {
    public enum Strategy {
      case array(ArrayParsingStrategy)
      case singleValue(SingleValueParsingStrategy)
    }
    public let propertyID: String
    public let strategy: Strategy
    public let preferredName: NameInfo?
    public init(id: String, strategy: Strategy, preferredName: NameInfo?) {
      self.propertyID = id
      self.strategy = strategy
      self.preferredName = preferredName
    }
    init(key: InputKey, strategy: Strategy, preferredName: NameInfo?) {
      self.init(
        id: key.fullPath.joined(separator: "."),
        strategy: strategy, preferredName: preferredName)
    }
  }

  public struct FlagParsing {
    public enum Kind {
      case regular(NameInfo?)
      case enumerated([NameInfo?])
    }
    public let propertyID: String
    public let kind: Kind
    public init(id: String, kind: Kind) {
      self.propertyID = id
      self.kind = kind
    }
    init(key: InputKey, kind: Kind) {
      self.init(id: key.fullPath.joined(separator: "."), kind: kind)
    }
  }

  public enum Kind {
    case argument(ArgumentParsing)
    case option(OptionParsing)
    case flag(FlagParsing)
  }

  /// Information about an argument's name.
  public struct NameInfo: Codable, Hashable {
    /// Kind of prefix of an argument's name.
    public enum Kind: String, Codable, Hashable {
      /// A multi-character name preceded by two dashes.
      case long
      /// A single character name preceded by a single dash.
      case short
      /// A multi-character name preceded by a single dash.
      case longWithSingleDash
    }

    /// Kind of prefix the NameInfo describes.
    public var kind: Kind
    /// Single or multi-character name of the argument.
    public var name: String

    public init(kind: NameInfo.Kind, name: String) {
      self.kind = kind
      self.name = name
    }
  }
}

fileprivate extension PropertyMetadataNamespace.NameInfo {
  init(name: Name) {
    switch name {
    case let .long(n):
      self.init(kind: .long, name: n)
    case let .short(n, _):
      self.init(kind: .short, name: String(n))
    case let .longWithSingleDash(n):
      self.init(kind: .longWithSingleDash, name: n)
    }
  }
}

private protocol _MetadataExtractor {
  func _metadata<P: CommandModelParser>(
    for key: InputKey, parser: P) throws -> [P.Property]
}

extension _MetadataExtractor where Self: ParsedWrapper {
  func _argument(for key: InputKey) -> ArgumentDefinition? {
    argumentSet(for: key).first { argument in
      switch argument.kind {
      case .named, .positional: return true
      case .default: return false
      }
    }
  }

  func _initialValue(
    argument: ArgumentDefinition, for key: InputKey) -> Value?
  {
    do {
      var values = ParsedValues(originalInput: [])
      try argument.initial(InputOrigin(), &values)
      return values.elements[key]?.value as? Value
    } catch {
      return nil
    }
  }
}

extension OptionGroup: _MetadataExtractor {
  func _metadata<P: CommandModelParser>(
    for key: InputKey, parser: P) throws -> [P.Property]
  {
    try parser._parse(Value.self, parent: key)
  }
}

extension Argument: _MetadataExtractor {
  func _metadata<P: CommandModelParser>(
    for key: InputKey, parser: P) throws -> [P.Property]
  {
    guard let argument = _argument(for: key) else { return [] }
    return [try parser.parse(
      property: PropertyMetadataNamespace
        .PropertyInfo(
          .argument(PropertyMetadataNamespace.ArgumentParsing(
            key: key,
            strategy: .init(base: argument.parsingStrategy))),
          argument: argument, key: key),
      initialValue: _initialValue(argument: argument, for: key))]
  }
}

private protocol _Array {
  static var _elementType: Any.Type { get }
}
extension Array: _Array {
  static var _elementType: Any.Type { Element.self }
}
private protocol _Optional {
  static var _wrappedType: Any.Type { get }
}
extension Optional: _Optional {
  static var _wrappedType: Any.Type { Wrapped.self }
}

private extension ArgumentDefinition {
  var _preferredName: PropertyMetadataNamespace.NameInfo? {
    names.preferredName.map(
      PropertyMetadataNamespace.NameInfo.init)
  }
}

extension Option: _MetadataExtractor  {
  private static var _isArray: Bool { Value.self is _Array.Type }

  func _metadata<P: CommandModelParser>(
    for key: InputKey, parser: P) throws -> [P.Property]
  {
    guard let argument = _argument(for: key) else { return [] }
    return [try parser.parse(
      property: PropertyMetadataNamespace
        .PropertyInfo(
          .option(PropertyMetadataNamespace.OptionParsing(
            key: key,
            strategy: Self._isArray
            ? .array(.init(base: argument.parsingStrategy))
            : .singleValue(.init(base: argument.parsingStrategy)),
            preferredName: argument._preferredName)),
          argument: argument, key: key),
      initialValue: _initialValue(argument: argument, for: key))]
  }
}

private extension EnumerableFlag {
  static var _names: [PropertyMetadataNamespace.NameInfo?] {
    allCases.map { item in
      name(for: item)
        .makeNames(InputKey(name: String(describing: item), parent: nil))
        .preferredName
        .map(PropertyMetadataNamespace.NameInfo.init)
    }
  }
}

extension Flag: _MetadataExtractor  {
  func _metadata<P: CommandModelParser>(
    for key: InputKey, parser: P) throws -> [P.Property]
  {
    guard let argument = _argument(for: key) else { return [] }
    let kind: PropertyMetadataNamespace.FlagParsing.Kind
    switch Value.self {
    case let type as any EnumerableFlag.Type:
      kind = .enumerated(type._names)
    case let type as _Optional.Type:
      if let elemType = type._wrappedType as? any EnumerableFlag.Type {
        kind = .enumerated(elemType._names)
      } else {
        kind = .regular(argument._preferredName)
      }
    case let type as _Array.Type:
      if let elemType = type._elementType as? any EnumerableFlag.Type {
        kind = .enumerated(elemType._names)
      } else {
        kind = .regular(argument._preferredName)
      }
    default:
      kind = .regular(argument._preferredName)
    }
    return [try parser.parse(
      property: PropertyMetadataNamespace
        .PropertyInfo(
          .flag(PropertyMetadataNamespace.FlagParsing(
            key: key,
            kind: kind)),
          argument: argument, key: key),
      initialValue: _initialValue(argument: argument, for: key))]
  }
}

extension PropertyMetadataNamespace {
  public struct PropertyInfo {
    internal init(
      _ kind: Kind,
      argument: ArgumentDefinition,
      key: InputKey)
    {
      self.kind = kind
      self.name = argument.valueName
      self.abstract = argument.help.abstract
      self.discussion = argument.help.discussion
      self.id = "." + key.fullPath.joined(separator: ".")
      self.parentTitle = argument.help.parentTitle
    }

    public let name: String
    public let abstract: String
    public let discussion: String
    public let kind: Kind
    public let id: String
    public let parentTitle: String
  }

  public struct CommandInfo {
    internal init(
      name: String, abstract: String, discussion: String)
    {
      self.name = name
      self.abstract = abstract
      self.discussion = discussion
    }

    public let name: String
    public let abstract: String
    public let discussion: String
  }
}

public protocol CommandModelParser {
  associatedtype Property

  func parse<V>(
    property: PropertyMetadataNamespace.PropertyInfo,
    initialValue: V?) throws -> Property

  func parse(
    propertiesOf command: ParsableCommand.Type) throws -> [Property]

  func commands(
    commandStack: [ParsableCommand.Type]) -> [String]

  func info(
    of command: ParsableCommand.Type) -> PropertyMetadataNamespace.CommandInfo
}

public extension CommandModelParser {
  fileprivate func _parse(
    _ type: ParsableArguments.Type, parent: InputKey? = nil) throws
  -> [Property]
  {
    try Mirror(reflecting: type.init())
      .children
      .compactMap { child -> [Property]? in
        guard let childLabel = child.label
        else { return nil }
        let key = InputKey(name: childLabel, parent: parent)
        return try (child.value as? _MetadataExtractor)?
          ._metadata(for: key, parser: self)
      }
      .flatMap { $0 }
  }

  func parse(
    propertiesOf command: ParsableCommand.Type) throws -> [Property]
  {
    try _parse(command)
  }

  func commands(commandStack: [ParsableCommand.Type]) -> [String]
  {
    let commands = commandStack.map { $0._commandName }
    guard let superName = commandStack.first?.configuration._superCommandName
    else { return commands }
    return [superName] + commands
  }

  func info(
    of command: ParsableCommand.Type) -> PropertyMetadataNamespace.CommandInfo
  {
    PropertyMetadataNamespace.CommandInfo(
      name: command._commandName,
      abstract: command.configuration.abstract,
      discussion: command.configuration.discussion)
  }
}

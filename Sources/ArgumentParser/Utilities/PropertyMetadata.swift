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

// MARK: - public code

/// A unique namespace for most of the types we added.
public enum PropertyMetadataNamespace {

  /// The kind of the property we parsed with associated values
  public enum Kind: Sendable {
    case singleArgument
    case arrayArgument(ArgumentArrayParsingStrategy)
    case singleOption(SingleValueParsingStrategy, NameInfo?)
    case arrayOption(ArrayParsingStrategy, NameInfo?)
    /// A flag can be a regular one (Bool or Int) or an enumarated value
    case regularFlag(NameInfo?)
    case enumeratedFlag([NameInfo?])
  }

  /// Information about an argument's name.
  public struct NameInfo: Codable, Hashable, Sendable {
    /// Kind of prefix of an argument's name.
    public enum Kind: String, Codable, Hashable, Sendable {
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

    public init(kind: Kind, name: String) {
      self.kind = kind
      self.name = name
    }
  }

  public struct PropertyIdentifier: Sendable, Hashable,
                                    CustomStringConvertible
  {
    public let name: String
    public let path: [String]
    public var fullPath: [String] { path + [name] }
    public var description: String { fullPath.joined(separator: ".") }

    public init(name: String, path: [String] = []) {
      self.name = name
      self.path = path
    }

    fileprivate init(key: InputKey) {
      self.init(name: key.name, path: key.path)
    }
  }

  /// Metadata for a property
  public struct PropertyInfo {
    fileprivate init(
      _ kind: Kind,
      argument: ArgumentDefinition,
      key: InputKey)
    {
      self.kind = kind
      self.name = argument.valueName
      self.abstract = argument.help.abstract
      self.discussion = argument.help.discussion
      self.id = PropertyIdentifier(key: key)
      self.parentTitle = argument.help.parentTitle
    }

    /// the property name
    public let name: String
    /// the abstract taken from the `Help` data strcuture.
    /// Can be an empty string.
    public let abstract: String
    /// the discussion taken from the `Help` data strcuture.
    /// Can be an empty string.
    public let discussion: String
    /// the property kind-specific metadata
    public let kind: Kind
    /// the property identifier. It is unique for a given command.
    public let id: PropertyIdentifier
    /// the property parent (group) title, if present.
    /// Otherwise, an empty string.
    public let parentTitle: String
  }

  /// Metadata for a `ParsableCommand`
  public struct CommandInfo {
    fileprivate init(
      name: String, abstract: String, discussion: String)
    {
      self.name = name
      self.abstract = abstract
      self.discussion = discussion
    }

    /// the command name
    public let name: String
    /// the abstract taken from the `Help` data strcuture.
    /// Can be an empty string.
    public let abstract: String
    /// the discussion taken from the `Help` data strcuture.
    /// Can be an empty string.
    public let discussion: String
  }
}

/// Property metadata parser protocol. Implement the protocol to support
/// parsing and collecting information about the command/property tree.
///
/// We cannot put protocols into a enum, so we have to pollute the global
/// namespace.
public protocol PropertyMetadataParser {
  /// Parser should return an object of this type for each property intance.
  associatedtype Property
  /// Property metadata
  typealias PropertyInfo = PropertyMetadataNamespace.PropertyInfo
  /// Command metadata
  typealias CommandInfo = PropertyMetadataNamespace.CommandInfo
  typealias PropertyIdentifier = PropertyMetadataNamespace.PropertyIdentifier


  /// Returns a new property object corresponding to an `OptionGroup`.
  /// - Parameters:
  ///   - id: the property identifier created from the group name
  ///   and the names of all enclosing `OptionGroup` objects.
  ///   - title: the group title
  ///   - children: the group children properties.
  /// - Returns: an object that describes the property group.
  func parse(
    group id: PropertyIdentifier,
    title: String,
    children: [Property]) throws -> Property

  /// Returns a new property object corresponding to a property.
  /// - Parameters:
  ///   - property: the property metadata
  ///   - initialValue: the initial value, if specified.
  /// - Returns: an object that describes the property.
  func parse<V>(
    property: PropertyInfo,
    initialValue: V?) throws -> Property

  /// Returns the list of property objects for each property in the
  /// `ParsableCommand` type.
  ///
  /// Default implementation provided.
  /// - Parameter command: the command type
  /// - Returns: a list of `Property` objects.
  func parse(
    propertiesOf command: ParsableCommand.Type) throws -> [Property]

  /// Given a command stack, returns a list of names for all commands in the
  /// stack.
  ///
  /// Default implementation provided.
  /// - Parameter commandStack: the command stack
  /// - Returns: command names
  func commands(
    commandStack: [ParsableCommand.Type]) -> [String]

  /// Returns a `ParsableCommand` type metadata.
  ///
  /// Default implementation provided.
  /// - Parameter command: the command type
  /// - Returns: the type metadata
  func info(
    of command: ParsableCommand.Type) -> CommandInfo
}

extension PropertyMetadataParser {
  fileprivate func _parse(
    _ type: ParsableArguments.Type, parent: InputKey? = nil) throws
  -> [Property]
  {
    try Mirror(reflecting: type.init())
      .children
      .compactMap { child -> Property? in
        guard let childLabel = child.label
        else { return nil }
        let key = InputKey(name: childLabel, parent: parent)
        return try (child.value as? _MetadataExtractor)?
          ._metadata(for: key, parser: self)
      }
  }

  public func parse(
    propertiesOf command: ParsableCommand.Type) throws -> [Property]
  {
    try _parse(command)
  }

  public func commands(commandStack: [ParsableCommand.Type]) -> [String]
  {
    let commands = commandStack.map { $0._commandName }
    guard let superName = commandStack.first?.configuration._superCommandName
    else { return commands }
    return [superName] + commands
  }

  public func info(
    of command: ParsableCommand.Type) -> CommandInfo
  {
    CommandInfo(
      name: command._commandName,
      abstract: command.configuration.abstract,
      discussion: command.configuration.discussion)
  }
}

// MARK: - private code

extension PropertyMetadataNamespace.NameInfo {
  fileprivate init(name: Name) {
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
  typealias Kind = PropertyMetadataNamespace.Kind
  func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
}

extension _MetadataExtractor where Self: ParsedWrapper {
  fileprivate func _argument(for key: InputKey) -> ArgumentDefinition? {
    argumentSet(for: key).first { argument in
      switch argument.kind {
      case .named, .positional: return true
      case .default: return false
      }
    }
  }

  fileprivate func _initialValue(
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
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    try parser.parse(
      group: PropertyMetadataNamespace.PropertyIdentifier(key: key),
      title: self.title,
      children: parser._parse(Value.self, parent: key))
  }
}

extension Argument: _MetadataExtractor {
  private static var _isArray: Bool { Value.self is _Array.Type }

  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    guard let argument = _argument(for: key) else { return nil }
    return try parser.parse(
      property: PropertyMetadataNamespace
        .PropertyInfo(
          Self._isArray
          ? .arrayArgument(.init(base: argument.parsingStrategy))
          : .singleArgument,
          argument: argument, key: key),
      initialValue: _initialValue(argument: argument, for: key))
  }
}

private protocol _Array {
  static var _elementType: Any.Type { get }
}
extension Array: _Array {
  fileprivate static var _elementType: Any.Type { Element.self }
}
private protocol _Optional {
  static var _wrappedType: Any.Type { get }
}
extension Optional: _Optional {
  fileprivate static var _wrappedType: Any.Type { Wrapped.self }
}

extension ArgumentDefinition {
  fileprivate var _preferredName: PropertyMetadataNamespace.NameInfo? {
    names.preferredName.map(
      PropertyMetadataNamespace.NameInfo.init)
  }
}

extension Option: _MetadataExtractor  {
  private static var _isArray: Bool { Value.self is _Array.Type }

  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    guard let argument = _argument(for: key) else { return nil }
    return try parser.parse(
      property: PropertyMetadataNamespace
        .PropertyInfo(
          Self._isArray
          ? .arrayOption(
            .init(base: argument.parsingStrategy), argument._preferredName)
          : .singleOption(
            .init(base: argument.parsingStrategy), argument._preferredName),
          argument: argument, key: key),
      initialValue: _initialValue(argument: argument, for: key))
  }
}

extension EnumerableFlag {
  fileprivate static var _names: [PropertyMetadataNamespace.NameInfo?] {
    allCases.map { item in
      name(for: item)
        .makeNames(InputKey(name: String(describing: item), parent: nil))
        .preferredName
        .map(PropertyMetadataNamespace.NameInfo.init)
    }
  }
}

private func unwrapEnumerableFlag(
  _ type: Any.Type?) -> (any EnumerableFlag.Type)?
{
  guard let type else { return nil }
  return (type as? any EnumerableFlag.Type)
  ?? unwrapEnumerableFlag((type as? _Optional.Type)?._wrappedType)
  ?? unwrapEnumerableFlag((type as? _Array.Type)?._elementType)
}

extension Flag: _MetadataExtractor  {
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    guard let argument = _argument(for: key) else { return nil }
    let kind: Kind
    if let type = unwrapEnumerableFlag(Value.self) {
      kind = .enumeratedFlag(type._names)
    } else {
      kind = .regularFlag(argument._preferredName)
    }
    return try parser.parse(
      property: PropertyMetadataNamespace
        .PropertyInfo(
          kind, argument: argument, key: key),
      initialValue: _initialValue(argument: argument, for: key))
  }
}

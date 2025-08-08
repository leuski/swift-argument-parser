//
//  PropertyMetadata.swift
//  ArgumentParser
//
//  Created by Anton Leuski on 11/4/20.
//

// The ArgumentInfoV0 might have been useful here. However,
// - we store parsingStrategy for the property. We need it to generate the
//    command line correctly.
// - we can get the initial value by forcing the property to parse the
//    default value. It looks more reliable than getting the defaultValue from
//    the info structure
// - we get property id from the variable name

// MARK: - public code
/// A minimal abstraction that erases concrete property wrappers into a common
/// interface for metadata extraction. Each concrete wrapper in
/// `PropertyMetadataNamespace` conforms to this protocol.
public protocol PropertyWrapper<Value> {
  associatedtype Value
  var value: Value? { get }
  var metadata: PropertyMetadataNamespace.PropertyMetadata { get }
}

/// A unique namespace for most of the types added by the metadata layer.
///
/// This namespace hosts plain data structures used by the parser to describe
/// arguments, options, flags, and their groupings in a form suitable for UI
/// or tooling.
public enum PropertyMetadataNamespace {
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

  /// Uniquely identifies a property within a command by path and name.
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

  /// Metadata for a property extracted from its `ArgumentDefinition`.
  public struct PropertyMetadata {
    fileprivate init(
      argument: ArgumentDefinition,
      key: InputKey)
    {
      self.name = argument.valueName
      self.abstract = argument.help.abstract
      self.discussion = argument.help.discussion
      self.id = PropertyIdentifier(key: key)
      self.parentTitle = argument.help.parentTitle
    }

    /// the property name
    public let name: String
    /// the abstract taken from the `Help` data structure.
    /// Can be an empty string.
    public let abstract: String
    /// the discussion taken from the `Help` data structure.
    /// Can be an empty string.
    public let discussion: String
    /// the property identifier. It is unique for a given command.
    public let id: PropertyIdentifier
    /// the property parent (group) title, if present.
    /// Otherwise, an empty string.
    public let parentTitle: String
  }

  /// Metadata for a `ParsableCommand` extracted from its configuration.
  public struct CommandMetadata {
    fileprivate init(
      name: String, abstract: String, discussion: String)
    {
      self.name = name
      self.abstract = abstract
      self.discussion = discussion
    }

    /// the command name
    public let name: String
    /// the abstract taken from the `Help` data structure.
    /// Can be an empty string.
    public let abstract: String
    /// the discussion taken from the `Help` data structure.
    /// Can be an empty string.
    public let discussion: String
  }

  // If you look over Argument, Option, and Flag types,
  // you can see very specific usage cases they are designed for. For example,
  // an array value is handled differently from a regular value; Flag
  // allows arrays and optionals for EnumerableFlag types only; etc.
  // Each of these types corresponds to a single case of a parsable
  // property wrapper.
  // We handle arrays and optionals separately from the regular values,
  // because we need to access the Element and Wrapped associated type
  // easily in the parser.

  /// Metadata/value container for `Argument<[Element]>`.
  public struct ArgumentArray<Element>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: ArgumentArrayParsingStrategy
    public let value: [Element]?
  }

  /// Metadata/value container for `Argument<Wrapped?>`.
  public struct ArgumentOptional<Wrapped>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let value: Wrapped??
  }

  /// Metadata/value container for `Argument<Value>`.
  public struct ArgumentValue<Value>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let value: Value?
  }

  /// Metadata/value container for `Option<[Element]>` with array strategy.
  public struct OptionArray<Element>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: ArrayParsingStrategy
    public let preferredName: NameInfo?
    public let value: [Element]?
  }

  /// Metadata/value container for `Option<Wrapped?>` with single-value strategy.
  public struct OptionOptional<Wrapped>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: SingleValueParsingStrategy
    public let preferredName: NameInfo?
    public let value: Wrapped??
  }

  /// Metadata/value container for `Option<Value>` with single-value strategy.
  public struct OptionValue<Value>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: SingleValueParsingStrategy
    public let preferredName: NameInfo?
    public let value: Value?
  }

  /// Metadata/value container for `Flag<[EnumerableFlag]>`.
  public struct EnumerableFlagArray<Element>: PropertyWrapper
  where Element: EnumerableFlag
  {
    public let metadata: PropertyMetadata
    public let names: [NameInfo?]
    public let value: [Element]?
  }

  /// Metadata/value container for `Flag<Wrapped?>` where `Wrapped: EnumerableFlag`.
  public struct EnumerableFlagOptional<Wrapped>: PropertyWrapper
  where Wrapped: EnumerableFlag
  {
    public let metadata: PropertyMetadata
    public let names: [NameInfo?]
    public let value: Wrapped??
  }

  /// Metadata/value container for `Flag<Value>` where `Value: EnumerableFlag`.
  public struct EnumerableFlagValue<Value>: PropertyWrapper
  where Value: EnumerableFlag
  {
    public let metadata: PropertyMetadata
    public let names: [NameInfo?]
    public let value: Value?
  }

  /// Metadata/value container for `Flag<Value>` (non-enumerable).
  public struct FlagValue<Value>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let preferredName: NameInfo?
    public let value: Value?
  }
}

/// Property metadata parser protocol. Implement the protocol to support
/// parsing and collecting information about the command/property tree.
///
/// We cannot put protocols into a enum, so we have to pollute the global
/// namespace.
/// Protocol to traverse a `ParsableCommand` type and produce metadata objects
/// for each property and group. Default implementations are provided for
/// walking the type and extracting names/initial values.
public protocol PropertyMetadataParser {
  /// Parser should return an object of this type for each property instance.
  associatedtype Property
  /// Command metadata
  typealias CommandMetadata = PropertyMetadataNamespace.CommandMetadata
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
  
  /// Returns a new property object corresponding to an `Argument`, `Option`,
  /// or `Flag`.
  ///
  /// This is the main parsing method. The argument represents individual
  /// property description and the initial value if it exists. We handle
  /// different property use cases separately.
  /// - Parameter box: the property description.
  /// - Returns: an object that describes the property.
  func parse<V>(_ wrapper: any PropertyWrapper<V>) throws -> Property

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
    of command: ParsableCommand.Type) -> CommandMetadata
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
    of command: ParsableCommand.Type) -> CommandMetadata
  {
    CommandMetadata(
      name: command._commandName,
      abstract: command.configuration.abstract,
      discussion: command.configuration.discussion)
  }
}

// MARK: - private code

private typealias PropertyInfo = PropertyMetadataNamespace.PropertyMetadata
private typealias NameInfo = PropertyMetadataNamespace.NameInfo

extension NameInfo {
  /// Convert internal `Name` (parser representation) into public
  /// `NameInfo`. We normalize the shape so clients do not depend on
  /// internal enums and keep only two fields: `kind` and `name`.
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
  /// Implemented by property wrappers and groups to extract their
  /// metadata using a uniform API. This avoids exposing concrete
  /// wrapper types to the `PropertyMetadataParser` and keeps the
  /// traversal generic.
  func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
}

extension _MetadataExtractor where Self: ParsedWrapper {
  /// Find the `ArgumentDefinition` that corresponds to a property key.
  /// We look for either a named or positional definition and ignore
  /// entries that represent default values.
  fileprivate func _argument(for key: InputKey) -> ArgumentDefinition? {
    argumentSet(for: key).first { argument in
      switch argument.kind {
      case .named, .positional: return true
      case .default: return false
      }
    }
  }

  /// Attempt to compute the initial value for a property by invoking
  /// the wrapper's `initial` closure against an empty `ParsedValues`.
  ///
  /// This leverages the parser's own defaulting rules instead of
  /// duplicating them. If any failure occurs, we treat it as absence
  /// of initial value and return `nil`.
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
  /// When encountering an `OptionGroup`, we synthesize a group node
  /// using the current key and the group's title, then recurse into
  /// the group's fields to gather child properties.
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    try parser.parse(
      group: PropertyMetadataNamespace.PropertyIdentifier(key: key),
      title: self.title,
      children: parser._parse(Value.self, parent: key))
  }
}

private protocol _Array {
  /// Bridge arrays for both Argument and Option cases. This protocol
  /// allows us to dispatch based on the array's element type while
  /// preserving the difference between Argument strategies and
  /// Option strategies.
  static func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P) throws -> P.Property
  static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P) throws -> P.Property
}

private protocol _EnumerableFlagArray {
  /// Bridge arrays of `EnumerableFlag` values. Each case corresponds
  /// to a concrete wrapper emitted to the parser.
  static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
}

extension Array: _Array {
  /// Emit an `ArgumentArray` wrapper without an initial value. Used
  /// when no default is present for an array argument.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.ArgumentArray(
      metadata: argument, strategy: strategy, value: nil as Self?))
  }
  /// Emit an `ArgumentArray` wrapper with the initial value captured
  /// from the property wrapper instance.
  fileprivate func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.ArgumentArray(
      metadata: argument, strategy: strategy, value: self))
  }
  /// Emit an `OptionArray` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.OptionArray(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: nil as Self?))
  }
  /// Emit an `OptionArray` wrapper with the initial value captured
  /// from the property wrapper instance.
  fileprivate func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.OptionArray(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: self))
  }
}

extension Array: _EnumerableFlagArray where Element: EnumerableFlag {
  /// Emit an `EnumerableFlagArray` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    return try parser.parse(PropertyMetadataNamespace.EnumerableFlagArray(
      metadata: enumerableFlag, names: Element._names,
      value: nil as Self?))
  }
  /// Emit an `EnumerableFlagArray` wrapper with the initial value.
  fileprivate func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    return try parser.parse(PropertyMetadataNamespace.EnumerableFlagArray(
      metadata: enumerableFlag, names: Element._names,
      value: self))
  }
}

private protocol _Optional {
  /// Bridge optionals for both Argument and Option cases. We separate
  /// the array vs value strategies and carry preferred names for
  /// options to support formatter construction.
  static func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P) throws -> P.Property
  static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P) throws -> P.Property
}

private protocol _EnumerableFlagOptional {
  /// Bridge optional `EnumerableFlag` values for flag wrappers.
  static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
}

extension Optional: _Optional {
  /// Emit an `ArgumentOptional` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.ArgumentOptional(
      metadata: argument, value: nil as Self?))
  }
  /// Emit an `ArgumentOptional` wrapper with the initial value.
  fileprivate func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.ArgumentOptional(
      metadata: argument, value: self))
  }
  /// Emit an `OptionOptional` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.OptionOptional(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: nil as Self?))
  }
  /// Emit an `OptionOptional` wrapper with the initial value.
  fileprivate func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P)
  throws -> P.Property
  {
    try parser.parse(PropertyMetadataNamespace.OptionOptional(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: self))
  }
}

extension Optional: _EnumerableFlagOptional where Wrapped: EnumerableFlag {
  /// Emit an `EnumerableFlagOptional` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    return try parser.parse(PropertyMetadataNamespace.EnumerableFlagOptional(
      metadata: enumerableFlag, names: Wrapped._names,
      value: nil as Self?))
  }
  /// Emit an `EnumerableFlagOptional` wrapper with the initial value.
  fileprivate func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    return try parser.parse(PropertyMetadataNamespace.EnumerableFlagOptional(
      metadata: enumerableFlag, names: Wrapped._names,
      value: self))
  }
}


extension ArgumentDefinition {
  /// Return the preferred name for an option, converted to `NameInfo`.
  /// This is used to set option key text when building command lines.
  fileprivate var _preferredName: NameInfo? {
    names.preferredName.map(NameInfo.init)
  }
}

extension Argument: _MetadataExtractor {
  /// Parse an `Argument` property. We determine whether the value is
  /// array, optional, or a simple value, taking into account any
  /// initial value produced by the wrapper. We then emit the
  /// corresponding wrapper instance into the client parser.
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    guard let argument = _argument(for: key) else { return nil }
    let propertyInfo = PropertyMetadataNamespace
      .PropertyMetadata(argument: argument, key: key)
    let initialValue = _initialValue(argument: argument, for: key)

    if let initialValue,
       let initialValue = initialValue as? _Array 
    {
      return try initialValue._parse(
        argument: propertyInfo,
        strategy: .init(base: argument.parsingStrategy), 
        with: parser)
    }

    if let type = Value.self as? any _Array.Type {
      return try type._parse(
        argument: propertyInfo,
        strategy: .init(base: argument.parsingStrategy),
        with: parser)
    }

    if let initialValue,
       let initialValue = initialValue as? _Optional 
    {
      return try initialValue._parse(argument: propertyInfo, with: parser)
    }

    if let type = Value.self as? any _Optional.Type {
      return try type._parse(argument: propertyInfo, with: parser)
    }

    return try parser.parse(PropertyMetadataNamespace.ArgumentValue(
      metadata: propertyInfo, value: initialValue))
  }
}

extension Option: _MetadataExtractor  {
  /// Parse an `Option` property. We branch on array vs optional vs
  /// value and pass the single-value parsing strategy and preferred
  /// name to the emitted wrapper so downstream formatters can choose
  /// the correct key placement.
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    guard let argument = _argument(for: key) else { return nil }
    let propertyInfo = PropertyMetadataNamespace
      .PropertyMetadata(argument: argument, key: key)
    let initialValue = _initialValue(argument: argument, for: key)

    if let initialValue,
       let initialValue = initialValue as? _Array 
    {
      return try initialValue._parse(
        option: propertyInfo,
        strategy: .init(base: argument.parsingStrategy),
        preferredName: argument._preferredName,
        with: parser)
    }

    if let type = Value.self as? any _Array.Type {
      return try type._parse(
        option: propertyInfo,
        strategy: .init(base: argument.parsingStrategy),
        preferredName: argument._preferredName,
        with: parser)
    }

    if let initialValue,
       let initialValue = initialValue as? _Optional 
    {
      return try initialValue._parse(
        option: propertyInfo,
        strategy: .init(base: argument.parsingStrategy),
        preferredName: argument._preferredName,
        with: parser)
    }

    if let type = Value.self as? any _Optional.Type {
      return try type._parse(
        option: propertyInfo,
        strategy: .init(base: argument.parsingStrategy),
        preferredName: argument._preferredName,
        with: parser)
    }

    return try parser.parse(PropertyMetadataNamespace.OptionValue(
      metadata: propertyInfo, strategy: .init(base: argument.parsingStrategy),
      preferredName: argument._preferredName, value: initialValue))
  }
}

extension EnumerableFlag {
  /// Compute display names for each enumerable flag case. The
  /// underlying parser can provide either short or long forms. We keep
  /// only the preferred name for each case.
  fileprivate static var _names: [NameInfo?] {
    allCases.map { item in
      name(for: item)
        .makeNames(InputKey(name: String(describing: item), parent: nil))
        .preferredName
        .map(NameInfo.init)
    }
  }
  /// Emit a flag value wrapper for the type itself and for an
  /// instance, carrying the names array so clients can render one flag
  /// per case.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    return try parser.parse(PropertyMetadataNamespace.EnumerableFlagValue(
      metadata: enumerableFlag, names: Self._names,
      value: nil as Self?))
  }
  fileprivate func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P)
  throws -> P.Property
  {
    return try parser.parse(PropertyMetadataNamespace.EnumerableFlagValue(
      metadata: enumerableFlag, names: Self._names,
      value: self))
  }
}

extension Flag: _MetadataExtractor  {
  /// Parse a `Flag` property. We support three shapes in addition to
  /// simple flags: array of cases, optional case, and single case.
  /// If none applies, we treat it as a plain flag value.
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P) throws -> P.Property?
  {
    guard let argument = _argument(for: key) else { return nil }
    let propertyInfo = PropertyMetadataNamespace
      .PropertyMetadata(argument: argument, key: key)
    let initialValue = _initialValue(argument: argument, for: key)

    if let initialValue,
       let initialValue = initialValue as? _EnumerableFlagArray 
    {
      return try initialValue._parse(enumerableFlag: propertyInfo, with: parser)
    }

    if let type = Value.self as? any _EnumerableFlagArray.Type {
      return try type._parse(enumerableFlag: propertyInfo, with: parser)
    }

    if let initialValue,
       let initialValue = initialValue as? _EnumerableFlagOptional 
    {
      return try initialValue._parse(enumerableFlag: propertyInfo, with: parser)
    }

    if let type = Value.self as? any _EnumerableFlagOptional.Type {
      return try type._parse(enumerableFlag: propertyInfo, with: parser)
    }

    if let initialValue,
       let initialValue = initialValue as? any EnumerableFlag 
    {
      return try initialValue._parse(enumerableFlag: propertyInfo, with: parser)
    }

    if let type = Value.self as? any EnumerableFlag.Type {
      return try type._parse(enumerableFlag: propertyInfo, with: parser)
    }

    return try parser.parse(PropertyMetadataNamespace.FlagValue(
      metadata: propertyInfo,
      preferredName: argument._preferredName, value: initialValue))
  }
}

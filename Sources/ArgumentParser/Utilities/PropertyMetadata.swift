//
//  PropertyMetadata.swift
//  ArgumentParser
//
//  Created by Anton Leuski on 11/4/20.
//

#if compiler(>=6.0)
public import ArgumentParserToolInfo
#else
import ArgumentParserToolInfo
#endif

/// A protocol-based visitor over the parsable property tree of a
/// `ParsableCommand`.
///
/// This file exposes a public surface that lets external tooling walk every
/// property of a command — its `@Argument`s, `@Option`s, `@Flag`s, and
/// nested `@OptionGroup`s — and receive a normalized description of each
/// one, anchored on a per-property `ArgumentInfoV1` node.
///
/// Conform a type to ``PropertyMetadataParser`` and call
/// ``PropertyMetadataParser/parse(propertiesOf:)`` to produce a tree of
/// your own `Property` values. Typical uses include shell-completion script
/// generators, alternative help renderers, and programmatic introspection
/// of parsable commands.
///
/// ### Why V1 and not V0?
///
/// V1 carries source-declaration order through `CommandChildV1`, decouples
/// `allValueDescriptions` from `discussion`, and is `Sendable`. The visitor
/// uses V1's per-property struct so consumers can work with the same shape
/// the tool-info dump produces. The wrapper structs additionally expose
/// kind-specific typed strategies (`SingleValueParsingStrategy`,
/// `ArrayParsingStrategy`) and a typed `value` field that V1 alone doesn't
/// surface.

// MARK: - Public surface

/// A type-erased view over a parsable property — `@Argument`, `@Option`,
/// or `@Flag` — produced while walking a command's property tree.
///
/// The concrete types that conform to this protocol live inside
/// ``PropertyMetadataNamespace`` and expose additional information specific
/// to each property kind (e.g. ``PropertyMetadataNamespace/OptionValue``
/// adds a parsing `strategy` and a `preferredName`). Cast a wrapper to its
/// concrete type to read those fields when needed.
public protocol PropertyWrapper<Value> {
  associatedtype Value

  /// The property's default value, if it has one.
  ///
  /// `nil` indicates that no default was provided. For optional properties
  /// the outer optional is the "has-default" flag and the inner optional
  /// is the value itself.
  var value: Value? { get }

  /// Description of the property, shared by every wrapper kind.
  var metadata: PropertyMetadataNamespace.PropertyMetadata { get }
}

/// Namespace for the metadata types produced by ``PropertyMetadataParser``.
///
/// Swift does not allow declaring protocols inside enums, so
/// ``PropertyMetadataParser`` and ``PropertyWrapper`` live at file scope.
/// Everything else — concrete metadata types and the per-kind wrappers —
/// is namespaced here to keep the public surface tidy.
public enum PropertyMetadataNamespace {
  /// Information about an argument's name on the command line.
  ///
  /// Aliased to `ArgumentInfoV1.NameInfo` (which itself aliases
  /// `ArgumentInfoV0.NameInfoV0`). Consumers reading `name.kind` and
  /// `name.name` see no shape change. Consumers that referenced the
  /// nested `NameInfo.Kind` type now reach it as
  /// `ArgumentInfoV0.NameInfoV0.KindV0` (the case shorthands `.long`,
  /// `.short`, `.longWithSingleDash` still work).
  public typealias NameInfo = ArgumentInfoV1.NameInfo

  /// A unique identifier for a property within a command.
  ///
  /// The identifier is composed of the property's variable name plus the
  /// names of any enclosing `@OptionGroup` properties, walking outward to
  /// the command type itself. Two distinct properties on the same command
  /// always have distinct ``PropertyIdentifier``s.
  public struct PropertyIdentifier:
    Sendable, Hashable, CustomStringConvertible
  {
    /// The property's variable name (the leaf of ``fullPath``).
    public let name: String
    /// The names of enclosing `@OptionGroup` properties, outermost first.
    public let path: [String]
    /// ``path`` followed by ``name`` — the full dotted identifier
    /// components.
    public var fullPath: [String] { path + [name] }
    /// ``fullPath`` joined with `.`.
    public var description: String { fullPath.joined(separator: ".") }

    public init(name: String, path: [String] = []) {
      self.name = name
      self.path = path
    }

    fileprivate init(key: InputKey) {
      self.init(name: key.name, path: key.path)
    }
  }

  /// Description of a single parsable property, anchored on its
  /// `ArgumentInfoV1` node and a stable `id`.
  ///
  /// Old fields like `metadata.name`, `metadata.abstract`,
  /// `metadata.discussion`, and `metadata.parentTitle` have been removed
  /// — read them from `metadata.info.valueName`,
  /// `metadata.info.abstract`, `metadata.info.discussion`, and
  /// `metadata.info.sectionTitle` respectively. The optionality of
  /// the new fields is intentional: V0's required-`String` form
  /// represented absence as `""`; V1 represents it as `nil`.
  public struct PropertyMetadata: Sendable, Hashable {
    /// Stable identifier for this property within its command.
    public let id: PropertyIdentifier
    /// V1 description of the property — names, kind, discussion, default
    /// value, allowed values, completion kind, etc.
    public let info: ArgumentInfoV1

    public init(id: PropertyIdentifier, info: ArgumentInfoV1) {
      self.id = id
      self.info = info
    }

    fileprivate init(argument: ArgumentDefinition, key: InputKey) {
      self.id = PropertyIdentifier(key: key)
      // The visitor only constructs PropertyMetadata for arguments whose
      // `kind` is `.named` or `.positional`, never `.default`. The V1 init
      // returns nil only for `.default`, so the force-unwrap is safe by
      // construction.
      guard let info = ArgumentInfoV1(argument: argument) else {
        preconditionFailure(
          "PropertyMetadata constructed for an ArgumentDefinition with "
          + "kind == .default; the visitor should have filtered it out.")
      }
      self.info = info
    }
  }

  /// Description of a `ParsableCommand` type — its name and help text.
  public struct CommandMetadata: Sendable, Hashable {
    fileprivate init(name: String, abstract: String, discussion: String) {
      self.name = name
      self.abstract = abstract
      self.discussion = discussion
    }

    /// The command's `_commandName`.
    public let name: String
    /// Short help text from the command's configuration. Empty if none.
    public let abstract: String
    /// Long discussion text from the command's configuration. Empty if
    /// none.
    public let discussion: String
  }

  // The wrapper structs below mirror the cases of @Argument, @Option, and
  // @Flag. Each public Argument/Option/Flag type supports several distinct
  // shapes — a regular value, an array, an optional, and (for @Flag) an
  // EnumerableFlag variant. We expose them as separate concrete types here
  // so the parser can read kind-specific fields (Element, Wrapped, parsing
  // strategy, preferred name, etc.) without further casting.

  /// Metadata for an `@Argument` array property.
  public struct ArgumentArray<Element>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: ArgumentArrayParsingStrategy
    public let value: [Element]?
  }

  /// Metadata for an `@Argument` optional property.
  public struct ArgumentOptional<Wrapped>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let value: Wrapped??
  }

  /// Metadata for a regular `@Argument` property.
  public struct ArgumentValue<Value>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let value: Value?
  }

  /// Metadata for an `@Option` array property.
  public struct OptionArray<Element>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: ArrayParsingStrategy
    public let preferredName: NameInfo?
    public let value: [Element]?
  }

  /// Metadata for an `@Option` optional property.
  public struct OptionOptional<Wrapped>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: SingleValueParsingStrategy
    public let preferredName: NameInfo?
    public let value: Wrapped??
  }

  /// Metadata for a regular `@Option` property.
  public struct OptionValue<Value>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let strategy: SingleValueParsingStrategy
    public let preferredName: NameInfo?
    public let value: Value?
  }

  /// Metadata for an `@Flag` array of `EnumerableFlag` cases.
  public struct EnumerableFlagArray<Element>: PropertyWrapper
  where Element: EnumerableFlag {
    public let metadata: PropertyMetadata
    public let names: [NameInfo?]
    public let value: [Element]?
  }

  /// Metadata for an optional `@Flag` of an `EnumerableFlag`.
  public struct EnumerableFlagOptional<Wrapped>: PropertyWrapper
  where Wrapped: EnumerableFlag {
    public let metadata: PropertyMetadata
    public let names: [NameInfo?]
    public let value: Wrapped??
  }

  /// Metadata for a regular `@Flag` of an `EnumerableFlag`.
  public struct EnumerableFlagValue<Value>: PropertyWrapper
  where Value: EnumerableFlag {
    public let metadata: PropertyMetadata
    public let names: [NameInfo?]
    public let value: Value?
  }

  /// Metadata for a regular Boolean-style `@Flag` property.
  public struct FlagValue<Value>: PropertyWrapper {
    public let metadata: PropertyMetadata
    public let preferredName: NameInfo?
    public let value: Value?
  }
}

// MARK: - Sendable conformances for the wrapper structs
//
// Each wrapper is a value type whose payload is `metadata` (Sendable),
// optional name/strategy fields (Sendable), and a generic value. The
// wrappers are therefore conditionally Sendable on the generic parameter.

extension PropertyMetadataNamespace.ArgumentArray: Sendable
where Element: Sendable {}

extension PropertyMetadataNamespace.ArgumentOptional: Sendable
where Wrapped: Sendable {}

extension PropertyMetadataNamespace.ArgumentValue: Sendable
where Value: Sendable {}

extension PropertyMetadataNamespace.OptionArray: Sendable
where Element: Sendable {}

extension PropertyMetadataNamespace.OptionOptional: Sendable
where Wrapped: Sendable {}

extension PropertyMetadataNamespace.OptionValue: Sendable
where Value: Sendable {}

extension PropertyMetadataNamespace.EnumerableFlagArray: Sendable
where Element: Sendable {}

extension PropertyMetadataNamespace.EnumerableFlagOptional: Sendable
where Wrapped: Sendable {}

extension PropertyMetadataNamespace.EnumerableFlagValue: Sendable
where Value: Sendable {}

extension PropertyMetadataNamespace.FlagValue: Sendable
where Value: Sendable {}

/// A visitor that walks a `ParsableCommand` and produces a custom
/// representation of every property it contains.
///
/// Conform a type to this protocol to walk the properties of a
/// `ParsableCommand` and produce your own per-property representation.
/// Implement ``parse(group:title:children:)`` to build a node for each
/// `@OptionGroup`, and ``parse(_:)`` to build a node for each individual
/// `@Argument`, `@Option`, or `@Flag`. Then call
/// ``parse(propertiesOf:)`` to receive the full list of nodes for a
/// command type.
public protocol PropertyMetadataParser {
  /// The parser-specific representation built for each property.
  associatedtype Property

  /// Convenience reference to ``PropertyMetadataNamespace/CommandMetadata``.
  typealias CommandMetadata = PropertyMetadataNamespace.CommandMetadata
  /// Convenience reference to
  /// ``PropertyMetadataNamespace/PropertyIdentifier``.
  typealias PropertyIdentifier = PropertyMetadataNamespace.PropertyIdentifier

  /// Returns a new property object corresponding to an `@OptionGroup`.
  /// - Parameters:
  ///   - id: the property identifier created from the group name and the
  ///     names of all enclosing `@OptionGroup` objects.
  ///   - title: the group title.
  ///   - children: the group's child properties.
  /// - Returns: an object that describes the property group.
  func parse(
    group id: PropertyIdentifier,
    title: String,
    children: [Property]
  ) throws -> Property

  /// Returns a new property object corresponding to an `@Argument`,
  /// `@Option`, or `@Flag`.
  ///
  /// This is the main parsing method. The wrapper carries the property
  /// description and the initial value if one exists. Distinct property
  /// shapes (array, optional, regular, enumerable-flag variants) arrive
  /// here as distinct concrete types from
  /// ``PropertyMetadataNamespace``.
  /// - Parameter wrapper: the property description.
  /// - Returns: an object that describes the property.
  func parse<V>(_ wrapper: any PropertyWrapper<V>) throws -> Property

  /// Returns the list of property objects for each property in the
  /// `ParsableCommand` type.
  ///
  /// Default implementation provided.
  /// - Parameter command: the command type.
  /// - Returns: a list of `Property` objects.
  func parse(
    propertiesOf command: ParsableCommand.Type
  ) throws -> [Property]

  /// Given a command stack, returns a list of names for all commands in
  /// the stack.
  ///
  /// Default implementation provided.
  /// - Parameter commandStack: the command stack.
  /// - Returns: command names.
  func commands(commandStack: [ParsableCommand.Type]) -> [String]

  /// Returns a `ParsableCommand` type's metadata.
  ///
  /// Default implementation provided.
  /// - Parameter command: the command type.
  /// - Returns: the type metadata.
  func info(of command: ParsableCommand.Type) -> CommandMetadata
}

extension PropertyMetadataParser {
  fileprivate func _parse(
    _ type: ParsableArguments.Type, parent: InputKey? = nil
  ) throws -> [Property] {
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
    propertiesOf command: ParsableCommand.Type
  ) throws -> [Property] {
    try _parse(command)
  }

  public func commands(commandStack: [ParsableCommand.Type]) -> [String] {
    let commands = commandStack.map { $0._commandName }
    guard let superName = commandStack.first?.configuration._superCommandName
    else { return commands }
    return [superName] + commands
  }

  public func info(of command: ParsableCommand.Type) -> CommandMetadata {
    CommandMetadata(
      name: command._commandName,
      abstract: command.configuration.abstract,
      discussion: command.configuration.discussion)
  }
}

// MARK: - Internal implementation

private typealias PropertyInfo = PropertyMetadataNamespace.PropertyMetadata
private typealias NameInfo = PropertyMetadataNamespace.NameInfo

private protocol _MetadataExtractor {
  /// Implemented by property wrappers and groups to extract their
  /// metadata using a uniform API. This avoids exposing concrete
  /// wrapper types to the `PropertyMetadataParser` and keeps the
  /// traversal generic.
  func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P
  ) throws -> P.Property?
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
    argument: ArgumentDefinition, for key: InputKey
  ) -> Value? {
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
    for key: InputKey, parser: P
  ) throws -> P.Property? {
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
    with parser: P
  ) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P
  ) throws -> P.Property
  static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property
}

private protocol _EnumerableFlagArray {
  /// Bridge arrays of `EnumerableFlag` values. Each case corresponds
  /// to a concrete wrapper emitted to the parser.
  static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property
}

extension Array: _Array {
  /// Emit an `ArgumentArray` wrapper without an initial value. Used
  /// when no default is present for an array argument.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.ArgumentArray(
      metadata: argument, strategy: strategy, value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    strategy: ArgumentArrayParsingStrategy,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.ArgumentArray(
      metadata: argument, strategy: strategy, value: self))
  }

  fileprivate static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.OptionArray(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: ArrayParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.OptionArray(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: self))
  }
}

extension Array: _EnumerableFlagArray where Element: EnumerableFlag {
  /// Emit an `EnumerableFlagArray` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.EnumerableFlagArray(
      metadata: enumerableFlag, names: Element._names,
      value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.EnumerableFlagArray(
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
    with parser: P
  ) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P
  ) throws -> P.Property
  static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property
}

private protocol _EnumerableFlagOptional {
  /// Bridge optional `EnumerableFlag` values for flag wrappers.
  static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property
  func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property
}

extension Optional: _Optional {
  /// Emit an `ArgumentOptional` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.ArgumentOptional(
      metadata: argument, value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    argument: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.ArgumentOptional(
      metadata: argument, value: self))
  }

  fileprivate static func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.OptionOptional(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    option: PropertyInfo,
    strategy: SingleValueParsingStrategy,
    preferredName: NameInfo?,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.OptionOptional(
      metadata: option, strategy: strategy, preferredName: preferredName,
      value: self))
  }
}

extension Optional: _EnumerableFlagOptional where Wrapped: EnumerableFlag {
  /// Emit an `EnumerableFlagOptional` wrapper without an initial value.
  fileprivate static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.EnumerableFlagOptional(
      metadata: enumerableFlag, names: Wrapped._names,
      value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.EnumerableFlagOptional(
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
    for key: InputKey, parser: P
  ) throws -> P.Property? {
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

extension Option: _MetadataExtractor {
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P
  ) throws -> P.Property? {
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
      metadata: propertyInfo,
      strategy: .init(base: argument.parsingStrategy),
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

  fileprivate static func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.EnumerableFlagValue(
      metadata: enumerableFlag, names: Self._names,
      value: nil as Self?))
  }

  fileprivate func _parse<P: PropertyMetadataParser>(
    enumerableFlag: PropertyInfo,
    with parser: P
  ) throws -> P.Property {
    try parser.parse(PropertyMetadataNamespace.EnumerableFlagValue(
      metadata: enumerableFlag, names: Self._names,
      value: self))
  }
}

extension Flag: _MetadataExtractor {
  fileprivate func _metadata<P: PropertyMetadataParser>(
    for key: InputKey, parser: P
  ) throws -> P.Property? {
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

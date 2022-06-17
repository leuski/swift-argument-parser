//
//  PropertyMetadata.swift
//  ArgumentParser
//
//  Created by Anton Leuski on 11/4/20.
//

fileprivate extension Collection {
  /// - returns: A non-empty collection or `nil`.
  var nonEmpty: Self? { isEmpty ? nil : self }
}

// This is adopted (from the old version) to be very similar to the
// ArgumnetInfoV0 struct. Key deifferences:
// - we store parsingStrategy for the property. We need it to generate the
//    command line correctly.
// - we can get the initial value by forcing the property to parse the
//    default value. It looks more relaible than getting the defaultValue from
//    the info structure
// - we get property id from the variable name
// - and the type of the property wrapper in case we need to warn the
//    programmer about a missing editor

public struct PropertyMetadata: Identifiable {
  // Copying from ArgumentDefinition
  /// This folds the public `ArrayParsingStrategy` and
  /// `SingleValueParsingStrategy`
  /// into a single enum.
  public enum ParsingStrategy {
    /// Expect the next `SplitArguments.Element` to be
    /// a value and parse it. Will fail if the next
    /// input is an option.
    case `default`
    /// Parse the next `SplitArguments.Element.value`
    case scanningForValue
    /// Parse the next `SplitArguments.Element` as
    /// a value, regardless of its type.
    case unconditional
    /// Parse multiple `SplitArguments.Element.value`
    /// up to the next non-`.value`
    case upToNextOption
    /// Parse all remaining `SplitArguments.Element`
    /// as values, regardless of its type.
    case allRemainingInput

    init(_ value: ArgumentDefinition.ParsingStrategy) {
      switch value {
      case .default: self = .default
      case .scanningForValue: self = .scanningForValue
      case .unconditional: self = .unconditional
      case .upToNextOption: self = .upToNextOption
      case .allRemainingInput: self = .allRemainingInput
      }
    }
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

  /// Kind of argument.
  public enum Kind: String, Codable, Hashable {
    /// Argument specified as a bare value on the command line.
    case positional
    /// Argument specified as a value prefixed by a `--flag` on the command line.
    case option
    /// Argument specified only as a `--flag` on the command line.
    case flag
  }

  public let kind: Kind
  /// All names of the argument.
  public var names: [NameInfo]?
  /// The best name to use when referring to the argument in help displays.
  public var preferredName: NameInfo?
  /// Name of argument's value.
  public let valueName: String?
  /// Short description of the argument's functionality.
  public var abstract: String?
  /// Extended description of the argument's functionality.
  public var discussion: String?

  public let parsingStrategy: ParsingStrategy

  public let id: String

  public let initialValue: Any?

  public let type: Any.Type

  init?(
    _ arg: ArgumentSet, key: InputKey, id: String, type: Any.Type)
  {
    self.type = type
    self.id = id
    guard
      let argument = arg.first(where: { Kind(argument: $0) != nil }),
      let kind = Kind(argument: argument)
    else { return nil }

    self.kind = kind
    self.names = argument.names.map(NameInfo.init)
    self.preferredName = argument.names.preferredName.map(NameInfo.init)
    self.valueName = argument.valueName.nonEmpty
    self.abstract = argument.help.abstract.nonEmpty
    self.discussion = argument.help.discussion.nonEmpty
    self.parsingStrategy = ParsingStrategy(argument.parsingStrategy)

    do {
      var values = ParsedValues(originalInput: [])
      try argument.initial(InputOrigin(), &values)
      self.initialValue = values.elements[key]?.value
    } catch {
      self.initialValue = nil
    }
  }
}

fileprivate extension PropertyMetadata.Kind {
  init?(argument: ArgumentDefinition) {
    switch argument.kind {
    case .named:
      switch argument.update {
      case .nullary:
        self = .flag
      case .unary:
        self = .option
      }
    case .positional:
      self = .positional
    case .default:
      return nil
    }
  }
}

fileprivate extension PropertyMetadata.NameInfo {
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

private protocol _OptionGroupProtocol {
  static var _valueType: ParsableArguments.Type { get }
}
extension OptionGroup: _OptionGroupProtocol {
  static var _valueType: ParsableArguments.Type { Value.self }
}

private func _parse(_ type: ParsableArguments.Type, key: String = "")
-> [PropertyMetadata]
{
  Mirror(reflecting: type.init())
    .children
    .flatMap { child -> [PropertyMetadata] in
      guard
        let childLabel = child.label
      else { return [] }

      // Property wrappers have underscore-prefixed names
      let codingKey = String(childLabel.dropFirst(
        childLabel.first == "_" ? 1 : 0))

      let nextKey = key + ".\(codingKey)"
      let childType = Swift.type(of: child.value)

      switch childType {
      case let optionGroupType as _OptionGroupProtocol.Type:
        return _parse(optionGroupType._valueType, key: nextKey)

      case is ArgumentSetProvider.Type:

        guard
          let parsed = child.value as? ArgumentSetProvider
        else { return [] }

        let key = InputKey(rawValue: codingKey)
        let argumentSet = parsed.argumentSet(for: key)
        let metadata = PropertyMetadata(
          argumentSet, key: key, id: nextKey,
          type: childType)
        return metadata.map { [$0] } ?? []

      default:
        return []
      }
    }
}

public struct CommandInfo {
  public init(
    superCommands: [String]? = nil,
    commandName: String,
    abstract: String? = nil,
    discussion: String? = nil,
    subcommands: [CommandInfo]? = nil,
    arguments: [PropertyMetadata]? = nil)
  {
    self.superCommands = superCommands
    self.commandName = commandName
    self.abstract = abstract
    self.discussion = discussion
    self.subcommands = subcommands
    self.arguments = arguments
  }

  /// Super commands and tools.
  public var superCommands: [String]?
  /// Name used to invoke the command.
  public var commandName: String
  /// Short description of the command's functionality.
  public var abstract: String?
  /// Extended description of the command's functionality.
  public var discussion: String?
  /// List of nested commands.
  public var subcommands: [CommandInfo]?
  /// List of supported arguments.
  public var arguments: [PropertyMetadata]?

  public init(commandStack: [ParsableCommand.Type]) {
    guard let command = commandStack.last else {
      preconditionFailure("commandStack must not be empty")
    }

    let parents = commandStack.dropLast()
    var superCommands = parents.map { $0._commandName }
    if let superName = parents.first?.configuration._superCommandName {
      superCommands.insert(superName, at: 0)
    }

    let subcommands = command.configuration.subcommands
      .map { subcommand -> CommandInfo in
        var commandStack = commandStack
        commandStack.append(subcommand)
        return CommandInfo(commandStack: commandStack)
      }

    self = CommandInfo(
      superCommands: superCommands,
      commandName: command._commandName,
      abstract: command.configuration.abstract.nonEmpty,
      discussion: command.configuration.discussion.nonEmpty,
      subcommands: subcommands,
      arguments: _parse(command))
  }
}

extension ParsableCommand {
//  public static var metadata: [PropertyMetadata] { _parse(self) }
//
//  public static var info: CommandInfo {
//    CommandInfo(
//      commandName: _commandName,
//      abstract: configuration.abstract.nonEmpty,
//      discussion: configuration.discussion.nonEmpty,
//      subcommands: configuration.subcommands.map { $0.info },
//      arguments: _parse(self))
//  }
}

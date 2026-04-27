//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Argument Parser open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.0)
internal import ArgumentParserToolInfo
#else
import ArgumentParserToolInfo
#endif

internal struct DumpHelpGenerator {
  private var toolInfo: ToolInfoV0

  init(_ type: ParsableArguments.Type) {
    self.init(commandStack: [type.asCommand])
  }

  init(commandStack: [ParsableCommand.Type]) {
    self.toolInfo = ToolInfoV0(commandStack: commandStack)
  }

  func rendered() -> String {
    JSONEncoder.encode(self.toolInfo)
  }
}

internal struct DumpHelpGeneratorV1 {
  private var toolInfo: ToolInfoV1

  init(_ type: ParsableArguments.Type) {
    self.init(commandStack: [type.asCommand])
  }

  init(commandStack: [ParsableCommand.Type]) {
    self.toolInfo = ToolInfoV1(commandStack: commandStack)
  }

  func rendered() -> String {
    JSONEncoder.encode(self.toolInfo)
  }
}

extension BidirectionalCollection where Element == ParsableCommand.Type {
  /// Returns the ArgumentSet for the last command in this stack, including
  /// help and version flags, when appropriate.
  fileprivate func allArguments() -> ArgumentSet {
    guard
      var arguments = self.last.map({
        ArgumentSet($0, visibility: .private, parent: nil)
      })
    else { return ArgumentSet() }
    self.versionArgumentDefinition().map { arguments.append($0) }
    self.helpArgumentDefinition().map { arguments.append($0) }
    return arguments
  }
}

extension ToolInfoV0 {
  init(commandStack: [ParsableCommand.Type]) {
    self.init(command: CommandInfoV0(commandStack: commandStack))
    // FIXME: This is a hack to inject the help command into the tool info
    // instead we should try to lift this into the parseable command tree
    self.command.subcommands =
      (self.command.subcommands ?? []) + [
        CommandInfoV0(commandStack: commandStack + [HelpCommand.self])
      ]
  }
}

extension CommandInfoV0 {
  fileprivate init(commandStack: [ParsableCommand.Type]) {
    guard let command = commandStack.last else {
      preconditionFailure("commandStack must not be empty")
    }

    let parents = commandStack.dropLast()
    var superCommands = parents.map { $0._commandName }
    if let superName = parents.first?.configuration._superCommandName {
      superCommands.insert(superName, at: 0)
    }

    let defaultSubcommand = command.configuration.defaultSubcommand?
      .configuration.commandName
    let subcommands = command.configuration.subcommands
      .map { subcommand -> CommandInfoV0 in
        var commandStack = commandStack
        commandStack.append(subcommand)
        return CommandInfoV0(commandStack: commandStack)
      }
    let arguments =
      commandStack
      .allArguments()
      .compactMap(ArgumentInfoV0.init)

    self = CommandInfoV0(
      superCommands: superCommands,
      shouldDisplay: command.configuration.shouldDisplay,
      commandName: command._commandName,
      aliases: command.configuration.aliases,
      abstract: command.configuration.abstract,
      discussion: command.configuration.discussion,
      defaultSubcommand: defaultSubcommand,
      subcommands: subcommands,
      arguments: arguments)
  }
}

extension ArgumentInfoV0 {
  fileprivate init?(argument: ArgumentDefinition) {
    guard let kind = ArgumentInfoV0.KindV0(argument: argument) else {
      return nil
    }

    let discussion: String?
    let allValueDescriptions: [String: String]?
    switch argument.help.discussion {
    case .none:
      discussion = nil
      allValueDescriptions = nil
    case .staticText(let _discussion):
      discussion = _discussion
      allValueDescriptions = nil
    case .enumerated(let _discussion, let options):
      discussion = _discussion
      allValueDescriptions = options.allValueDescriptions
    }

    self.init(
      kind: kind,
      shouldDisplay: argument.help.visibility.base == .default,
      sectionTitle: argument.help.parentTitle.nonEmpty,
      isOptional: argument.help.options.contains(.isOptional),
      isRepeating: argument.help.options.contains(.isRepeating),
      parsingStrategy: ArgumentInfoV0.ParsingStrategyV0(argument: argument),
      names: argument.names.map(ArgumentInfoV0.NameInfoV0.init),
      preferredName: argument.names.preferredName.map(
        ArgumentInfoV0.NameInfoV0.init),
      valueName: argument.valueName,
      defaultValue: argument.help.defaultValue,
      allValueStrings: argument.help.allValueStrings,
      allValueDescriptions: allValueDescriptions,
      completionKind: ArgumentInfoV0.CompletionKindV0(
        completion: argument.completion),
      abstract: argument.help.abstract,
      discussion: discussion)
  }
}

extension ArgumentInfoV0.KindV0 {
  fileprivate init?(argument: ArgumentDefinition) {
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

extension ArgumentInfoV0.ParsingStrategyV0 {
  fileprivate init(argument: ArgumentDefinition) {
    switch argument.parsingStrategy {
    case .`default`:
      self = .default
    case .scanningForValue:
      self = .scanningForValue
    case .unconditional:
      self = .unconditional
    case .upToNextOption:
      self = .upToNextOption
    case .allRemainingInput:
      self = .allRemainingInput
    case .postTerminator:
      self = .postTerminator
    case .allUnrecognized:
      self = .allUnrecognized
    }
  }
}

extension ArgumentInfoV0.NameInfoV0 {
  fileprivate init(name: Name) {
    switch name {
    case .long(let n):
      self.init(kind: .long, name: n)
    case .short(let n, _):
      self.init(kind: .short, name: String(n))
    case .longWithSingleDash(let n):
      self.init(kind: .longWithSingleDash, name: n)
    }
  }
}

extension ArgumentInfoV0.CompletionKindV0 {
  fileprivate init?(completion: CompletionKind) {
    switch completion.kind {
    case .`default`:
      return nil
    case .list(let values):
      self = .list(values: values)
    case .file(let extensions):
      self = .file(extensions: extensions)
    case .directory:
      self = .directory
    case .shellCommand(let command):
      self = .shellCommand(command: command)
    case .custom(_):
      self = .custom
    case .customAsync(_):
      self = .customAsync
    case .customDeprecated(_):
      self = .customDeprecated
    }
  }
}

// MARK: - V1 generation

extension ToolInfoV1 {
  internal init(commandStack: [ParsableCommand.Type]) {
    self.init(command: CommandInfoV1(commandStack: commandStack))
    // Mirror V0's HelpCommand injection so V1 reflects the same observable
    // command tree.
    // FIXME: lift HelpCommand injection into the parsable command tree
    // (tracked alongside the V0 FIXME at the top of CommandInfoV0.init).
    var existing = self.command.subcommands ?? []
    existing.append(
      CommandInfoV1(commandStack: commandStack + [HelpCommand.self]))
    self.command.subcommands = existing
  }
}

extension CommandInfoV1 {
  fileprivate init(commandStack: [ParsableCommand.Type]) {
    guard let command = commandStack.last else {
      preconditionFailure("commandStack must not be empty")
    }

    let parents = commandStack.dropLast()
    var superCommands = parents.map { $0._commandName }
    if let superName = parents.first?.configuration._superCommandName {
      superCommands.insert(superName, at: 0)
    }

    let defaultSubcommand = command.configuration.defaultSubcommand?
      .configuration.commandName
    let subcommands = command.configuration.subcommands
      .map { subcommand -> CommandInfoV1 in
        var commandStack = commandStack
        commandStack.append(subcommand)
        return CommandInfoV1(commandStack: commandStack)
      }

    let children = CommandChildV1.children(
      forArguments: commandStack.allArguments())

    self.init(
      superCommands: superCommands.isEmpty ? nil : superCommands,
      shouldDisplay: command.configuration.shouldDisplay,
      commandName: command._commandName,
      aliases: command.configuration.aliases.isEmpty
        ? nil : command.configuration.aliases,
      abstract: command.configuration.abstract.isEmpty
        ? nil : command.configuration.abstract,
      discussion: command.configuration.discussion.isEmpty
        ? nil : command.configuration.discussion,
      defaultSubcommand: defaultSubcommand,
      subcommands: subcommands.isEmpty ? nil : subcommands,
      children: children)
  }
}

extension CommandChildV1 {
  /// Walks an `ArgumentSet` in declaration order and groups consecutive
  /// arguments that share a `parentTitle` into `.group(...)` children. The
  /// resulting list preserves source order across interleaved arguments and
  /// option groups.
  fileprivate static func children(
    forArguments arguments: ArgumentSet
  ) -> [CommandChildV1]? {
    var output: [CommandChildV1] = []
    var currentTitle: String? = nil
    var currentGroupArgs: [CommandChildV1] = []

    func flushGroup() {
      guard let title = currentTitle, !currentGroupArgs.isEmpty else { return }
      output.append(
        .group(
          ArgumentGroupInfoV1(title: title, children: currentGroupArgs)))
      currentTitle = nil
      currentGroupArgs = []
    }

    for definition in arguments {
      guard let info = ArgumentInfoV1(argument: definition) else { continue }
      let title = definition.help.parentTitle.isEmpty
        ? nil : definition.help.parentTitle
      if title == currentTitle {
        if title == nil {
          output.append(.argument(info))
        } else {
          currentGroupArgs.append(.argument(info))
        }
      } else {
        flushGroup()
        currentTitle = title
        if title == nil {
          output.append(.argument(info))
        } else {
          currentGroupArgs = [.argument(info)]
        }
      }
    }
    flushGroup()
    return output.isEmpty ? nil : output
  }
}

extension ArgumentInfoV1 {
  fileprivate init?(argument: ArgumentDefinition) {
    guard let kind = ArgumentInfoV1.Kind(argument: argument) else {
      return nil
    }

    let discussion: String?
    let allValueDescriptions: [String: String]?
    switch argument.help.discussion {
    case .none:
      discussion = nil
      allValueDescriptions = nil
    case .staticText(let text):
      discussion = text
      allValueDescriptions = nil
    case .enumerated(let text, let options):
      discussion = text
      allValueDescriptions = options.allValueDescriptions
    }

    let parentTitle = argument.help.parentTitle
    self.init(
      kind: kind,
      shouldDisplay: argument.help.visibility.base == .default,
      sectionTitle: parentTitle.isEmpty ? nil : parentTitle,
      isOptional: argument.help.options.contains(.isOptional),
      isRepeating: argument.help.options.contains(.isRepeating),
      parsingStrategy: ArgumentInfoV1.ParsingStrategy(argument: argument),
      names: argument.names.isEmpty
        ? nil : argument.names.map(ArgumentInfoV1.NameInfo.init),
      preferredName: argument.names.preferredName.map(
        ArgumentInfoV1.NameInfo.init),
      valueName: argument.valueName.isEmpty ? nil : argument.valueName,
      defaultValue: argument.help.defaultValue,
      allValueStrings: argument.help.allValueStrings.isEmpty
        ? nil : argument.help.allValueStrings,
      allValueDescriptions: allValueDescriptions,
      completionKind: ArgumentInfoV1.CompletionKind(
        completion: argument.completion),
      abstract: argument.help.abstract.isEmpty
        ? nil : argument.help.abstract,
      discussion: discussion)
  }
}

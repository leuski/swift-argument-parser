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

/// All information about a particular command, including arguments, option
/// groups, and subcommands.
///
/// Compared to `CommandInfoV0`, this struct replaces the flat `arguments`
/// list with a `children` tree of `CommandChildV1` cases that preserves the
/// source-declaration order of arguments and option groups.
public struct CommandInfoV1: Codable, Hashable, Sendable {
  /// Super commands and tools.
  public var superCommands: [String]?
  /// Command should appear in help displays.
  public var shouldDisplay: Bool
  /// Name used to invoke the command.
  public var commandName: String
  /// List of command aliases.
  public var aliases: [String]?
  /// Short description of the command's functionality.
  public var abstract: String?
  /// Extended description of the command's functionality.
  public var discussion: String?
  /// Optional name of the subcommand invoked when the command is invoked
  /// with no arguments.
  public var defaultSubcommand: String?
  /// List of nested commands.
  public var subcommands: [CommandInfoV1]?
  /// Ordered arguments and groups, in source-declaration order.
  public var children: [CommandChildV1]?

  public init(
    superCommands: [String]?,
    shouldDisplay: Bool,
    commandName: String,
    aliases: [String]?,
    abstract: String?,
    discussion: String?,
    defaultSubcommand: String?,
    subcommands: [CommandInfoV1]?,
    children: [CommandChildV1]?
  ) {
    self.superCommands = superCommands
    self.shouldDisplay = shouldDisplay
    self.commandName = commandName
    self.aliases = aliases
    self.abstract = abstract
    self.discussion = discussion
    self.defaultSubcommand = defaultSubcommand
    self.subcommands = subcommands
    self.children = children
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.superCommands = try container.decodeIfPresent(
      [String].self, forKey: .superCommands)
    self.shouldDisplay =
      try container.decodeIfPresent(Bool.self, forKey: .shouldDisplay) ?? true
    self.commandName = try container.decode(
      String.self, forKey: .commandName)
    self.aliases = try container.decodeIfPresent(
      [String].self, forKey: .aliases)
    self.abstract = try container.decodeIfPresent(
      String.self, forKey: .abstract)
    self.discussion = try container.decodeIfPresent(
      String.self, forKey: .discussion)
    self.defaultSubcommand = try container.decodeIfPresent(
      String.self, forKey: .defaultSubcommand)
    self.subcommands = try container.decodeIfPresent(
      [CommandInfoV1].self, forKey: .subcommands)
    self.children = try container.decodeIfPresent(
      [CommandChildV1].self, forKey: .children)
  }
}

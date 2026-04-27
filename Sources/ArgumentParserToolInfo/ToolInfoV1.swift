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

/// Top-level structure containing serialization version and information for
/// all commands in a tool — V1 schema.
///
/// V1 differs from V0 in that argument metadata is represented as an ordered
/// tree (`CommandChildV1`) preserving source-declaration order, instead of a
/// flat list. The two schemas live side-by-side; consumers select via
/// `ToolInfoHeader.serializationVersion`.
public struct ToolInfoV1: Codable, Hashable, Sendable {
  /// A sentinel value indicating the version of the ToolInfo struct used to
  /// generate the serialized form.
  public var serializationVersion = 1
  /// Root command of the tool.
  public var command: CommandInfoV1

  public init(command: CommandInfoV1) {
    self.command = command
  }
}

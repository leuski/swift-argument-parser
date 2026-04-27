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

/// Metadata for an `@OptionGroup` declared inside a command.
///
/// Groups recurse via `children`, which is a heterogeneous list of arguments
/// and nested groups. The recursion mirrors the schema's main tree: every
/// level of the command's argument structure is described with the same enum
/// shape.
public struct ArgumentGroupInfoV1: Codable, Hashable, Sendable {
  /// Title shown for the group in help displays.
  public var title: String

  /// Ordered children of the group, in source-declaration order.
  public var children: [CommandChildV1]?

  public init(title: String, children: [CommandChildV1]?) {
    self.title = title
    self.children = children
  }
}

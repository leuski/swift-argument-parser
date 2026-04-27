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

/// One ordered child of a command (or of a nested option group): either an
/// argument or a (possibly nested) option group.
///
/// V1 represents arguments and groups in the order they were declared so that
/// consumers — in particular UI generators — can reproduce the source
/// ordering instead of post-hoc reconstruction from a flat list.
public enum CommandChildV1: Hashable, Sendable {
  case argument(ArgumentInfoV1)
  case group(ArgumentGroupInfoV1)
}

extension CommandChildV1: Codable {
  /// Wire format uses Swift's default associated-value encoding, with the
  /// case name as a single wrapping key, e.g.
  ///
  ///     {"argument": {"kind": "option", "valueName": "input", ...}}
  ///     {"group":    {"title": "Options", "children": [...]}}
  ///
  /// A flatter "tagged-union" shape with a top-level discriminator was
  /// considered but collides with `ArgumentInfoV1.kind`'s payload field. If
  /// proposal review prefers a different key (e.g., `nodeKind`), the change
  /// is mechanical.
  // TODO(wire-format): bikeshed wrapper vs tagged-union with non-colliding
  // discriminator in proposal review.
  private enum CodingKeys: String, CodingKey {
    case argument
    case group
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let info = try container.decodeIfPresent(
      ArgumentInfoV1.self, forKey: .argument)
    {
      self = .argument(info)
      return
    }
    if let info = try container.decodeIfPresent(
      ArgumentGroupInfoV1.self, forKey: .group)
    {
      self = .group(info)
      return
    }
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: container.codingPath,
        debugDescription:
          "CommandChildV1 must contain exactly one of `argument` or `group`."))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .argument(let info):
      try container.encode(info, forKey: .argument)
    case .group(let info):
      try container.encode(info, forKey: .group)
    }
  }
}

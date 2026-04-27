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

/// All information about a particular argument, including display names and
/// options.
///
/// `ArgumentInfoV1` mirrors `ArgumentInfoV0` field-for-field, with a single
/// schema-level deviation: `allValueDescriptions` is no longer fused into
/// `discussion`. Consumers that want to render enumerated values separately
/// from the discussion text can do so without parsing the discussion blob.
public struct ArgumentInfoV1: Codable, Hashable, Sendable {
  /// Kind of prefix of an argument's name.
  public typealias NameInfo = ArgumentInfoV0.NameInfoV0

  /// Kind of argument.
  public typealias Kind = ArgumentInfoV0.KindV0

  /// Strategy used when parsing the argument from the command line.
  public typealias ParsingStrategy = ArgumentInfoV0.ParsingStrategyV0

  /// The kind of completion to use for an argument or option value.
  public typealias CompletionKind = ArgumentInfoV0.CompletionKindV0

  /// Kind of argument the ArgumentInfo describes.
  public var kind: Kind

  /// Argument should appear in help displays.
  public var shouldDisplay: Bool
  /// Custom name of argument's section.
  public var sectionTitle: String?

  /// Argument can be omitted.
  public var isOptional: Bool
  /// Argument can be specified multiple times.
  public var isRepeating: Bool

  /// Parsing strategy of the ArgumentInfo.
  public var parsingStrategy: ParsingStrategy

  /// All names of the argument.
  public var names: [NameInfo]?
  /// The best name to use when referring to the argument in help displays.
  public var preferredName: NameInfo?

  /// Name of argument's value.
  public var valueName: String?
  /// Default value of the argument is none is specified on the command line.
  public var defaultValue: String?
  /// List of all valid value strings.
  public var allValueStrings: [String]?
  /// Mapping of valid values to descriptions of the value.
  ///
  /// Unlike V0, this field is independent of `discussion` — the V1 emitter
  /// never folds enumerated values into the discussion text.
  public var allValueDescriptions: [String: String]?

  /// The type of completion to use for an argument or an option value.
  ///
  /// `nil` if the tool uses the default completion kind.
  public var completionKind: CompletionKind?

  /// Short description of the argument's functionality.
  public var abstract: String?
  /// Extended description of the argument's functionality.
  public var discussion: String?

  public init(
    kind: Kind,
    shouldDisplay: Bool,
    sectionTitle: String?,
    isOptional: Bool,
    isRepeating: Bool,
    parsingStrategy: ParsingStrategy,
    names: [NameInfo]?,
    preferredName: NameInfo?,
    valueName: String?,
    defaultValue: String?,
    allValueStrings: [String]?,
    allValueDescriptions: [String: String]?,
    completionKind: CompletionKind?,
    abstract: String?,
    discussion: String?
  ) {
    self.kind = kind
    self.shouldDisplay = shouldDisplay
    self.sectionTitle = sectionTitle
    self.isOptional = isOptional
    self.isRepeating = isRepeating
    self.parsingStrategy = parsingStrategy
    self.names = names
    self.preferredName = preferredName
    self.valueName = valueName
    self.defaultValue = defaultValue
    self.allValueStrings = allValueStrings
    self.allValueDescriptions = allValueDescriptions
    self.completionKind = completionKind
    self.abstract = abstract
    self.discussion = discussion
  }
}

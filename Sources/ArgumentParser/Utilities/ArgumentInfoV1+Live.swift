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

#if compiler(>=6.0)
internal import ArgumentParserToolInfo
#else
import ArgumentParserToolInfo
#endif

/// Adapters that build `ArgumentInfoV1` and friends from the parser's
/// internal `ArgumentDefinition` representation.
///
/// The dump-help generator (`DumpHelpGeneratorV1`) and the typed visitor
/// (`PropertyMetadata.swift`) both need to convert an `ArgumentDefinition`
/// into an `ArgumentInfoV1`. Centralizing the conversion here keeps the two
/// call sites in lockstep and avoids drift.
extension ArgumentInfoV1 {
  internal init?(argument: ArgumentDefinition) {
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

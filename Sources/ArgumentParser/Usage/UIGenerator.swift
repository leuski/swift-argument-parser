//
//  UIGenerator.swift
//  ArgumentParser
//
//  Created by Anton Leuski on 11/4/20.
//

public struct PropertyMetadata: Identifiable {
  public struct Content {
    public enum Kind {
      case long(String)
      case short(Character)
      case longWithSingleDash(String)
      case positional
    }

    public let help: ArgumentHelp?
    public let kind: Kind
    public let valueName: String

    fileprivate init(_ arg: ArgumentDefinition) {
      let kind: Kind
      switch arg.kind {
      case .positional: kind = .positional
      case .named(let names):
        switch names.first {
        case .none: fatalError()
        case .long(let value): kind = .long(value)
        case .short(let value): kind = .short(value)
        case .longWithSingleDash(let value): kind = .longWithSingleDash(value)
        }
      }

      self.help = arg.help.help
      self.kind = kind
      self.valueName = arg.valueName
    }

    fileprivate init() {
      self.valueName = "a string"
      self.kind = .long("a-string")
      self.help = ArgumentHelp(
        "sample abstract",
        discussion: "sample discussion",
        valueName: "help value name",
        shouldDisplay: true)
    }
  }

  public let id: String
  public let initialValue: Any?
  public let values: [Content]
  public let type: Any.Type

  init?(
    _ arg: ArgumentSet, key: InputKey, id: String, type: Any.Type) {
    self.type = type
    self.id = id
    self.values = arg.map { Content($0) }
    guard !values.isEmpty else { return nil }

    if let arg1 = Array(arg).first {
      do {
        var values = ParsedValues(originalInput: [])
        try arg1.initial(InputOrigin(), &values)
        self.initialValue = values.elements[key]?.value
      } catch {
        self.initialValue = nil
      }
    } else {
      self.initialValue = nil
    }
  }

  // for testing purposes
  public init() {
    self.id = "Hello"
    self.initialValue = "Hello World"
    self.type = String.self
    self.values = [ Content() ]
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

extension ParsableCommand {
  public static var metadata: [PropertyMetadata] { _parse(self) }
}

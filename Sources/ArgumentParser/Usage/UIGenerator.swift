//
//  UIGenerator.swift
//  ArgumentParser
//
//  Created by Anton Leuski on 11/4/20.
//

protocol OptionGroupProtocol {
  static var _valueType: ParsableArguments.Type { get }
}
extension OptionGroup: OptionGroupProtocol {
  static var _valueType: ParsableArguments.Type { Value.self }
}
protocol ArgumentProtocol {
  static var _valueType: Any.Type { get }
}
extension Argument: ArgumentProtocol {
  static var _valueType: Any.Type { Value.self }
}
protocol FlagProtocol {
  static var _valueType: Any.Type { get }
}
extension Flag: FlagProtocol {
  static var _valueType: Any.Type { Value.self }
}
protocol OptionProtocol {
  static var _valueType: Any.Type { get }
}
extension Option: OptionProtocol {
  static var _valueType: Any.Type { Value.self }
}

public struct UIMetadata {
  public enum Kind {
    case long(String)
    case short(Character)
    case longWithSingleDash(String)
    case positional
  }

  public enum ArgumentKind {
    case flag(Any.Type)
    case argument(Any.Type)
    case option(Any.Type)
  }

  public let help: ArgumentHelp?
  public let key: String
  public let defaultValue: String?
  public let kind: Kind
  public let argumentKind: ArgumentKind
  public let valueName: String

  public var abstract: String? {
    (help?.abstract).flatMap { $0.isEmpty ? nil : $0} }
  public var discussion: String? {
    (help?.discussion).flatMap { $0.isEmpty ? nil : $0} }
}

private func _parse(_ type: ParsableArguments.Type)
  -> [(String, UIMetadata.ArgumentKind)]
{
  Mirror(reflecting: type.init())
    .children
    .flatMap { child -> [(String, UIMetadata.ArgumentKind)] in
      guard
        var codingKey = child.label,
        let parsed = child.value as? ArgumentSetProvider
      else { return [] }

      // Property wrappers have underscore-prefixed names
      codingKey = String(codingKey.dropFirst(codingKey.first == "_" ? 1 : 0))

      switch Swift.type(of: parsed) {
      case let type as OptionGroupProtocol.Type:
        return _parse(type._valueType)

      case let type as ArgumentProtocol.Type:
        return [(codingKey, .argument(type._valueType))]

      case let type as FlagProtocol.Type:
        return [(codingKey, .flag(type._valueType))]

      case let type as OptionProtocol.Type:
        return [(codingKey, .option(type._valueType))]

      default:
        return []
      }
    }
}

struct UIGenerator {

  let metadata: [UIMetadata]

  init(commandStack: [ParsableCommand.Type]) {
    guard let command = commandStack.last else { fatalError() }

    let types = Dictionary(_parse(command), uniquingKeysWith: {_, new in new })

    metadata = commandStack.flatMap {
      Array(ArgumentSet($0)).compactMap {
        arg in
        guard arg.help.help?.shouldDisplay != false else { return nil }

        let kind: UIMetadata.Kind
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

        guard let key = arg.help.keys.map({ $0.rawValue })
                .first(where: {nil != types[$0]}),
              let argumentKind = types[key]
        else { return nil }

        return UIMetadata(
          help: arg.help.help,
          key: key,
          defaultValue: arg.help.defaultValue,
          kind: kind,
          argumentKind: argumentKind,
          valueName: arg.valueName)
      }
    }
  }
}

extension ParsableCommand {
  public static func ui(for subcommand: ParsableCommand.Type)
  -> [UIMetadata]
  {
    let stack = CommandParser(self).commandStack(for: subcommand)
    return UIGenerator(commandStack: stack).metadata
  }
}

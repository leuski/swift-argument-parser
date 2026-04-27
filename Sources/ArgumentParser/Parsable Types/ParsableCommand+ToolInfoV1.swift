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
public import ArgumentParserToolInfo
#else
import ArgumentParserToolInfo
#endif

// TODO(naming): bikeshed `toolInfoV1` vs alternatives in proposal review.
extension ParsableCommand {
  /// A V1 description of this command and its subcommands.
  ///
  /// Equivalent to running `--experimental-dump-help-v1` on the command,
  /// once that flag lands. Useful for tooling that wants to introspect a
  /// command tree without spawning a subprocess.
  public static var toolInfoV1: ToolInfoV1 {
    ToolInfoV1(commandStack: [Self.asCommand])
  }
}

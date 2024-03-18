// Copyright 2023 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import StringifyMacroPlugin
import Stringify2MacroPlugin
import XCTest

class StringifyMacroTests: XCTestCase {
  func testStringify() {
    let sourceFile: SourceFileSyntax = #"""
      _ = #stringify(1 + 2)
      """#
    let context = BasicMacroExpansionContext(
      sourceFiles: [sourceFile: .init(moduleName: "TestModule", fullFilePath: "Test.swift")]
    )
    let transformedSourceFile =
      sourceFile.expand(macros: ["stringify": StringifyMacro.self], in: context)
    XCTAssertEqual(
      String(describing: transformedSourceFile),
      #"""
      _ = (1 + 2, "1 + 2")
      """#
    )
  }

  func testStringify2() {
    let sourceFile: SourceFileSyntax = #"""
      _ = #stringify2(2 + 1)
      """#
    let context = BasicMacroExpansionContext(
      sourceFiles: [sourceFile: .init(moduleName: "TestModule", fullFilePath: "Test.swift")]
    )
    let transformedSourceFile =
      sourceFile.expand(macros: ["stringify2": Stringify2Macro.self], in: context)
    XCTAssertEqual(
      String(describing: transformedSourceFile),
      #"""
      _ = (2 + 1, "2 + 1")
      """#
    )
  }
}

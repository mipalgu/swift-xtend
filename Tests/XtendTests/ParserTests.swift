//
//  ParserTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import Xtend

/// Tests of the lexer, parser, outline and highlighting tokens.
@Suite("Parsing")
struct ParserTests {
    /// A class with a field and methods parses without diagnostics and has an outline.
    @Test("Class with members")
    func classWithMembers() throws {
        let source = """
            package demo

            import java.util.List

            class Greeter extends Base implements Runnable {
                val greeting = 'Hello'
                extension Helper helper
                def greet(String name) {
                    greeting + ', ' + name
                }
                def dispatch describe(String s) '''text «s»'''
                def create new Base() make(int n) {}
                new() {}
                def abstract List<String> names()
            }
            """
        let result = XtendParser.parse(source, document: "Greeter.xtend")
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.file.packageName == "demo")
        #expect(result.file.imports.map(\.name) == ["java.util.List"])
        let declaration = try #require(result.file.classes.first)
        #expect(declaration.qualifiedName == "demo.Greeter")
        #expect(declaration.superclass?.name == "Base")
        #expect(declaration.interfaces.map(\.name) == ["Runnable"])
        #expect(declaration.fields.map(\.name) == ["greeting", "helper"])
        #expect(declaration.fields.map(\.modifiers.isExtension) == [false, true])
        #expect(declaration.methods.map(\.name) == ["greet", "describe", "make", "new", "names"])
        #expect(declaration.methods.last?.returnType?.description == "List<String>")
        let outline = try #require(result.outline.first)
        #expect(outline.name == "Greeter")
        #expect(outline.detail == "Base")
        #expect(outline.children.map(\.kind) == ["field", "field", "method", "dispatchMethod", "createMethod", "constructor", "method"])
        #expect(outline.children[2].detail == "(String)")
        #expect(outline.children[2].selectionRange.start.line == 8)
    }

    /// Highlighting tokens classify keywords, names, literals, template keywords and comments.
    @Test("Highlighting tokens")
    func highlighting() {
        let source = """
            // note
            class A { def f() '''«FOR x : #[1] SEPARATOR ','»«x»«ENDFOR» «true»''' }
            """
        let result = XtendParser.parse(source, document: "A.xtend")
        #expect(result.diagnostics.isEmpty)
        let kinds = result.tokens.map(\.kind)
        #expect(kinds.first == .comment)
        #expect(kinds.contains(.keyword))
        #expect(kinds.contains(.typeName))
        #expect(kinds.contains(.number))
        #expect(kinds.contains(.boolean))
        #expect(kinds.contains(.string))
        #expect(kinds.filter { $0 == .keyword }.count == 5)
        let offsets = result.tokens.map(\.range.start.utf8Offset)
        #expect(offsets == offsets.sorted())
    }

    /// Parsing recovers at member boundaries and reports lexical problems.
    @Test("Error recovery")
    func recovery() {
        let source = """
            class A {
              def broken( { 1 }
              def fine() { 2 }
              def text() { "unterminated }
            }
            """
        let result = XtendParser.parse(source, document: "A.xtend")
        #expect(result.hasErrors)
        #expect(result.file.classes.first?.methods.map(\.name).contains("fine") == true)
        #expect(result.diagnostics.contains { $0.code == XtendDiagnosticCode.unterminatedString.rawValue })
        let richString = XtendParser.parse("class B { def f() '''never closed }", document: "B.xtend")
        #expect(richString.diagnostics.contains { $0.code == XtendDiagnosticCode.unterminatedRichString.rawValue })
        let character = XtendParser.parse("class C { def f() { 1 ~ 2 } }", document: "C.xtend")
        #expect(character.diagnostics.contains { $0.code == XtendDiagnosticCode.invalidCharacter.rawValue })
        let comment = XtendParser.parse("class D {} /* open", document: "D.xtend")
        #expect(comment.diagnostics.contains { $0.code == XtendDiagnosticCode.unterminatedComment.rawValue })
    }

    /// Literals of every form are read with their values.
    @Test(
        "Literals",
        arguments: [
            ("0x1F", "31"), ("1_000", "1000"), ("12L", "12"), ("1.5e2", "150.0"), ("2.5d", "2.5"), ("'a\\tb'.length", "3"),
            ("\"q\\u0041\"", "qA"), ("'''x'''", "x"), ("^class", "null"),
        ])
    func literals(expression: String, expected: String) async throws {
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []))
        #expect(try await interpreter.evaluate(expression, variables: ["class": .null]).description == expected)
    }

    /// Standalone expressions with syntax errors are rejected.
    @Test("Invalid standalone expressions")
    func invalidExpressions() async throws {
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []))
        for text in ["1 +", "val = 3", "new java.io.File('x')"] {
            await #expect(throws: XtendError.self) { _ = try await interpreter.evaluate(text) }
        }
        let (expression, diagnostics) = XtendParser.parseExpression("a.b(c)[d | d]", document: "x")
        #expect(expression != nil)
        #expect(diagnostics.isEmpty)
    }
}

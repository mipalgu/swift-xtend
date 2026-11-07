//
//  RichStringTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import Xtend

/// Tests of rich strings and their whitespace rules, with exact expected output.
@Suite("Rich strings")
struct RichStringTests {
    /// The first example of the Xtend documentation: indentation relative to the opening
    /// delimiter is not part of the output, and the line of the closing delimiter is dropped.
    @Test("Documentation example: a single node")
    func documentationSingleNode() async throws {
        let source = """
            class Template {
              def print(String name) '''
                node «name» {}
              '''
            }
            """
        let result = try await XtendTestSupport.call(source, "print", of: "Template", arguments: [.string("NodeName")])
        #expect(result.stringValue == "node NodeName {}\n")
    }

    /// The second example of the Xtend documentation, written with a loop: indentation
    /// relative to control structures is dropped, lines with only control structures vanish,
    /// and indentation propagates into the text of nested template calls.
    @Test("Documentation example: nested nodes")
    func documentationNestedNodes() async throws {
        let source = """
            import java.util.List

            class Node {
              public val String name
              public val List<Node> children
              new(String name, List<Node> children) {
                this.name = name
                this.children = children
              }
            }

            class Template {
              def print(Node n) '''
                node «n.name» {
                  «IF !n.children.empty»
                    «FOR c : n.children»
                      «print(c)»
                    «ENDFOR»
                  «ENDIF»
                }
              '''

              def tree() {
                print(new Node('Parent', #[
                  new Node('FirstChild', #[]),
                  new Node('SecondChild', #[new Node('Leaf', #[])])
                ]))
              }
            }
            """
        let result = try await XtendTestSupport.call(source, "tree", of: "Template")
        #expect(
            result.stringValue == """
                node Parent {
                  node FirstChild {
                  }
                  node SecondChild {
                    node Leaf {
                    }
                  }
                }

                """)
    }

    /// `BEFORE`, `SEPARATOR` and `AFTER` surround the iterations of an inline loop, and
    /// produce nothing for an empty collection.
    @Test("Inline loop with BEFORE, SEPARATOR and AFTER")
    func inlineLoopClauses() async throws {
        let source = """
            import java.util.List
            class T {
              def list(List<String> items) '''«FOR p : items BEFORE '(' SEPARATOR ', ' AFTER ')'»«p»«ENDFOR»'''
            }
            """
        let some = try await XtendTestSupport.call(source, "list", of: "T", arguments: [.list([.string("a"), .string("b"), .string("c")])])
        #expect(some.stringValue == "(a, b, c)")
        let none = try await XtendTestSupport.call(source, "list", of: "T", arguments: [.list([])])
        #expect(none.stringValue == "")
    }

    /// A separator is placed directly after the last non-whitespace text of the previous
    /// iteration, before its line break.
    @Test("Separator before the line break of a multi-line loop")
    func multiLineSeparator() async throws {
        let source = """
            import java.util.List
            class T {
              def call(List<String> names) '''
                call(
                  «FOR n : names SEPARATOR ','»
                    «n»
                  «ENDFOR»
                )
              '''
            }
            """
        let result = try await XtendTestSupport.call(source, "call", of: "T", arguments: [.list([.string("a"), .string("b")])])
        #expect(result.stringValue == "call(\n  a,\n  b\n)\n")
    }

    /// Conditionals choose a branch; their control lines leave no trace.
    @Test("IF, ELSEIF and ELSE", arguments: [(-3, "negative\n"), (0, "zero\n"), (5, "positive\n")])
    func conditionals(value: Int, expected: String) async throws {
        let source = """
            class T {
              def describe(int n) '''
                «IF n < 0»
                  negative
                «ELSEIF n == 0»
                  zero
                «ELSE»
                  positive
                «ENDIF»
              '''
            }
            """
        let result = try await XtendTestSupport.call(source, "describe", of: "T", arguments: [.int(value)])
        #expect(result.stringValue == expected)
    }

    /// Line breaks inside an inserted value receive the indentation of the line that holds
    /// the interpolation, and the trailing line break of a nested template is not doubled.
    @Test("Indentation of inserted multi-line text")
    func insertedIndentation() async throws {
        let source = """
            class T {
              def outer() '''
                begin
                  «inner»
                end
              '''
              def inner() '''
                line1
                line2
              '''
            }
            """
        let result = try await XtendTestSupport.call(source, "outer", of: "T")
        #expect(result.stringValue == "begin\n  line1\n  line2\nend\n")
    }

    /// Blank lines inside an inserted value keep the indentation, as Xtend's
    /// `StringConcatenation` does.
    @Test("Blank lines of inserted text keep the indentation")
    func insertedBlankLines() async throws {
        let source = """
            class T {
              def outer() '''
                {
                  «inner»
                }
              '''
              def inner() '''
                a

                b
              '''
            }
            """
        let result = try await XtendTestSupport.call(source, "outer", of: "T")
        #expect(result.stringValue == "{\n  a\n  \n  b\n}\n")
    }

    /// A line whose interpolations produce only whitespace disappears, while static text
    /// and blank template lines are kept.
    @Test("Lines with empty interpolations disappear")
    func emptyInterpolations() async throws {
        let source = """
            class T {
              def text() '''
                a
                «empty»
                «nothing»
                x«empty»

                b
              '''
              def empty() { '' }
              def nothing() { null }
            }
            """
        let result = try await XtendTestSupport.call(source, "text", of: "T")
        #expect(result.stringValue == "a\nx\n\nb\n")
    }

    /// A line that holds only a comment vanishes; the comment ends at the line break.
    @Test("Comments in rich strings")
    func comments() async throws {
        let source = """
            class T {
              def text() '''
                a
                ««« this line disappears
                b ««« trailing comment
                c
              '''
            }
            """
        let result = try await XtendTestSupport.call(source, "text", of: "T")
        #expect(result.stringValue == "a\nb \nc\n")
    }

    /// Text on the line of the opening delimiter is kept, and so is the indentation of
    /// later lines, which is not relative to a control structure.
    @Test("Text on the opening line")
    func openingLineText() async throws {
        let source = """
            class T {
              def text() '''first
                second'''
              def last() '''
                only'''
            }
            """
        #expect(try await XtendTestSupport.call(source, "text", of: "T").stringValue == "first\n    second")
        #expect(try await XtendTestSupport.call(source, "last", of: "T").stringValue == "only")
    }

    /// A loop inside a line keeps the surrounding text.
    @Test("Loop inside a line")
    func loopInsideLine() async throws {
        let source = """
            class T {
              def text() '''
                values: «FOR v : #[1, 2, 3] SEPARATOR ' '»«v»«ENDFOR».
              '''
            }
            """
        #expect(try await XtendTestSupport.call(source, "text", of: "T").stringValue == "values: 1 2 3.\n")
    }

    /// Indentation inside a loop body that is deeper than the loop's first body line is kept
    /// relative to it, and loops nest.
    @Test("Nested loops with relative indentation")
    func nestedLoops() async throws {
        let source = """
            class T {
              def table() '''
                rows:
                  «FOR r : 1..2»
                    row «r»
                      «FOR c : #['a', 'b']»
                        cell «r»«c»
                      «ENDFOR»
                  «ENDFOR»
                done
              '''
            }
            """
        let expected = """
            rows:
              row 1
                cell 1a
                cell 1b
              row 2
                cell 2a
                cell 2b
            done

            """
        #expect(try await XtendTestSupport.call(source, "table", of: "T").stringValue == expected)
    }

    /// Values are inserted with Java's textual form, and `null` inserts nothing.
    @Test("Textual form of inserted values")
    func insertedValues() async throws {
        let source = """
            class T {
              def text() '''«1» «2.5» «true» «#[1, 2]» «'k' -> 'v'» «null»|'''
            }
            """
        #expect(try await XtendTestSupport.call(source, "text", of: "T").stringValue == "1 2.5 true [1, 2] k->v |")
    }

    /// Unbalanced control structures are reported with their positions.
    @Test("Unbalanced control structures")
    func unbalanced() {
        let program = XtendProgram(
            """
            class T {
              def a() '''«FOR x : #[1]»«x»'''
              def b() '''«ENDIF»'''
            }
            """)
        let codes = program.errors.map(\.code)
        #expect(codes == [XtendDiagnosticCode.unbalancedTemplate.rawValue, XtendDiagnosticCode.unbalancedTemplate.rawValue])
        #expect(program.errors.first?.range?.start.line == 2)
        #expect(program.errors.last?.range?.start.line == 3)
    }

    /// The text builder mirrors Xtend's `StringConcatenation`.
    @Test("String concatenation primitives")
    func stringConcatenation() {
        var builder = XtendStringConcatenation()
        builder.append("a")
        builder.newLine()
        builder.append("  ")
        builder.newLineIfNotEmpty()
        builder.append("b\nc", indentation: "    ")
        builder.appendImmediate(",")
        builder.newLine()
        #expect(builder.text == "a\nb\n    c,\n")
        var empty = XtendStringConcatenation()
        empty.append("   ")
        empty.newLineIfNotEmpty()
        empty.appendImmediate("x")
        #expect(empty.text == "x")
    }
}

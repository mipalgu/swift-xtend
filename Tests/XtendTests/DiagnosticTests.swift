//
//  DiagnosticTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import Xtend

/// Tests of the diagnostics for Java interop and unsupported constructs, with positions.
@Suite("Diagnostics")
struct DiagnosticTests {
    /// The position of a diagnostic as line and column.
    private struct Position: Equatable, CustomStringConvertible {
        let code: String
        let line: Int
        let column: Int
        var description: String { "\(code)@\(line):\(column)" }
    }

    private func positions(_ diagnostics: [SourceDiagnostic]) -> [Position] {
        diagnostics.map { Position(code: $0.code, line: $0.range?.start.line ?? 0, column: $0.range?.start.column ?? 0) }
    }

    /// Java imports, types, constructors, static members and annotations outside the subset
    /// are reported where they occur, while allowed Java types pass.
    @Test("Java interop outside the subset")
    func javaInterop() {
        let source = """
            import java.io.File
            import java.util.List
            import org.eclipse.emf.ecore.util.EcoreUtil
            import static java.lang.Math.*
            import java.nio.*
            class A extends java.lang.Thread {
              def read(File f) { f }
              def make() { new java.util.Scanner(System::in) }
              def ok() { val List<String> l = new java.util.ArrayList<String>(); l }
              @Data def x() {}
              def cast(Object o) { o as java.math.BigDecimal }
            }
            """
        let program = XtendProgram(source, document: "A.xtend")
        let actual = positions(program.errors).sorted { ($0.line, $0.column) < ($1.line, $1.column) }.map(\.description)
        let expected: [String] = [
            "xtend.java.unsupportedImport@1:1", "xtend.java.unsupportedImport@3:1", "xtend.java.unsupportedImport@4:1",
            "xtend.java.unsupportedImport@5:1", "xtend.java.unsupportedType@6:17", "xtend.java.unsupportedType@7:12",
            "xtend.java.unsupportedConstructor@8:20", "xtend.java.unsupportedMember@8:38",
            "xtend.unsupported.annotation@10:3", "xtend.java.unsupportedType@11:29",
        ]
        #expect(actual == expected)
        #expect(program.errors.allSatisfy { $0.document == "A.xtend" })
        #expect(program.errors.first?.message.contains("java.io.File") == true)
        #expect(program.errors.allSatisfy { $0.code.hasPrefix(XtendLanguage.diagnosticNamespace + ".") })
    }

    /// Language constructs outside the subset are reported.
    @Test("Unsupported constructs")
    func unsupportedConstructs() {
        let source = """
            interface Shape {}
            enum Colour { RED }
            class T {
              def t() { try { 1 } catch (Exception e) { 2 } finally { 3 } }
              def s() { synchronized (this) { 1 } }
            }
            """
        let program = XtendProgram(source)
        #expect(
            positions(program.errors).map(\.description) == [
                "xtend.unsupported.construct@1:1", "xtend.unsupported.construct@2:1", "xtend.unsupported.construct@4:13",
                "xtend.unsupported.construct@5:13",
            ])
        #expect(program.classNames == ["T"])
    }

    /// Validation problems of classes are reported.
    @Test("Class validation")
    func classValidation() {
        let program = XtendProgram(
            sources: [
                XtendSource(document: "a.xtend", text: "class A {}\nclass B extends Missing {}"),
                XtendSource(document: "b.xtend", text: "class A {}"),
            ])
        #expect(
            program.errors.map(\.code).sorted() == [
                XtendDiagnosticCode.duplicateClass.rawValue, XtendDiagnosticCode.unsupportedJavaType.rawValue,
            ].sorted())
        #expect(throws: XtendError.self) { _ = try XtendInterpreter(program: program) }
    }

    /// A run-time Java member outside the subset is reported at the position of the call.
    @Test("Run-time Java member with position")
    func runtimeMember() async throws {
        let source = """
            class T {
              def run() {
                val text = 'abc'
                text.chars
              }
            }
            """
        await #expect {
            _ = try await XtendTestSupport.call(source, "run", of: "T")
        } throws: { error in
            guard let diagnostic = (error as? XtendError)?.diagnostics.first else { return false }
            return diagnostic.code == XtendDiagnosticCode.unsupportedJavaMember.rawValue && diagnostic.range?.start.line == 4
                && diagnostic.range?.start.column == 5 && diagnostic.document == "Test.xtend"
                && diagnostic.message.contains("chars")
        }
    }

    /// The textual form of an error lists each diagnostic with its position.
    @Test("Error description")
    func errorDescription() {
        let program = XtendProgram("import java.io.File\nclass A {}", document: "A.xtend")
        let error = XtendError(diagnostics: program.errors)
        #expect(error.description.hasPrefix("A.xtend:1:1: error: The Java type 'java.io.File'"))
        #expect(error.code == .unsupportedJavaImport)
    }
}

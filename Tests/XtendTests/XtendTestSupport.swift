//
//  XtendTestSupport.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import Xtend

/// Helpers that compile and run Xtend snippets in tests.
enum XtendTestSupport {
    /// Compiles a program and fails the test with its diagnostics if it has errors.
    ///
    /// - Parameters:
    ///   - sources: The documents by name.
    ///   - metamodels: The metamodels the documents may use.
    /// - Returns: The program.
    static func program(_ sources: [String: String], metamodels: [EPackage] = []) throws -> XtendProgram {
        let program = XtendProgram(
            sources: sources.sorted { $0.key < $1.key }.map { XtendSource(document: $0.key, text: $0.value) },
            metamodels: metamodels)
        if program.hasErrors { throw XtendError(diagnostics: program.errors) }
        return program
    }

    /// Calls a method of a class of a single-document program.
    ///
    /// - Parameters:
    ///   - source: The source of the document.
    ///   - method: The method to call.
    ///   - className: The class that declares the method.
    ///   - arguments: The arguments.
    /// - Returns: The result.
    static func call(
        _ source: String, _ method: String, of className: String, arguments: [XtendHostValue] = []
    ) async throws -> XtendHostValue {
        let interpreter = try XtendInterpreter(program: try program(["Test.xtend": source]))
        return try await interpreter.call(method, of: className, arguments: arguments)
    }

    /// Evaluates a standalone expression with an empty program.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The value.
    static func evaluate(_ expression: String) async throws -> XtendHostValue {
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []))
        return try await interpreter.evaluate(expression)
    }

    /// The error code that evaluating an expression fails with.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The code of the error, or `nil` if evaluation succeeds.
    static func failureCode(of expression: String) async -> XtendDiagnosticCode? {
        do {
            _ = try await evaluate(expression)
            return nil
        } catch let error as XtendError {
            return error.code
        } catch {
            return nil
        }
    }

    /// The textual form of a host value, as Java would print it.
    static func text(_ value: XtendHostValue) -> String { value.description }
}

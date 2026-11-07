//
//  XtendDiagnostics.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The kinds of problem that the Xtend parser, validator and interpreter report.
///
/// Each code's raw value is the stable machine-readable identifier stored in
/// `SourceDiagnostic.code`. All codes start with
/// ``XtendLanguage/diagnosticNamespace``.
public enum XtendDiagnosticCode: String, CaseIterable, Sendable {
    /// A token appeared where the grammar does not allow it.
    case unexpectedToken = "xtend.syntax.unexpectedToken"
    /// A character that cannot start any token.
    case invalidCharacter = "xtend.syntax.invalidCharacter"
    /// A string literal without its closing quote.
    case unterminatedString = "xtend.syntax.unterminatedString"
    /// A rich string without its closing delimiter.
    case unterminatedRichString = "xtend.syntax.unterminatedRichString"
    /// A block comment without its closing delimiter.
    case unterminatedComment = "xtend.syntax.unterminatedComment"
    /// A numeric literal that cannot be read.
    case invalidNumber = "xtend.syntax.invalidNumber"
    /// A control structure of a rich string without its counterpart, such as `ENDFOR` without `FOR`.
    case unbalancedTemplate = "xtend.syntax.unbalancedTemplate"
    /// A language construct outside the interpreted subset, such as `try` or an interface.
    case unsupportedConstruct = "xtend.unsupported.construct"
    /// An annotation that the interpreter does not understand.
    case unsupportedAnnotation = "xtend.unsupported.annotation"
    /// An import of a Java type or package outside the documented subset.
    case unsupportedJavaImport = "xtend.java.unsupportedImport"
    /// A reference to a Java type outside the documented subset.
    case unsupportedJavaType = "xtend.java.unsupportedType"
    /// A constructor call of a Java type outside the documented subset.
    case unsupportedJavaConstructor = "xtend.java.unsupportedConstructor"
    /// A Java method or field outside the documented subset.
    case unsupportedJavaMember = "xtend.java.unsupportedMember"
    /// Two classes of a compilation set with the same name.
    case duplicateClass = "xtend.validation.duplicateClass"
    /// A superclass that is neither an Xtend class of the compilation set nor allowed.
    case unknownSuperclass = "xtend.validation.unknownSuperclass"
    /// A name that does not denote a variable, feature, method or type.
    case unknownFeature = "xtend.runtime.unknownFeature"
    /// A class that the compilation set does not declare.
    case unknownClass = "xtend.runtime.unknownClass"
    /// A member access on `null`.
    case nullPointer = "xtend.runtime.nullPointer"
    /// A value of the wrong type for an operation.
    case typeMismatch = "xtend.runtime.typeMismatch"
    /// A dispatch method without a case for the runtime types of its arguments.
    case noDispatchCase = "xtend.runtime.noDispatchCase"
    /// An assignment to something that cannot be assigned.
    case invalidAssignment = "xtend.runtime.invalidAssignment"
    /// A cast to a type that the value does not have.
    case invalidCast = "xtend.runtime.invalidCast"
    /// An index outside the bounds of a list or string.
    case indexOutOfBounds = "xtend.runtime.indexOutOfBounds"
    /// A whole-number division by zero.
    case divisionByZero = "xtend.runtime.divisionByZero"
    /// An attempt to modify an immutable collection.
    case immutableCollection = "xtend.runtime.immutableCollection"
    /// An exception raised by the program with `throw`.
    case thrownException = "xtend.runtime.thrownException"
    /// Calls nested deeper than the configured limit.
    case recursionLimit = "xtend.runtime.recursionLimit"
    /// More evaluation steps than the configured limit.
    case stepLimit = "xtend.runtime.stepLimit"
    /// A failure of the file system access.
    case fileAccess = "xtend.runtime.fileAccess"
    /// A model operation that the resource refused.
    case modelAccess = "xtend.runtime.modelAccess"
    /// An argument of the wrong kind for a library function.
    case invalidArgument = "xtend.runtime.invalidArgument"
}

/// An error raised by the Xtend toolchain, carrying one or more diagnostics.
///
/// Parsing and validation collect all problems they find and raise this error with every
/// error-severity diagnostic when a program cannot run. Evaluation stops at the first
/// problem and raises it with a single diagnostic that records the position of the
/// expression that failed.
public struct XtendError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The problems, in the order they were found.
    public var diagnostics: [SourceDiagnostic]

    /// Creates an error from diagnostics.
    ///
    /// - Parameter diagnostics: The problems that the error reports.
    public init(diagnostics: [SourceDiagnostic]) {
        self.diagnostics = diagnostics
    }

    /// Creates an error with a single diagnostic of error severity.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected source text, if known.
    ///   - document: The document the range refers to, if known.
    public init(_ code: XtendDiagnosticCode, _ message: String, range: SourceRange? = nil, document: String? = nil) {
        self.diagnostics = [
            SourceDiagnostic(severity: .error, code: code.rawValue, message: message, range: range, document: document)
        ]
    }

    /// The code of the first diagnostic, if it is one of the Xtend codes.
    public var code: XtendDiagnosticCode? {
        diagnostics.first.flatMap { XtendDiagnosticCode(rawValue: $0.code) }
    }

    /// A readable summary listing each diagnostic with its position.
    public var description: String {
        diagnostics.map { diagnostic in
            var text = ""
            if let document = diagnostic.document { text += document + ":" }
            if let range = diagnostic.range { text += "\(range.start.line):\(range.start.column): " }
            return text + "\(diagnostic.severity): \(diagnostic.message) [\(diagnostic.code)]"
        }.joined(separator: "\n")
    }
}

extension SourceDiagnostic {
    /// Creates a diagnostic with an Xtend code.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text, if any.
    ///   - document: The document the range refers to, if known.
    ///   - severity: How serious the problem is (default error).
    static func xtend(
        _ code: XtendDiagnosticCode, _ message: String, range: SourceRange?, document: String?,
        severity: DiagnosticSeverity = .error
    ) -> SourceDiagnostic {
        SourceDiagnostic(severity: severity, code: code.rawValue, message: message, range: range, document: document)
    }
}

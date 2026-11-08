//
//  XtendLanguage.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The vocabulary of the interpreted Xtend subset.
///
/// This type is the single authoritative place for the file extension, the reserved words,
/// the template keywords, the delimiters of rich strings, the generator conventions and the
/// documented allow-list of Java types and members that the interpreter provides natively.
public enum XtendLanguage {
    /// The file extension of Xtend documents, without the leading full stop.
    public static let fileExtension = "xtend"

    /// The prefix of every diagnostic code that the parser, validator and interpreter report.
    public static let diagnosticNamespace = "xtend"

    /// The delimiter that opens and closes a rich string (template expression).
    public static let richStringDelimiter = "'''"

    /// The character that opens an interpolation or control structure inside a rich string.
    public static let openingGuillemet: Unicode.Scalar = "«"

    /// The character that closes an interpolation or control structure inside a rich string.
    public static let closingGuillemet: Unicode.Scalar = "»"

    /// The line delimiter that rich strings and generated files use.
    public static let lineDelimiter = "\n"

    /// The name of the output configuration that files are written to when none is given.
    ///
    /// This mirrors the default output configuration of Xtext file system access.
    public static let defaultOutputConfiguration = "DEFAULT_OUTPUT"

    /// The names of the methods that ``XtendInterpreter/generate(resource:fileSystem:className:)``
    /// looks for, in order of preference.
    ///
    /// A generator method takes the input resource and a file system access, optionally
    /// followed by a generator context.
    public static let generatorMethodNames = ["doGenerate", "generate"]

    /// The numbers of parameters that a generator method can take, in order of preference.
    ///
    /// A generator method takes the input resource and a file system access, optionally
    /// followed by a generator context.
    public static let generatorArities = [2, 3]

    /// The name of the implicit parameter of a lambda expression with one argument.
    public static let implicitParameter = "it"

    /// The name of the implicit receiver of instance members.
    public static let thisName = "this"

    /// The name of a constructor declaration.
    public static let constructorName = "new"

    /// The reserved words of the language.
    ///
    /// Reserved words cannot be used as identifiers unless they are escaped with a leading
    /// caret, as in `^class`.
    public enum Keyword: String, CaseIterable, Sendable {
        /// Declares the package of a file.
        case package
        /// Imports a type or its static members.
        case `import`
        /// Marks a member as static or an import as a static import.
        case `static`
        /// Makes a field, parameter, variable or import an extension provider.
        case `extension`
        /// Declares a class.
        case `class`
        /// Declares an interface (not supported).
        case interface
        /// Declares an enumeration (not supported).
        case `enum`
        /// Declares an annotation type (not supported).
        case annotation
        /// Introduces a superclass.
        case extends
        /// Introduces implemented interfaces.
        case implements
        /// Declares a method.
        case def
        /// Declares a method that overrides an inherited one.
        case override
        /// Marks a method as one case of a polymorphic dispatch method.
        case dispatch
        /// Marks a method as a create method whose results are cached.
        case create
        /// Declares a final variable or field.
        case val
        /// Declares a mutable variable or field.
        case `var`
        /// Marks a member as final.
        case final
        /// Marks a member as abstract.
        case abstract
        /// Restricts a member to its class.
        case `private`
        /// Restricts a member to its package and subclasses.
        case `protected`
        /// Makes a member visible everywhere.
        case `public`
        /// Restricts a member to its package.
        case packageVisibility = "package-visibility"
        /// Creates an object.
        case new
        /// Starts a conditional expression.
        case `if`
        /// Introduces the alternative of a conditional expression.
        case `else`
        /// Starts a switch expression.
        case `switch`
        /// Introduces a case of a switch expression.
        case `case`
        /// Introduces the default case of a switch expression.
        case `default`
        /// Starts a loop over a collection, or a counting loop.
        case `for`
        /// Starts a pre-tested loop.
        case `while`
        /// Starts a post-tested loop.
        case `do`
        /// Returns from a method or lambda expression.
        case `return`
        /// Raises an exception.
        case `throw`
        /// Starts a protected block (not supported).
        case `try`
        /// Introduces an exception handler (not supported).
        case `catch`
        /// Introduces a final handler (not supported).
        case finally
        /// Introduces declared exceptions, which are ignored.
        case `throws`
        /// Starts a synchronised block (not supported).
        case synchronized
        /// Refers to a type as a value.
        case typeof
        /// Tests the runtime type of a value.
        case `instanceof`
        /// Casts a value to a type.
        case `as`
        /// The absent value.
        case null
        /// The Boolean value true.
        case `true`
        /// The Boolean value false.
        case `false`
        /// The receiver of instance members.
        case this
        /// The superclass view of the receiver.
        case `super`
    }

    /// The keywords of the control structures of rich strings.
    ///
    /// These words are only keywords between guillemets inside a rich string.
    public enum TemplateKeyword: String, CaseIterable, Sendable {
        /// Starts a loop.
        case FOR
        /// Ends a loop.
        case ENDFOR
        /// Starts a conditional.
        case IF
        /// Introduces an alternative condition.
        case ELSEIF
        /// Introduces the final alternative.
        case ELSE
        /// Ends a conditional.
        case ENDIF
        /// Introduces the text written before the first iteration of a loop.
        case BEFORE
        /// Introduces the text written between iterations of a loop.
        case SEPARATOR
        /// Introduces the text written after the last iteration of a loop.
        case AFTER
    }

    /// The annotations that the interpreter understands.
    ///
    /// `@Inject` on an extension field of an Xtend class type instantiates that class when
    /// no initialiser is given. `@Override` is accepted and ignored. Every other annotation
    /// is reported as unsupported.
    public static let supportedAnnotations: Set<String> = ["Inject", "Override", "SuppressWarnings"]

    /// The labels of the outline nodes that ``XtendParser`` produces.
    public enum OutlineKind: String, Sendable, CaseIterable {
        /// A class declaration.
        case `class`
        /// A field declaration.
        case field
        /// An ordinary method.
        case method
        /// A case of a dispatch method.
        case dispatchMethod
        /// A create method.
        case createMethod
        /// A constructor.
        case constructor
    }
}

//
//  XtendProgram.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The text of an Xtend document with its identifier.
public struct XtendSource: Sendable, Hashable {
    /// The identifier of the document, such as its URI or file name.
    public var document: String

    /// The source text.
    public var text: String

    /// Creates a source.
    ///
    /// - Parameters:
    ///   - document: The identifier of the document.
    ///   - text: The source text.
    public init(document: String, text: String) {
        self.document = document
        self.text = text
    }
}

/// A class of a compilation set with the context needed to run its code.
struct XtendClassInfo: Sendable {
    /// The declaration.
    let declaration: XtendClass
    /// The imports of the declaring file.
    let imports: [XtendImport]
    /// The qualified name of the superclass, if it is a class of the compilation set.
    let superclass: String?
    /// The qualified names of the classes whose static methods the file imports as extensions.
    let staticExtensionClasses: [String]
}

/// A validated set of Xtend documents that can be interpreted together.
///
/// A program parses its sources, links the classes they declare, and checks that every
/// import, type reference, constructor call and static member access is either part of the
/// compilation set, a classifier of one of the given metamodels, or part of the documented
/// Java subset (see ``XtendJavaSubset``). Classes of one compilation set can extend each other
/// and use each other as extension providers.
public struct XtendProgram: Sendable {
    /// The parse results of the sources, in the order given.
    public let parseResults: [XtendParseResult]

    /// All diagnostics of parsing and validation.
    public let diagnostics: [SourceDiagnostic]

    /// The metamodels whose classifiers the program may refer to.
    public let metamodels: [EPackage]

    /// The classes by qualified name.
    let classes: [String: XtendClassInfo]

    /// The qualified class names in declaration order.
    public let classNames: [String]

    /// The type resolver for the program.
    let resolver: XtendTypeResolver

    /// Parses, links and validates a compilation set.
    ///
    /// - Parameters:
    ///   - sources: The documents of the compilation set.
    ///   - metamodels: The metamodels whose classifiers the documents may use.
    public init(sources: [XtendSource], metamodels: [EPackage] = []) {
        let results = sources.map { XtendParser.parse($0.text, document: $0.document) }
        var diagnostics = results.flatMap(\.diagnostics)
        var classNames: [String] = []
        var byName: [String: String] = [:]
        var declarations: [String: (XtendClass, XtendFile)] = [:]
        for result in results {
            for declaration in result.file.classes {
                let qualified = declaration.qualifiedName
                if declarations[qualified] != nil {
                    diagnostics.append(
                        .xtend(
                            .duplicateClass, "The class '\(qualified)' is declared more than once",
                            range: declaration.nameRange, document: declaration.document))
                    continue
                }
                declarations[qualified] = (declaration, result.file)
                classNames.append(qualified)
                byName[qualified] = qualified
                if byName[declaration.name] == nil { byName[declaration.name] = qualified }
            }
        }
        var superclasses: [String: String] = [:]
        for (qualified, entry) in declarations {
            if let superclass = entry.0.superclass {
                let imported = entry.1.imports.first { !$0.isStatic && $0.simpleName == superclass.name }?.name
                if let target = byName[imported ?? superclass.name] ?? byName[superclass.name] {
                    superclasses[qualified] = target
                }
            }
        }
        let resolver = XtendTypeResolver(metamodels: metamodels, classNames: byName, superclasses: superclasses)
        var classes: [String: XtendClassInfo] = [:]
        for (qualified, entry) in declarations {
            let staticExtensions = entry.1.imports.filter { $0.isStatic && $0.isExtension }.compactMap { item -> String? in
                let target = item.isWildcard ? item.name : String(item.name.split(separator: ".").dropLast().joined(separator: "."))
                return resolver.className(target) ?? resolver.className(item.name)
            }
            classes[qualified] = XtendClassInfo(
                declaration: entry.0, imports: entry.1.imports, superclass: superclasses[qualified],
                staticExtensionClasses: staticExtensions)
        }
        var validator = XtendValidator(resolver: resolver, classes: classes)
        for result in results { validator.validate(result.file) }
        diagnostics.append(contentsOf: validator.diagnostics)
        self.parseResults = results
        self.diagnostics = diagnostics
        self.metamodels = metamodels
        self.classes = classes
        self.classNames = classNames
        self.resolver = resolver
    }

    /// Creates a program from a single document.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The identifier of the document.
    ///   - metamodels: The metamodels whose classifiers the document may use.
    public init(_ text: String, document: String = "main.\(XtendLanguage.fileExtension)", metamodels: [EPackage] = []) {
        self.init(sources: [XtendSource(document: document, text: text)], metamodels: metamodels)
    }

    /// Whether any diagnostic is an error, in which case the program cannot be interpreted.
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    /// The error-severity diagnostics.
    public var errors: [SourceDiagnostic] { diagnostics.filter { $0.severity == .error } }

    /// Looks a class up by simple or qualified name.
    func classInfo(_ name: String) -> XtendClassInfo? {
        resolver.className(name).flatMap { classes[$0] }
    }
}

/// Checks a parsed file against the interpreted subset.
struct XtendValidator {
    /// The resolver that maps type references to classes, metamodel classifiers and the supported Java subset.
    let resolver: XtendTypeResolver
    /// The classes of the compilation set, keyed by qualified name.
    let classes: [String: XtendClassInfo]
    private(set) var diagnostics: [SourceDiagnostic] = []
    /// The imports of the file being validated.
    private var imports: [XtendImport] = []
    /// The identifier of the document being validated, attached to diagnostics.
    private var document = ""

    /// Creates a validator.
    init(resolver: XtendTypeResolver, classes: [String: XtendClassInfo]) {
        self.resolver = resolver
        self.classes = classes
    }

    /// Records an error against the file being validated.
    ///
    /// - Parameters:
    ///   - code: The kind of diagnostic.
    ///   - message: The description of the problem.
    ///   - range: The source extent that the problem concerns.
    private mutating func report(_ code: XtendDiagnosticCode, _ message: String, _ range: SourceRange) {
        diagnostics.append(.xtend(code, message, range: range, document: document))
    }

    /// Validates a file.
    mutating func validate(_ file: XtendFile) {
        imports = file.imports
        document = file.document
        for item in file.imports { validate(item) }
        for declaration in file.classes {
            validate(annotations: declaration.annotations)
            if let superclass = declaration.superclass {
                switch resolver.resolve(superclass, imports: imports) {
                case .xtendClass?, .builtin(.generator)?, .builtin(.object)?: break
                case nil:
                    report(
                        .unsupportedJavaType,
                        "The superclass '\(superclass.name)' is neither a class of the compilation set nor part of the supported Java subset",
                        superclass.range)
                default:
                    report(.unknownSuperclass, "A class cannot extend '\(superclass.name)'", superclass.range)
                }
            }
            for field in declaration.fields {
                validate(annotations: field.annotations)
                if let type = field.type { validate(type) }
                if let initialiser = field.initialiser { validate(initialiser) }
            }
            for method in declaration.methods {
                validate(annotations: method.annotations)
                for parameter in method.parameters { if let type = parameter.type { validate(type) } }
                if let returnType = method.returnType { validate(returnType) }
                if let create = method.createClause { validate(create.expression) }
                if let body = method.body { validate(body) }
            }
        }
    }

    /// Reports each annotation that the interpreter does not support.
    ///
    /// - Parameter annotations: The annotations to check.
    private mutating func validate(annotations: [XtendAnnotation]) {
        for annotation in annotations where !XtendLanguage.supportedAnnotations.contains(annotation.simpleName) {
            report(
                .unsupportedAnnotation,
                "The annotation '@\(annotation.simpleName)' is not supported by the interpreter", annotation.range)
        }
    }

    /// Reports an import that refers to Java code outside the supported subset.
    ///
    /// - Parameter item: The import to check.
    private mutating func validate(_ item: XtendImport) {
        let name = item.name
        if item.isStatic {
            let owner = item.isWildcard ? name : name.split(separator: ".").dropLast().joined(separator: ".")
            if resolver.className(owner) != nil || resolver.className(name) != nil
                || XtendJavaSubset.libraryClasses.contains(owner)
            {
                return
            }
            report(
                .unsupportedJavaImport,
                "The static import '\(name)' refers to Java code outside the supported subset; only Xtend classes of the compilation set and the Xbase library can be imported statically",
                item.range)
            return
        }
        if item.isWildcard {
            if XtendJavaSubset.importablePackages.contains(name) || resolver.packageNames.contains(name)
                || classes.values.contains(where: { $0.declaration.packageName == name })
            {
                return
            }
            report(
                .unsupportedJavaImport,
                "The package '\(name)' is neither a metamodel package nor part of the supported Java subset", item.range)
            return
        }
        if resolver.className(name) != nil || resolver.isClassifier(name) || XtendJavaSubset.builtinType(named: name) != nil
            || XtendJavaSubset.libraryClasses.contains(name)
        {
            return
        }
        report(
            .unsupportedJavaImport,
            "The Java type '\(name)' is outside the supported subset; the interpreter cannot load Java classes",
            item.range)
    }

    /// Reports a type, or any of its type arguments, that cannot be resolved.
    ///
    /// - Parameter type: The type reference to check.
    private mutating func validate(_ type: XtendTypeReference) {
        for argument in type.arguments { validate(argument) }
        if type.isFunctionType { return }
        if resolver.resolve(type, imports: imports) == nil {
            report(
                .unsupportedJavaType,
                "Unknown type '\(type.name)': it is neither a class of the compilation set, nor a metamodel classifier, nor part of the supported Java subset",
                type.range)
        }
    }

    /// Validates a standalone expression.
    mutating func validate(expression: XtendExpression) {
        validate(expression)
    }

    /// Checks an expression and its subexpressions against the supported subset.
    ///
    /// - Parameter expression: The expression to check.
    private mutating func validate(_ expression: XtendExpression) {
        switch expression.kind {
        case .nullLiteral, .booleanLiteral, .integerLiteral, .doubleLiteral, .stringLiteral, .this, .superReference,
            .unsupported:
            break
        case .richString(let template):
            validate(template.instructions)
        case .listLiteral(let elements), .setLiteral(let elements), .block(let elements):
            elements.forEach { validate($0) }
        case .lambda(let parameters, _, let body):
            for parameter in parameters { if let type = parameter.type { validate(type) } }
            validate(body)
        case .featureCall(_, let arguments, _):
            arguments.forEach { validate($0) }
        case .memberCall(let receiver, _, let arguments, _, _):
            validate(receiver)
            arguments.forEach { validate($0) }
        case .staticCall(let type, let name, let arguments, _):
            arguments.forEach { validate($0) }
            validateStatic(type, member: name)
        case .assignment(let target, let value), .compoundAssignment(_, let target, let value):
            validate(target)
            validate(value)
        case .binary(_, let left, let right):
            validate(left)
            validate(right)
        case .unary(_, let operand), .postfix(_, let operand), .returnExpression(let operand?), .throwExpression(let operand):
            validate(operand)
        case .returnExpression(nil):
            break
        case .instanceOf(let operand, let type), .cast(let operand, let type):
            validate(operand)
            validate(type)
        case .ifExpression(let condition, let then, let otherwise):
            validate(condition)
            validate(then)
            if let otherwise { validate(otherwise) }
        case .switchExpression(let switchExpression):
            validate(switchExpression.subject)
            for item in switchExpression.cases {
                if let type = item.typeGuard { validate(type) }
                if let condition = item.condition { validate(condition) }
                if let body = item.body { validate(body) }
            }
            if let defaultBranch = switchExpression.defaultBranch { validate(defaultBranch) }
        case .forEach(let parameter, let iterable, let body):
            if let type = parameter.type { validate(type) }
            validate(iterable)
            validate(body)
        case .basicFor(let initialisers, let condition, let updates, let body):
            initialisers.forEach { validate($0) }
            if let condition { validate(condition) }
            updates.forEach { validate($0) }
            validate(body)
        case .whileLoop(let condition, let body), .doWhileLoop(let body, let condition):
            validate(condition)
            validate(body)
        case .variableDeclaration(_, let type, _, _, let initialiser):
            if let type { validate(type) }
            if let initialiser { validate(initialiser) }
        case .constructorCall(let type, let arguments):
            arguments.forEach { validate($0) }
            switch resolver.resolve(type, imports: imports) {
            case nil:
                report(
                    .unsupportedJavaConstructor,
                    "Cannot create an instance of '\(type.name)': it is neither a class of the compilation set, nor a metamodel class, nor a constructible type of the supported Java subset",
                    type.range)
            case .builtin(let builtin)? where !XtendJavaSubset.constructibleTypes.contains(builtin):
                report(
                    .unsupportedJavaConstructor,
                    "The Java type '\(type.name)' cannot be instantiated by the interpreter", type.range)
            default: break
            }
        case .typeLiteral(let type):
            validate(type)
        }
    }

    /// Checks the expressions and nested blocks of template instructions.
    ///
    /// - Parameter instructions: The instructions to check.
    private mutating func validate(_ instructions: [XtendTemplateInstruction]) {
        for instruction in instructions {
            switch instruction {
            case .literal, .newLine, .newLineIfNotEmpty: break
            case .expression(let expression, _): validate(expression)
            case .loop(let loop):
                if let type = loop.parameter.type { validate(type) }
                validate(loop.iterable)
                for clause in [loop.before, loop.separator, loop.after].compactMap({ $0 }) { validate(clause) }
                validate(loop.body)
            case .conditional(let conditional):
                for branch in conditional.branches {
                    validate(branch.condition)
                    validate(branch.body)
                }
                if let otherwise = conditional.otherwise { validate(otherwise) }
            }
        }
    }

    /// Reports a static member that is outside the supported Java subset.
    ///
    /// - Parameters:
    ///   - type: The type that declares the member.
    ///   - member: The name of the static member.
    private mutating func validateStatic(_ type: XtendTypeReference, member: String) {
        switch resolver.resolve(type, imports: imports) {
        case .xtendClass?, .modelEnum?, .modelClass?: return
        case .builtin?:
            if XtendJavaSubset.staticMembers[type.simpleName]?.contains(member) == true { return }
            report(
                .unsupportedJavaMember,
                "The static member '\(type.simpleName)::\(member)' is outside the supported Java subset", type.range)
        case nil:
            if XtendJavaSubset.staticMembers[type.simpleName]?.contains(member) == true { return }
            report(
                .unsupportedJavaMember,
                "The static member '\(type.name)::\(member)' refers to a Java type outside the supported subset",
                type.range)
        }
    }
}

//
//  XtendSyntax.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A parsed Xtend document.
///
/// A file declares an optional package, its imports and one or more classes.
public struct XtendFile: Sendable {
    /// The identifier of the document, such as its URI.
    public var document: String

    /// The declared package, if any.
    public var packageName: String?

    /// The imports in source order.
    public var imports: [XtendImport]

    /// The classes in source order.
    public var classes: [XtendClass]

    /// Creates a file.
    ///
    /// - Parameters:
    ///   - document: The identifier of the document.
    ///   - packageName: The declared package, if any.
    ///   - imports: The imports in source order.
    ///   - classes: The classes in source order.
    public init(document: String, packageName: String? = nil, imports: [XtendImport] = [], classes: [XtendClass] = []) {
        self.document = document
        self.packageName = packageName
        self.imports = imports
        self.classes = classes
    }
}

/// An import declaration.
public struct XtendImport: Sendable, Hashable {
    /// The imported qualified name, without a trailing wildcard.
    public var name: String

    /// Whether the import is a static import.
    public var isStatic: Bool

    /// Whether the import makes static methods available as extension methods.
    public var isExtension: Bool

    /// Whether the import ends in a wildcard (`.*`).
    public var isWildcard: Bool

    /// The extent of the declaration.
    public var range: SourceRange

    /// Creates an import.
    ///
    /// - Parameters:
    ///   - name: The imported qualified name.
    ///   - isStatic: Whether the import is static.
    ///   - isExtension: Whether static methods become extension methods.
    ///   - isWildcard: Whether the import ends in a wildcard.
    ///   - range: The extent of the declaration.
    public init(name: String, isStatic: Bool = false, isExtension: Bool = false, isWildcard: Bool = false, range: SourceRange) {
        self.name = name
        self.isStatic = isStatic
        self.isExtension = isExtension
        self.isWildcard = isWildcard
        self.range = range
    }

    /// The last segment of the imported name.
    public var simpleName: String {
        name.split(separator: ".").last.map(String.init) ?? name
    }
}

/// A reference to a type, as written in the source.
public struct XtendTypeReference: Sendable, Hashable {
    /// The simple or qualified name of the type, or `=>` for a function type.
    public var name: String

    /// The type arguments, or the parameter and result types of a function type.
    public var arguments: [XtendTypeReference]

    /// The number of array dimensions.
    public var arrayDimensions: Int

    /// The extent of the reference.
    public var range: SourceRange

    /// The name used for function types.
    public static let functionTypeName = "=>"

    /// Creates a type reference.
    ///
    /// - Parameters:
    ///   - name: The simple or qualified name of the type.
    ///   - arguments: The type arguments.
    ///   - arrayDimensions: The number of array dimensions.
    ///   - range: The extent of the reference.
    public init(name: String, arguments: [XtendTypeReference] = [], arrayDimensions: Int = 0, range: SourceRange) {
        self.name = name
        self.arguments = arguments
        self.arrayDimensions = arrayDimensions
        self.range = range
    }

    /// Whether this reference denotes a function type such as `(String)=>int`.
    public var isFunctionType: Bool { name == Self.functionTypeName }

    /// The last segment of the type name.
    public var simpleName: String {
        name.split(separator: ".").last.map(String.init) ?? name
    }

    /// The source-like rendering of the reference.
    public var description: String {
        if isFunctionType {
            let parameters = arguments.dropLast().map(\.description).joined(separator: ", ")
            return "(\(parameters))=>\(arguments.last?.description ?? "void")"
        }
        var text = name
        if !arguments.isEmpty { text += "<" + arguments.map(\.description).joined(separator: ", ") + ">" }
        return text + String(repeating: "[]", count: arrayDimensions)
    }
}

/// An annotation, which the interpreter mostly ignores.
public struct XtendAnnotation: Sendable, Hashable {
    /// The simple or qualified name of the annotation type.
    public var name: String

    /// The extent of the annotation including any arguments.
    public var range: SourceRange

    /// Creates an annotation.
    ///
    /// - Parameters:
    ///   - name: The name of the annotation type.
    ///   - range: The extent of the annotation.
    public init(name: String, range: SourceRange) {
        self.name = name
        self.range = range
    }

    /// The last segment of the annotation name.
    public var simpleName: String {
        name.split(separator: ".").last.map(String.init) ?? name
    }
}

/// The modifiers of a member declaration.
public struct XtendModifiers: Sendable, Hashable {
    /// Whether the member is static.
    public var isStatic = false
    /// Whether the member is an extension provider.
    public var isExtension = false
    /// Whether the member overrides an inherited method.
    public var isOverride = false
    /// Whether the method is a case of a dispatch method.
    public var isDispatch = false
    /// Whether the member is abstract.
    public var isAbstract = false
    /// Whether the field is final.
    public var isFinal = false
    /// The declared visibility keyword, if any.
    public var visibility: String?

    /// Creates modifiers with nothing set.
    public init() {}
}

/// A parameter of a method, constructor or lambda expression.
public struct XtendParameter: Sendable, Hashable {
    /// The name of the parameter.
    public var name: String

    /// The declared type, if any.
    public var type: XtendTypeReference?

    /// Whether the parameter is an extension provider.
    public var isExtension: Bool

    /// The extent of the parameter.
    public var range: SourceRange

    /// Creates a parameter.
    ///
    /// - Parameters:
    ///   - name: The name of the parameter.
    ///   - type: The declared type, if any.
    ///   - isExtension: Whether the parameter is an extension provider.
    ///   - range: The extent of the parameter.
    public init(name: String, type: XtendTypeReference? = nil, isExtension: Bool = false, range: SourceRange) {
        self.name = name
        self.type = type
        self.isExtension = isExtension
        self.range = range
    }
}

/// A field of a class.
public struct XtendField: Sendable {
    /// The name of the field.
    public var name: String

    /// The declared type, if any.
    public var type: XtendTypeReference?

    /// The modifiers of the field.
    public var modifiers: XtendModifiers

    /// Whether the field was declared with `val` (or is otherwise final).
    public var isFinal: Bool

    /// The initialiser, if any.
    public var initialiser: XtendExpression?

    /// The annotations of the field.
    public var annotations: [XtendAnnotation]

    /// The extent of the declaration.
    public var range: SourceRange

    /// The extent of the field name.
    public var nameRange: SourceRange

    /// Creates a field.
    ///
    /// - Parameters:
    ///   - name: The name of the field.
    ///   - type: The declared type, if any.
    ///   - modifiers: The modifiers of the field.
    ///   - isFinal: Whether the field is final.
    ///   - initialiser: The initialiser, if any.
    ///   - annotations: The annotations of the field.
    ///   - range: The extent of the declaration.
    ///   - nameRange: The extent of the field name.
    public init(
        name: String, type: XtendTypeReference?, modifiers: XtendModifiers, isFinal: Bool,
        initialiser: XtendExpression?, annotations: [XtendAnnotation], range: SourceRange, nameRange: SourceRange
    ) {
        self.name = name
        self.type = type
        self.modifiers = modifiers
        self.isFinal = isFinal
        self.initialiser = initialiser
        self.annotations = annotations
        self.range = range
        self.nameRange = nameRange
    }
}

/// The create clause of a create method, as in `def create result: new Person() toPerson(...)`.
public struct XtendCreateClause: Sendable {
    /// The name under which the created object is visible in the body (`it` by default).
    public var name: String

    /// The expression that creates the object.
    public var expression: XtendExpression

    /// Creates a create clause.
    ///
    /// - Parameters:
    ///   - name: The name of the created object in the body.
    ///   - expression: The expression that creates the object.
    public init(name: String, expression: XtendExpression) {
        self.name = name
        self.expression = expression
    }
}

/// A method or constructor of a class.
public struct XtendMethod: Sendable {
    /// The name of the method, or ``XtendLanguage/constructorName`` for a constructor.
    public var name: String

    /// The parameters in order.
    public var parameters: [XtendParameter]

    /// The declared result type, if any.
    public var returnType: XtendTypeReference?

    /// The modifiers of the method.
    public var modifiers: XtendModifiers

    /// The create clause of a create method, if any.
    public var createClause: XtendCreateClause?

    /// The body, which is a block or a rich string, or `nil` for an abstract method.
    public var body: XtendExpression?

    /// The annotations of the method.
    public var annotations: [XtendAnnotation]

    /// The extent of the declaration.
    public var range: SourceRange

    /// The extent of the method name.
    public var nameRange: SourceRange

    /// Creates a method.
    ///
    /// - Parameters:
    ///   - name: The name of the method.
    ///   - parameters: The parameters in order.
    ///   - returnType: The declared result type, if any.
    ///   - modifiers: The modifiers of the method.
    ///   - createClause: The create clause, if any.
    ///   - body: The body, if any.
    ///   - annotations: The annotations of the method.
    ///   - range: The extent of the declaration.
    ///   - nameRange: The extent of the method name.
    public init(
        name: String, parameters: [XtendParameter], returnType: XtendTypeReference?, modifiers: XtendModifiers,
        createClause: XtendCreateClause?, body: XtendExpression?, annotations: [XtendAnnotation],
        range: SourceRange, nameRange: SourceRange
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.modifiers = modifiers
        self.createClause = createClause
        self.body = body
        self.annotations = annotations
        self.range = range
        self.nameRange = nameRange
    }

    /// Whether this declaration is a constructor.
    public var isConstructor: Bool { name == XtendLanguage.constructorName }
}

/// A class declaration.
public struct XtendClass: Sendable {
    /// The simple name of the class.
    public var name: String

    /// The package of the file that declares the class, if any.
    public var packageName: String?

    /// The superclass, if any.
    public var superclass: XtendTypeReference?

    /// The implemented interfaces, which the interpreter ignores.
    public var interfaces: [XtendTypeReference]

    /// Whether the class is abstract.
    public var isAbstract: Bool

    /// The fields in source order.
    public var fields: [XtendField]

    /// The methods and constructors in source order.
    public var methods: [XtendMethod]

    /// The annotations of the class.
    public var annotations: [XtendAnnotation]

    /// The document that declares the class.
    public var document: String

    /// The extent of the declaration.
    public var range: SourceRange

    /// The extent of the class name.
    public var nameRange: SourceRange

    /// Creates a class.
    ///
    /// - Parameters:
    ///   - name: The simple name of the class.
    ///   - packageName: The package of the declaring file, if any.
    ///   - superclass: The superclass, if any.
    ///   - interfaces: The implemented interfaces.
    ///   - isAbstract: Whether the class is abstract.
    ///   - fields: The fields in source order.
    ///   - methods: The methods in source order.
    ///   - annotations: The annotations of the class.
    ///   - document: The declaring document.
    ///   - range: The extent of the declaration.
    ///   - nameRange: The extent of the class name.
    public init(
        name: String, packageName: String?, superclass: XtendTypeReference?, interfaces: [XtendTypeReference],
        isAbstract: Bool, fields: [XtendField], methods: [XtendMethod], annotations: [XtendAnnotation],
        document: String, range: SourceRange, nameRange: SourceRange
    ) {
        self.name = name
        self.packageName = packageName
        self.superclass = superclass
        self.interfaces = interfaces
        self.isAbstract = isAbstract
        self.fields = fields
        self.methods = methods
        self.annotations = annotations
        self.document = document
        self.range = range
        self.nameRange = nameRange
    }

    /// The qualified name of the class.
    public var qualifiedName: String {
        packageName.map { "\($0).\(name)" } ?? name
    }
}

/// An expression with its source extent.
public struct XtendExpression: Sendable {
    /// What the expression is.
    public var kind: Kind

    /// The extent of the expression.
    public var range: SourceRange

    /// Creates an expression.
    ///
    /// - Parameters:
    ///   - kind: What the expression is.
    ///   - range: The extent of the expression.
    public init(_ kind: Kind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }

    /// The kinds of expression.
    public indirect enum Kind: Sendable {
        /// The literal `null`.
        case nullLiteral
        /// A Boolean literal.
        case booleanLiteral(Bool)
        /// A whole-number literal.
        case integerLiteral(Int)
        /// A floating point literal.
        case doubleLiteral(Double)
        /// A string literal.
        case stringLiteral(String)
        /// A rich string, already compiled into template instructions.
        case richString(XtendTemplate)
        /// A list literal `#[...]`.
        case listLiteral([XtendExpression])
        /// A set or map literal `#{...}`; it is a map if every element is a pair.
        case setLiteral([XtendExpression])
        /// A lambda expression; `explicitParameters` is `false` when the parameters are implicit.
        case lambda(parameters: [XtendParameter], explicitParameters: Bool, body: XtendExpression)
        /// A name without a receiver, with arguments if it is a call.
        case featureCall(name: String, arguments: [XtendExpression], explicitCall: Bool)
        /// A member access on a receiver.
        case memberCall(
            receiver: XtendExpression, name: String, arguments: [XtendExpression], explicitCall: Bool, nullSafe: Bool)
        /// A static member access `Type::member`.
        case staticCall(type: XtendTypeReference, name: String, arguments: [XtendExpression], explicitCall: Bool)
        /// An assignment `target = value`.
        case assignment(target: XtendExpression, value: XtendExpression)
        /// A compound assignment such as `target += value`.
        case compoundAssignment(operator: String, target: XtendExpression, value: XtendExpression)
        /// A binary operation.
        case binary(operator: String, left: XtendExpression, right: XtendExpression)
        /// A prefix operation (`!`, `-` or `+`).
        case unary(operator: String, operand: XtendExpression)
        /// A postfix increment or decrement.
        case postfix(operator: String, operand: XtendExpression)
        /// A type test `value instanceof Type`.
        case instanceOf(XtendExpression, XtendTypeReference)
        /// A cast `value as Type`.
        case cast(XtendExpression, XtendTypeReference)
        /// A conditional expression.
        case ifExpression(condition: XtendExpression, then: XtendExpression, otherwise: XtendExpression?)
        /// A switch expression.
        case switchExpression(XtendSwitch)
        /// A loop over the elements of a collection.
        case forEach(parameter: XtendParameter, iterable: XtendExpression, body: XtendExpression)
        /// A counting loop with initialisers, a condition and updates.
        case basicFor(
            initialisers: [XtendExpression], condition: XtendExpression?, updates: [XtendExpression],
            body: XtendExpression)
        /// A pre-tested loop.
        case whileLoop(condition: XtendExpression, body: XtendExpression)
        /// A post-tested loop.
        case doWhileLoop(body: XtendExpression, condition: XtendExpression)
        /// A block of expressions whose value is that of the last one.
        case block([XtendExpression])
        /// A local variable declaration.
        case variableDeclaration(
            name: String, type: XtendTypeReference?, isMutable: Bool, isExtension: Bool, initialiser: XtendExpression?)
        /// A return from the enclosing method or lambda expression.
        case returnExpression(XtendExpression?)
        /// A `throw` of an exception.
        case throwExpression(XtendExpression)
        /// A constructor call `new Type(arguments)`.
        case constructorCall(type: XtendTypeReference, arguments: [XtendExpression])
        /// A type literal `typeof(Type)`.
        case typeLiteral(XtendTypeReference)
        /// The receiver `this`.
        case this
        /// The superclass view `super`.
        case superReference
        /// A construct outside the subset; evaluating it fails.
        case unsupported(String)
    }
}

/// A switch expression.
public struct XtendSwitch: Sendable {
    /// The name declared for the switched value, as in `switch x : value`, if any.
    public var declaredName: String?

    /// The switched value.
    public var subject: XtendExpression

    /// The cases in order.
    public var cases: [XtendSwitchCase]

    /// The default branch, if any.
    public var defaultBranch: XtendExpression?

    /// Creates a switch expression.
    ///
    /// - Parameters:
    ///   - declaredName: The name declared for the switched value, if any.
    ///   - subject: The switched value.
    ///   - cases: The cases in order.
    ///   - defaultBranch: The default branch, if any.
    public init(declaredName: String?, subject: XtendExpression, cases: [XtendSwitchCase], defaultBranch: XtendExpression?) {
        self.declaredName = declaredName
        self.subject = subject
        self.cases = cases
        self.defaultBranch = defaultBranch
    }
}

/// A case of a switch expression.
///
/// A case matches if the switched value has the type guard's type (when given) and the case
/// expression (when given) either evaluates to `true` or equals the switched value. A case
/// without a body falls through to the body of the next case.
public struct XtendSwitchCase: Sendable {
    /// The type guard, if any.
    public var typeGuard: XtendTypeReference?

    /// The case expression, if any.
    public var condition: XtendExpression?

    /// The body, or `nil` if the case falls through.
    public var body: XtendExpression?

    /// The extent of the case.
    public var range: SourceRange

    /// Creates a case.
    ///
    /// - Parameters:
    ///   - typeGuard: The type guard, if any.
    ///   - condition: The case expression, if any.
    ///   - body: The body, or `nil` to fall through.
    ///   - range: The extent of the case.
    public init(typeGuard: XtendTypeReference?, condition: XtendExpression?, body: XtendExpression?, range: SourceRange) {
        self.typeGuard = typeGuard
        self.condition = condition
        self.body = body
        self.range = range
    }
}

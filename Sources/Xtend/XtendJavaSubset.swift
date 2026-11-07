//
//  XtendJavaSubset.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The built-in types that the interpreter knows without any metamodel.
///
/// Xtend programs refer to Java and Xtext library types. The interpreter does not load Java
/// classes: it maps the documented subset of type names onto these built-in kinds and
/// implements their behaviour natively. Any other Java type is reported with a diagnostic.
public enum XtendBuiltinType: String, CaseIterable, Sendable, Hashable {
    /// The root type `java.lang.Object`, which every value conforms to.
    case object = "Object"
    /// Character strings, including `CharSequence` and `char`.
    case string = "String"
    /// Whole numbers (`int`, `long`, `short`, `byte` and their wrappers).
    case integer = "Integer"
    /// Floating point numbers (`double`, `float` and their wrappers).
    case double = "Double"
    /// Any number.
    case number = "Number"
    /// Truth values.
    case boolean = "Boolean"
    /// Ordered collections that may contain duplicates.
    case list = "List"
    /// Collections without duplicates.
    case set = "Set"
    /// Maps from keys to values.
    case map = "Map"
    /// Any list or set.
    case collection = "Collection"
    /// Anything that can be iterated, including ranges.
    case iterable = "Iterable"
    /// A pair created with the `->` operator.
    case pair = "Pair"
    /// A range of whole numbers created with `..`, `..<` or `>..`.
    case integerRange = "IntegerRange"
    /// A lambda expression.
    case function = "Function"
    /// Any model object.
    case eObject = "EObject"
    /// An input or output model resource.
    case resource = "Resource"
    /// The file system access of a generator.
    case fileSystemAccess = "IFileSystemAccess"
    /// The context of a generator, which the interpreter passes as `null`.
    case generatorContext = "IGeneratorContext"
    /// The Xtext generator base classes, which a generator class may extend.
    case generator = "AbstractGenerator"
    /// A metamodel element with a name.
    case eNamedElement = "ENamedElement"
    /// A metamodel package.
    case ePackage = "EPackage"
    /// A metamodel classifier.
    case eClassifier = "EClassifier"
    /// A metamodel class.
    case eClass = "EClass"
    /// A metamodel data type.
    case eDataType = "EDataType"
    /// A metamodel enumeration.
    case eEnum = "EEnum"
    /// A literal of a metamodel enumeration.
    case eEnumLiteral = "EEnumLiteral"
    /// A structural feature of a metamodel class.
    case eStructuralFeature = "EStructuralFeature"
    /// An attribute of a metamodel class.
    case eAttribute = "EAttribute"
    /// A reference of a metamodel class.
    case eReference = "EReference"
    /// An exception that `throw` raises.
    case exception = "Exception"
    /// The absence of a value, as the result type of a procedure.
    case void = "void"

    /// The direct supertypes of this type within the built-in hierarchy.
    ///
    /// The hierarchy decides type guards, `instanceof` and the order of dispatch cases.
    public var supertypes: [XtendBuiltinType] {
        switch self {
        case .object: return []
        case .integer, .double: return [.number]
        case .list, .set: return [.collection]
        case .collection, .integerRange: return [.iterable]
        case .ePackage, .eClassifier, .eStructuralFeature, .eEnumLiteral: return [.eNamedElement]
        case .eNamedElement: return [.eObject]
        case .eClass, .eDataType: return [.eClassifier]
        case .eEnum: return [.eDataType]
        case .eAttribute, .eReference: return [.eStructuralFeature]
        default: return [.object]
        }
    }

    /// Whether this type is the given type or one of its subtypes.
    ///
    /// - Parameter other: The candidate supertype.
    /// - Returns: `true` if every value of this type is also a value of `other`.
    public func conforms(to other: XtendBuiltinType) -> Bool {
        if self == other || other == .object { return true }
        return supertypes.contains { $0.conforms(to: other) }
    }
}

/// The documented subset of Java and Xtext library types, members and constructors.
///
/// The interpreter runs Xtend without a Java virtual machine. Instead it implements the
/// types and members listed here natively. Imports, type references, constructor calls and
/// static member accesses outside this allow-list produce a diagnostic with the code
/// ``XtendDiagnosticCode/unsupportedJavaType``, ``XtendDiagnosticCode/unsupportedJavaImport``,
/// ``XtendDiagnosticCode/unsupportedJavaConstructor`` or
/// ``XtendDiagnosticCode/unsupportedJavaMember``.
public enum XtendJavaSubset {
    /// The type names, simple or qualified, that map onto built-in types.
    public static let typeNames: [String: XtendBuiltinType] = {
        var names: [String: XtendBuiltinType] = [:]
        /// Maps type names onto a built-in type.
        ///
        /// - Parameters:
        ///   - type: The built-in type.
        ///   - simple: The simple names of the type.
        ///   - package: The package that qualifies each simple name, if any.
        func add(_ type: XtendBuiltinType, _ simple: [String], package: String? = nil) {
            for name in simple {
                names[name] = type
                if let package { names["\(package).\(name)"] = type }
            }
        }
        add(.object, ["Object"], package: "java.lang")
        add(.string, ["String", "CharSequence", "Character", "StringConcatenation"], package: "java.lang")
        add(.string, ["char"])
        add(.integer, ["Integer", "Long", "Short", "Byte"], package: "java.lang")
        add(.integer, ["int", "long", "short", "byte"])
        add(.double, ["Double", "Float"], package: "java.lang")
        add(.double, ["double", "float"])
        add(.number, ["Number"], package: "java.lang")
        add(.boolean, ["Boolean"], package: "java.lang")
        add(.boolean, ["boolean"])
        add(.void, ["Void"], package: "java.lang")
        add(.void, ["void"])
        add(.iterable, ["Iterable"], package: "java.lang")
        add(.list, ["List", "ArrayList", "LinkedList"], package: "java.util")
        add(.set, ["Set", "HashSet", "LinkedHashSet", "TreeSet"], package: "java.util")
        add(.map, ["Map", "HashMap", "LinkedHashMap", "TreeMap"], package: "java.util")
        add(.collection, ["Collection"], package: "java.util")
        add(.iterable, ["Iterator"], package: "java.util")
        add(.list, ["EList"], package: "org.eclipse.emf.common.util")
        add(.iterable, ["TreeIterator"], package: "org.eclipse.emf.common.util")
        add(.pair, ["Pair"], package: "org.eclipse.xtext.xbase.lib")
        add(.integerRange, ["IntegerRange", "ExclusiveRange"], package: "org.eclipse.xtext.xbase.lib")
        add(.function, ["Function0", "Function1", "Function2", "Function3"], package: "org.eclipse.xtext.xbase.lib.Functions")
        add(.function, ["Procedure0", "Procedure1", "Procedure2", "Procedure3"], package: "org.eclipse.xtext.xbase.lib.Procedures")
        add(.eObject, ["EObject"], package: "org.eclipse.emf.ecore")
        add(.eNamedElement, ["ENamedElement"], package: "org.eclipse.emf.ecore")
        add(.ePackage, ["EPackage"], package: "org.eclipse.emf.ecore")
        add(.eClassifier, ["EClassifier"], package: "org.eclipse.emf.ecore")
        add(.eClass, ["EClass"], package: "org.eclipse.emf.ecore")
        add(.eDataType, ["EDataType"], package: "org.eclipse.emf.ecore")
        add(.eEnum, ["EEnum"], package: "org.eclipse.emf.ecore")
        add(.eEnumLiteral, ["EEnumLiteral"], package: "org.eclipse.emf.ecore")
        add(.eStructuralFeature, ["EStructuralFeature"], package: "org.eclipse.emf.ecore")
        add(.eAttribute, ["EAttribute"], package: "org.eclipse.emf.ecore")
        add(.eReference, ["EReference"], package: "org.eclipse.emf.ecore")
        add(.resource, ["Resource"], package: "org.eclipse.emf.ecore.resource")
        add(.fileSystemAccess, ["IFileSystemAccess", "IFileSystemAccess2"], package: "org.eclipse.xtext.generator")
        add(.generatorContext, ["IGeneratorContext"], package: "org.eclipse.xtext.generator")
        add(.generator, ["AbstractGenerator", "IGenerator", "IGenerator2"], package: "org.eclipse.xtext.generator")
        add(
            .exception,
            [
                "Exception", "RuntimeException", "IllegalArgumentException", "IllegalStateException",
                "UnsupportedOperationException", "NullPointerException", "IndexOutOfBoundsException",
            ], package: "java.lang")
        return names
    }()

    /// The packages whose members may be imported with a wildcard or as static extensions.
    ///
    /// Their members are either built in or provided natively by the interpreter's library.
    public static let importablePackages: Set<String> = [
        "java.util", "java.lang", "org.eclipse.xtext.xbase.lib", "org.eclipse.emf.ecore",
        "org.eclipse.emf.ecore.resource", "org.eclipse.xtext.generator", "org.eclipse.emf.common.util",
    ]

    /// The library classes whose static methods the interpreter provides natively.
    ///
    /// Importing one of these, for example with `import static extension`, has no effect
    /// because their methods are always available.
    public static let libraryClasses: Set<String> = [
        "org.eclipse.xtext.xbase.lib.IterableExtensions", "org.eclipse.xtext.xbase.lib.ListExtensions",
        "org.eclipse.xtext.xbase.lib.StringExtensions", "org.eclipse.xtext.xbase.lib.CollectionLiterals",
        "org.eclipse.xtext.xbase.lib.CollectionExtensions", "org.eclipse.xtext.xbase.lib.MapExtensions",
        "org.eclipse.xtext.xbase.lib.InputOutput", "org.eclipse.xtext.xbase.lib.ObjectExtensions",
        "org.eclipse.xtext.xbase.lib.IteratorExtensions",
    ]

    /// The built-in types that `new` may instantiate.
    public static let constructibleTypes: Set<XtendBuiltinType> = [.list, .set, .map, .exception, .object]

    /// The static members that `Type::member` may access, keyed by the simple type name.
    public static let staticMembers: [String: Set<String>] = [
        "String": ["valueOf", "join"],
        "Integer": ["parseInt", "valueOf", "toString", "MAX_VALUE", "MIN_VALUE"],
        "Long": ["parseLong", "valueOf", "MAX_VALUE", "MIN_VALUE"],
        "Double": ["parseDouble", "valueOf"],
        "Boolean": ["parseBoolean", "valueOf"],
        "Math": ["max", "min", "abs", "floor", "ceil", "round", "sqrt", "pow"],
    ]

    /// The members of strings that the interpreter implements.
    public static let stringMembers: Set<String> = [
        "length", "isEmpty", "charAt", "substring", "indexOf", "lastIndexOf", "contains", "startsWith",
        "endsWith", "toUpperCase", "toLowerCase", "trim", "strip", "isBlank", "replace", "replaceAll", "split",
        "equals", "equalsIgnoreCase", "compareTo", "concat", "matches", "repeat", "toString", "hashCode",
        "toCharArray", "lines",
    ]

    /// The members of lists and sets that the interpreter implements.
    public static let collectionMembers: Set<String> = [
        "size", "isEmpty", "contains", "containsAll", "add", "addAll", "remove", "removeAll", "clear",
        "get", "set", "indexOf", "lastIndexOf", "subList", "toString", "equals", "hashCode",
    ]

    /// The members of maps that the interpreter implements.
    public static let mapMembers: Set<String> = [
        "size", "isEmpty", "get", "put", "putAll", "remove", "containsKey", "containsValue", "keySet",
        "values", "entrySet", "getOrDefault", "clear", "toString", "equals", "hashCode",
    ]

    /// The members of pairs and map entries that the interpreter implements.
    public static let pairMembers: Set<String> = ["key", "value", "getKey", "getValue", "toString", "equals"]

    /// The members of numbers and Booleans that the interpreter implements.
    public static let valueMembers: Set<String> = [
        "intValue", "longValue", "doubleValue", "floatValue", "booleanValue", "compareTo", "toString", "equals",
        "hashCode",
    ]

    /// The members of lambda expressions that the interpreter implements.
    public static let functionMembers: Set<String> = ["apply"]

    /// The members of exceptions that the interpreter implements.
    public static let exceptionMembers: Set<String> = ["getMessage", "toString"]

    /// The members of model objects that the interpreter implements besides their features.
    public static let eObjectMembers: Set<String> = [
        "eClass", "eContainer", "eContents", "eAllContents", "eResource", "eContainingFeature", "eGet",
        "eIsSet", "eSet", "toString", "equals", "hashCode",
    ]

    /// The members of resources that the interpreter implements.
    public static let resourceMembers: Set<String> = ["contents", "allContents", "URI", "uri"]

    /// The members of file system accesses that the interpreter implements.
    public static let fileSystemAccessMembers: Set<String> = ["generateFile"]

    /// Resolves a type name against the allow-list.
    ///
    /// - Parameter name: A simple or qualified type name, without type arguments.
    /// - Returns: The built-in type, or `nil` if the name is not part of the subset.
    public static func builtinType(named name: String) -> XtendBuiltinType? {
        typeNames[name]
    }
}

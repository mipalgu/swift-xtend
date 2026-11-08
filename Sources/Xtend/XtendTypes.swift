//
//  XtendTypes.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore

/// A type that the interpreter can test values against.
///
/// Type references in the source resolve to one of these: a built-in type of the Java
/// subset, a class or enumeration of a registered metamodel, or a class of the compilation
/// set. Type guards, `instanceof`, casts, `filter(Type)` and the selection of dispatch cases
/// all work with these types at runtime.
public enum XtendRuntimeType: Sendable {
    /// A built-in type of the Java subset.
    case builtin(XtendBuiltinType)
    /// A class of a registered metamodel.
    case modelClass(EClass)
    /// An enumeration of a registered metamodel, whose values are literal names.
    case modelEnum(EEnum)
    /// A class of the compilation set, by qualified name.
    case xtendClass(String)

    /// The name of the type as it is shown in messages.
    public var name: String {
        switch self {
        case .builtin(let type): return type.rawValue
        case .modelClass(let eClass): return eClass.name
        case .modelEnum(let eEnum): return eEnum.name
        case .xtendClass(let name): return name
        }
    }
}

/// Resolves type references against the compilation set, the metamodels and the Java subset.
struct XtendTypeResolver: Sendable {
    /// The classifiers of the registered metamodels by simple and qualified name.
    private let classifiers: [String: any EClassifier]

    /// The qualified names of the packages of the registered metamodels, with their prefixes.
    let packageNames: Set<String>

    /// The superclass of each class of the compilation set, by qualified name.
    let superclasses: [String: String]

    /// The qualified names of the classes of the compilation set, by simple and qualified name.
    private let classNames: [String: String]

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - metamodels: The registered metamodels.
    ///   - classNames: The qualified class names by simple and qualified name.
    ///   - superclasses: The qualified superclass of each class.
    init(metamodels: [EPackage], classNames: [String: String], superclasses: [String: String]) {
        var classifiers: [String: any EClassifier] = [:]
        var packageNames: Set<String> = []
        /// Records a package, its subpackages and their classifiers.
        ///
        /// - Parameters:
        ///   - package: The package to record.
        ///   - prefix: The qualified name of the enclosing package, if any.
        func register(_ package: EPackage, prefix: String?) {
            let qualified = prefix.map { "\($0).\(package.name)" } ?? package.name
            packageNames.insert(qualified)
            packageNames.insert(package.name)
            if !package.nsPrefix.isEmpty { packageNames.insert(package.nsPrefix) }
            for classifier in package.eClassifiers {
                if classifiers[classifier.name] == nil { classifiers[classifier.name] = classifier }
                classifiers["\(qualified).\(classifier.name)"] = classifier
                classifiers["\(package.name).\(classifier.name)"] = classifier
            }
            for subpackage in package.eSubpackages { register(subpackage, prefix: qualified) }
        }
        for package in metamodels { register(package, prefix: nil) }
        self.classifiers = classifiers
        self.packageNames = packageNames
        self.superclasses = superclasses
        self.classNames = classNames
    }

    /// The qualified name of a class of the compilation set.
    ///
    /// - Parameter name: A simple or qualified class name.
    /// - Returns: The qualified name, or `nil` if the compilation set has no such class.
    func className(_ name: String) -> String? {
        classNames[name]
    }

    /// Whether a qualified name denotes a classifier of a registered metamodel.
    func isClassifier(_ name: String) -> Bool { classifiers[name] != nil }

    /// Resolves a type name.
    ///
    /// Names imported explicitly take precedence; otherwise classes of the compilation set,
    /// the built-in types and the metamodel classifiers are tried in that order.
    ///
    /// - Parameters:
    ///   - name: A simple or qualified type name.
    ///   - imports: The imports of the file that contains the reference.
    /// - Returns: The type, or `nil` if the name is unknown.
    func resolve(name: String, imports: [XtendImport] = []) -> XtendRuntimeType? {
        if !name.contains("."), let imported = imports.first(where: { !$0.isStatic && !$0.isWildcard && $0.simpleName == name }),
            imported.name != name, let type = resolve(name: imported.name, imports: [])
        {
            return type
        }
        if let qualified = classNames[name] { return .xtendClass(qualified) }
        if let builtin = XtendJavaSubset.builtinType(named: name) { return .builtin(builtin) }
        if let classifier = classifiers[name] { return Self.type(of: classifier) }
        for item in imports where item.isWildcard && !item.isStatic {
            if let classifier = classifiers["\(item.name).\(name)"] { return Self.type(of: classifier) }
            if let qualified = classNames["\(item.name).\(name)"] { return .xtendClass(qualified) }
        }
        return nil
    }

    /// Resolves a type reference.
    ///
    /// - Parameters:
    ///   - reference: The reference as written.
    ///   - imports: The imports of the file that contains the reference.
    /// - Returns: The type, or `nil` if the name is unknown.
    func resolve(_ reference: XtendTypeReference, imports: [XtendImport] = []) -> XtendRuntimeType? {
        if reference.isFunctionType { return .builtin(.function) }
        if reference.arrayDimensions > 0 { return .builtin(.list) }
        return resolve(name: reference.name, imports: imports)
    }

    /// The runtime type of a metamodel classifier.
    static func type(of classifier: any EClassifier) -> XtendRuntimeType {
        if let eClass = classifier as? EClass { return .modelClass(eClass) }
        if let eEnum = classifier as? EEnum { return .modelEnum(eEnum) }
        switch classifier.name {
        case "EString", "EChar", "ECharacterObject": return .builtin(.string)
        case "EInt", "EIntegerObject", "ELong", "ELongObject", "EShort", "EShortObject", "EByte", "EByteObject",
            "EBigInteger":
            return .builtin(.integer)
        case "EDouble", "EDoubleObject", "EFloat", "EFloatObject", "EBigDecimal": return .builtin(.double)
        case "EBoolean", "EBooleanObject": return .builtin(.boolean)
        default: return .builtin(.object)
        }
    }

    /// Whether a class of the compilation set is the given class or inherits from it.
    ///
    /// - Parameters:
    ///   - name: The qualified name of the class.
    ///   - ancestor: The qualified name of the candidate ancestor.
    /// - Returns: `true` if `name` is `ancestor` or one of its subclasses.
    func isClass(_ name: String, subclassOf ancestor: String) -> Bool {
        var current: String? = name
        var visited: Set<String> = []
        while let candidate = current, visited.insert(candidate).inserted {
            if candidate == ancestor { return true }
            current = superclasses[candidate]
        }
        return false
    }

    /// Whether every value of one type is also a value of another.
    ///
    /// The relation orders dispatch cases from the most to the least specific.
    ///
    /// - Parameters:
    ///   - type: The candidate subtype.
    ///   - other: The candidate supertype.
    /// - Returns: `true` if `type` conforms to `other`.
    func isSubtype(_ type: XtendRuntimeType, of other: XtendRuntimeType) -> Bool {
        switch (type, other) {
        case (_, .builtin(.object)): return true
        case (.builtin(let lhs), .builtin(let rhs)): return lhs.conforms(to: rhs)
        case (.modelClass(let lhs), .modelClass(let rhs)): return Self.eClass(lhs, conformsTo: rhs)
        case (.modelClass, .builtin(let rhs)): return XtendBuiltinType.eObject.conforms(to: rhs)
        case (.modelEnum(let lhs), .modelEnum(let rhs)): return lhs.name == rhs.name
        case (.modelEnum, .builtin(let rhs)): return XtendBuiltinType.string.conforms(to: rhs)
        case (.xtendClass(let lhs), .xtendClass(let rhs)): return isClass(lhs, subclassOf: rhs)
        default: return false
        }
    }

    /// Whether a metamodel class is another class or one of its subclasses.
    static func eClass(_ eClass: EClass, conformsTo other: EClass) -> Bool {
        if eClass.id == other.id || eClass.name == other.name { return true }
        return eClass.allSuperTypes.contains { $0.id == other.id || $0.name == other.name }
    }
}

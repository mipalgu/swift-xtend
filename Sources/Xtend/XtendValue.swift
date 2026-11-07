//
//  XtendValue.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase

/// A value during interpretation.
///
/// Values live inside an ``XtendInterpreter``. Collections, maps, class instances and lambda
/// expressions are reference types, as in Java, so that changes made through one reference
/// are visible through all others. Values cross the boundary of the interpreter as
/// ``XtendHostValue``.
enum XtendValue {
    /// The absent value.
    case null
    /// A truth value.
    case bool(Bool)
    /// A whole number.
    case int(Int)
    /// A floating point number.
    case double(Double)
    /// A character string.
    case string(String)
    /// A list or set.
    case collection(XtendCollection)
    /// A map.
    case map(XtendMap)
    /// A pair created with `->`, or a map entry.
    case pair(XtendPair)
    /// A range of whole numbers.
    case range(XtendRange)
    /// A model object or metamodel element.
    case object(XtendObjectReference)
    /// An instance of a class of the compilation set.
    case instance(XtendInstance)
    /// A lambda expression with its captured scope.
    case lambda(XtendLambda)
    /// A type used as a value, as in `filter(Person)` or `typeof(Person)`.
    case type(XtendRuntimeType)
    /// A model resource.
    case resource(Resource)
    /// A file system access of a generator.
    case fileSystem(any XtendFileSystemAccess)
    /// An exception created with `new`, with its type name and message.
    case exception(String, String?)

    /// Whether this is the absent value.
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The built-in kind of the value, used for type tests and messages.
    var builtinKind: XtendBuiltinType {
        switch self {
        case .null: return .void
        case .bool: return .boolean
        case .int: return .integer
        case .double: return .double
        case .string: return .string
        case .collection(let collection): return collection.isSet ? .set : .list
        case .map: return .map
        case .pair: return .pair
        case .range: return .integerRange
        case .object(let reference): return reference.metaKind ?? .eObject
        case .instance, .type: return .object
        case .lambda: return .function
        case .resource: return .resource
        case .fileSystem: return .fileSystemAccess
        case .exception: return .exception
        }
    }

    /// A short description of the kind of value, for messages.
    var typeDescription: String {
        switch self {
        case .object(let reference): return reference.eClass?.name ?? reference.metaKind?.rawValue ?? "EObject"
        case .instance(let instance): return instance.className
        case .exception(let name, _): return name
        default: return builtinKind.rawValue
        }
    }

    /// The key that identifies the value in sets and maps and decides equality.
    var key: XtendKey {
        switch self {
        case .null: return .null
        case .bool(let value): return .bool(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .string(let value): return .string(value)
        case .collection(let collection):
            return collection.isSet ? .set(Set(collection.elements.map(\.key))) : .sequence(collection.elements.map(\.key))
        case .map(let map):
            return .set(Set(zip(map.keys, map.values).map { XtendKey.pair($0.key, $1.key) }))
        case .pair(let pair): return .pair(pair.key.key, pair.value.key)
        case .range(let range): return .sequence(range.elements.map { .int($0) })
        case .object(let reference): return .object(reference.id)
        case .instance(let instance): return .instance(instance.serial)
        case .lambda(let lambda): return .identity(ObjectIdentifier(lambda))
        case .type(let type): return .type(type.name)
        case .resource(let resource): return .type(resource.uri)
        case .fileSystem: return .type(XtendBuiltinType.fileSystemAccess.rawValue)
        case .exception(let name, let message): return .sequence([.string(name), .string(message ?? "")])
        }
    }

    /// Whether two values are equal in the sense of Java's `equals`, with numeric comparison
    /// of mixed whole and floating point numbers.
    static func areEqual(_ lhs: XtendValue, _ rhs: XtendValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let left), .double(let right)): return Double(left) == right
        case (.double(let left), .int(let right)): return left == Double(right)
        default: return lhs.key == rhs.key
        }
    }

    /// Whether two values are the same object in the sense of Java's `==` on references.
    static func areIdentical(_ lhs: XtendValue, _ rhs: XtendValue) -> Bool {
        switch (lhs, rhs) {
        case (.collection(let left), .collection(let right)): return left === right
        case (.map(let left), .map(let right)): return left === right
        case (.pair(let left), .pair(let right)): return left === right
        default: return areEqual(lhs, rhs)
        }
    }
}

/// A hashable identity of a value, used for sets, map keys, equality and caching.
indirect enum XtendKey: Hashable {
    /// The null value.
    case null
    /// A boolean value.
    case bool(Bool)
    /// An integer value.
    case int(Int)
    /// A floating-point value.
    case double(Double)
    /// A string value.
    case string(String)
    /// A model object, identified by its unique identifier.
    case object(EUUID)
    /// An Xtend instance or lambda, identified by object identity.
    case identity(ObjectIdentifier)
    /// An instance of a class of the compilation set, by its serial number.
    case instance(Int)
    /// An ordered sequence of keys.
    case sequence([XtendKey])
    /// An unordered set of keys.
    case set(Set<XtendKey>)
    /// A pair of keys.
    case pair(XtendKey, XtendKey)
    /// A type, identified by name.
    case type(String)
}

/// A reference to a model object or metamodel element.
///
/// Model objects are value types held by resources, so a reference records the identifier
/// and the resource and looks the object up whenever it is read. The class of an object
/// never changes, so it is recorded in the reference for fast type tests.
struct XtendObjectReference: Sendable {
    /// The identifier of the object.
    let id: EUUID

    /// The resource that holds the object, if any.
    let resource: Resource?

    /// The class of a dynamic model object.
    let eClass: EClass?

    /// The built-in kind of a native metamodel element, such as ``XtendBuiltinType/eClass``.
    let metaKind: XtendBuiltinType?

    /// The object itself, for objects that no resource holds.
    let snapshot: (any EObject)?
}

/// A list or set with Java reference semantics.
final class XtendCollection {
    /// The elements in order.
    var elements: [XtendValue]

    /// Whether the collection rejects duplicates.
    let isSet: Bool

    /// Whether the collection may be changed.
    let isMutable: Bool

    /// The keys of the elements of a set.
    private var keys: Set<XtendKey>

    /// The model feature that the collection mirrors, if it was read from one.
    var binding: XtendFeatureBinding?

    /// Creates a collection.
    ///
    /// - Parameters:
    ///   - elements: The elements; duplicates are dropped from sets.
    ///   - isSet: Whether the collection rejects duplicates.
    ///   - isMutable: Whether the collection may be changed.
    init(_ elements: [XtendValue], isSet: Bool = false, isMutable: Bool = true) {
        self.isSet = isSet
        self.isMutable = isMutable
        self.elements = []
        self.keys = []
        for element in elements { _ = insert(element) }
    }

    /// Adds an element at the end, unless a set already holds it.
    ///
    /// - Parameter element: The element to add.
    /// - Returns: Whether the collection changed.
    @discardableResult
    func insert(_ element: XtendValue) -> Bool {
        if isSet {
            guard keys.insert(element.key).inserted else { return false }
        }
        elements.append(element)
        return true
    }

    /// Inserts an element at a position.
    ///
    /// - Parameters:
    ///   - element: The element to insert.
    ///   - index: The position.
    func insert(_ element: XtendValue, at index: Int) {
        if isSet {
            guard keys.insert(element.key).inserted else { return }
        }
        elements.insert(element, at: index)
    }

    /// Removes the first element equal to a value.
    ///
    /// - Parameter element: The value to remove.
    /// - Returns: Whether the collection changed.
    @discardableResult
    func remove(_ element: XtendValue) -> Bool {
        guard let index = elements.firstIndex(where: { XtendValue.areEqual($0, element) }) else { return false }
        remove(at: index)
        return true
    }

    /// Removes the element at a position.
    ///
    /// - Parameter index: The position.
    /// - Returns: The removed element.
    @discardableResult
    func remove(at index: Int) -> XtendValue {
        let element = elements.remove(at: index)
        if isSet { keys.remove(element.key) }
        return element
    }

    /// Replaces all elements.
    ///
    /// - Parameter elements: The new elements.
    func replaceAll(_ elements: [XtendValue]) {
        self.elements = []
        keys = []
        for element in elements { insert(element) }
    }

    /// Whether the collection holds a value equal to the given one.
    func contains(_ element: XtendValue) -> Bool {
        if isSet { return keys.contains(element.key) }
        return elements.contains { XtendValue.areEqual($0, element) }
    }
}

/// The model feature that a collection was read from, so that changes can be written back.
struct XtendFeatureBinding {
    /// The object that owns the feature.
    let owner: XtendObjectReference
    /// The name of the many-valued feature.
    let feature: String
}

/// A map with Java reference semantics that keeps its insertion order.
final class XtendMap {
    /// The keys in insertion order.
    private(set) var keys: [XtendValue] = []

    /// The values, parallel to ``keys``.
    private(set) var values: [XtendValue] = []

    /// The position of each key.
    private var index: [XtendKey: Int] = [:]

    /// Whether the map may be changed.
    let isMutable: Bool

    /// Creates a map.
    ///
    /// - Parameters:
    ///   - entries: The entries in order; later entries replace earlier ones with equal keys.
    ///   - isMutable: Whether the map may be changed.
    init(_ entries: [(XtendValue, XtendValue)] = [], isMutable: Bool = true) {
        self.isMutable = isMutable
        for (key, value) in entries { put(key, value) }
    }

    /// The value for a key.
    func get(_ key: XtendValue) -> XtendValue? {
        index[key.key].map { values[$0] }
    }

    /// Stores a value for a key.
    ///
    /// - Returns: The previous value, if any.
    @discardableResult
    func put(_ key: XtendValue, _ value: XtendValue) -> XtendValue? {
        if let position = index[key.key] {
            let previous = values[position]
            values[position] = value
            return previous
        }
        index[key.key] = keys.count
        keys.append(key)
        values.append(value)
        return nil
    }

    /// Removes the entry for a key.
    ///
    /// - Returns: The removed value, if any.
    @discardableResult
    func remove(_ key: XtendValue) -> XtendValue? {
        guard let position = index[key.key] else { return nil }
        let value = values[position]
        keys.remove(at: position)
        values.remove(at: position)
        index = [:]
        for (offset, key) in keys.enumerated() { index[key.key] = offset }
        return value
    }

    /// Removes all entries.
    func removeAll() {
        keys = []
        values = []
        index = [:]
    }

    /// The number of entries.
    var count: Int { keys.count }
}

/// A pair of values, as created by the `->` operator.
final class XtendPair {
    /// The first value.
    let key: XtendValue
    /// The second value.
    let value: XtendValue

    /// Creates a pair.
    init(_ key: XtendValue, _ value: XtendValue) {
        self.key = key
        self.value = value
    }
}

/// A range of whole numbers.
struct XtendRange {
    /// The first number.
    let start: Int
    /// The number after which (or before which, when counting down) the range ends.
    let end: Int
    /// Whether ``end`` belongs to the range.
    let isInclusive: Bool
    /// Whether the range counts down.
    let isDescending: Bool

    /// The numbers of the range in order.
    var elements: [Int] {
        if isDescending {
            let last = isInclusive ? end : end + 1
            return start >= last ? Array(stride(from: start, through: last, by: -1)) : []
        }
        let last = isInclusive ? end : end - 1
        return start <= last ? Array(start...last) : []
    }
}

/// An instance of a class of the compilation set.
final class XtendInstance {
    /// The qualified name of the class.
    let className: String
    /// The number that identifies the instance for the lifetime of its interpreter.
    let serial: Int
    /// The values of the fields.
    var fields: [String: XtendValue] = [:]

    /// Creates an instance without field values.
    ///
    /// - Parameters:
    ///   - className: The qualified name of the class.
    ///   - serial: The number that identifies the instance.
    init(className: String, serial: Int) {
        self.className = className
        self.serial = serial
    }
}

/// A lambda expression with the scope it was created in.
final class XtendLambda {
    /// The declared parameters.
    let parameters: [XtendParameter]
    /// Whether the parameters were declared explicitly.
    let explicitParameters: Bool
    /// The body.
    let body: XtendExpression
    /// The context the lambda captures.
    let context: XtendContext

    /// Creates a lambda.
    init(parameters: [XtendParameter], explicitParameters: Bool, body: XtendExpression, context: XtendContext) {
        self.parameters = parameters
        self.explicitParameters = explicitParameters
        self.body = body
        self.context = context
    }
}

/// A variable binding.
struct XtendVariable {
    /// The current value.
    var value: XtendValue
    /// Whether the variable may be reassigned.
    let isMutable: Bool
    /// Whether the variable provides extension methods.
    let isExtension: Bool
}

/// A lexical scope of variables.
final class XtendScope {
    /// The variables declared directly in this scope.
    private var variables: [String: XtendVariable] = [:]
    /// The enclosing scope.
    let parent: XtendScope?

    /// Creates a scope.
    init(parent: XtendScope? = nil) {
        self.parent = parent
    }

    /// Declares a variable in this scope.
    func declare(_ name: String, _ value: XtendValue, isMutable: Bool = false, isExtension: Bool = false) {
        variables[name] = XtendVariable(value: value, isMutable: isMutable, isExtension: isExtension)
    }

    /// Looks a variable up in this scope and its enclosing scopes.
    func lookup(_ name: String) -> XtendVariable? {
        var scope: XtendScope? = self
        while let current = scope {
            if let variable = current.variables[name] { return variable }
            scope = current.parent
        }
        return nil
    }

    /// Changes the value of a variable in the scope that declares it.
    ///
    /// - Returns: `false` if no scope declares the variable.
    func assign(_ name: String, _ value: XtendValue) -> Bool {
        var scope: XtendScope? = self
        while let current = scope {
            if current.variables[name] != nil {
                current.variables[name]?.value = value
                return true
            }
            scope = current.parent
        }
        return false
    }

    /// The values of the extension variables visible from this scope, innermost first.
    var extensionValues: [XtendValue] {
        var result: [XtendValue] = []
        var scope: XtendScope? = self
        while let current = scope {
            result.append(contentsOf: current.variables.values.filter(\.isExtension).map(\.value))
            scope = current.parent
        }
        return result
    }
}

/// The context in which an expression is evaluated.
struct XtendContext {
    /// The innermost scope.
    let scope: XtendScope
    /// The receiver of instance members, or `nil` in a static method.
    let this: XtendInstance?
    /// The qualified name of the class whose code is running.
    let className: String?

    /// A context with a new nested scope.
    func nested() -> XtendContext {
        XtendContext(scope: XtendScope(parent: scope), this: this, className: className)
    }
}

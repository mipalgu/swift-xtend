//
//  XtendInterpreter.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
import EMFBase

/// Limits that keep interpretation of untrusted programs bounded.
public struct XtendOptions: Sendable, Hashable {
    /// The deepest nesting of method and lambda calls before evaluation fails with
    /// ``XtendDiagnosticCode/recursionLimit``.
    public var maximumCallDepth: Int

    /// The number of evaluation steps after which evaluation fails with
    /// ``XtendDiagnosticCode/stepLimit``, or `nil` for no limit.
    public var maximumSteps: Int?

    /// Creates options.
    ///
    /// - Parameters:
    ///   - maximumCallDepth: The deepest nesting of calls (default 200).
    ///   - maximumSteps: The number of evaluation steps allowed (default ten million).
    public init(maximumCallDepth: Int = 200, maximumSteps: Int? = 10_000_000) {
        self.maximumCallDepth = maximumCallDepth
        self.maximumSteps = maximumSteps
    }
}

/// The signal that unwinds evaluation to the enclosing method or lambda on `return`.
struct XtendReturnSignal: Error {}

/// Interprets the classes of an ``XtendProgram`` over Ecore models.
///
/// The interpreter instantiates classes of the compilation set, invokes their methods with
/// runtime dispatch, evaluates rich strings with Xtend's whitespace rules, navigates and
/// changes model objects held by `Resource`s, and writes generated files through an
/// ``XtendFileSystemAccess``.
///
/// ```swift
/// let program = XtendProgram(source, metamodels: [package])
/// let interpreter = try XtendInterpreter(program: program, resources: [model])
/// let files = XtendInMemoryFileSystemAccess()
/// try await interpreter.generate(resource: model, fileSystem: files)
/// ```
///
/// Model objects created with `new` (for a metamodel class) are added to
/// ``targetResource``. Results of create methods are cached per receiver and arguments.
public actor XtendInterpreter {
    /// The program being interpreted.
    public nonisolated let program: XtendProgram

    /// The resource that receives the model objects that the program creates.
    public nonisolated let targetResource: Resource

    /// The limits of evaluation.
    public nonisolated let options: XtendOptions

    /// The resources whose objects the program can reach.
    var resources: [Resource]

    /// The text written with `print` and `println`.
    var outputText = ""

    /// The results of create methods by method and arguments.
    var createCaches: [String: [XtendKey: XtendValue]] = [:]

    /// The values of static fields by class and field name.
    var staticFields: [String: [String: XtendValue]] = [:]

    /// The value of the `return` that is unwinding.
    var returnValue: XtendValue = .null

    /// The current nesting of calls.
    var depth = 0

    /// The number of evaluation steps so far.
    var steps = 0

    /// The number of class instances created so far, which numbers each new instance.
    var instanceCount = 0

    /// The URI of the target resource that the interpreter creates when none is given.
    public static let defaultTargetURI = "xtend:target"

    /// Creates an interpreter.
    ///
    /// - Parameters:
    ///   - program: The program to interpret; it must not have errors.
    ///   - resources: The resources whose objects the program can reach.
    ///   - targetResource: The resource that receives created objects; a new empty resource
    ///     is used if it is `nil`.
    ///   - options: The limits of evaluation.
    /// - Throws: ``XtendError`` with the program's errors if the program has errors.
    public init(
        program: XtendProgram, resources: [Resource] = [], targetResource: Resource? = nil,
        options: XtendOptions = XtendOptions()
    ) throws {
        guard !program.hasErrors else { throw XtendError(diagnostics: program.errors) }
        self.program = program
        let target = targetResource ?? Resource(uri: Self.defaultTargetURI)
        self.targetResource = target
        self.options = options
        self.resources = resources.contains { $0 === target } ? resources : resources + [target]
    }

    /// The text that the program wrote with `print` and `println`.
    public var standardOutput: String { outputText }

    /// Makes the objects of another resource reachable.
    ///
    /// - Parameter resource: The resource to add.
    public func addResource(_ resource: Resource) {
        if !resources.contains(where: { $0 === resource }) { resources.append(resource) }
    }

    // MARK: - Public entry points

    /// Creates an instance of a class and calls one of its methods.
    ///
    /// - Parameters:
    ///   - method: The name of the method.
    ///   - className: The simple or qualified name of the class.
    ///   - arguments: The arguments.
    /// - Returns: The result of the method.
    /// - Throws: ``XtendError`` if the class or method does not exist or evaluation fails.
    public func call(_ method: String, of className: String, arguments: [XtendHostValue] = []) async throws -> XtendHostValue {
        guard let info = program.classInfo(className) else {
            throw XtendError(.unknownClass, "The compilation set declares no class '\(className)'")
        }
        let instance = try await instantiate(info.declaration.qualifiedName, arguments: [], range: info.declaration.nameRange)
        var values: [XtendValue] = []
        for argument in arguments { values.append(await value(of: argument)) }
        guard
            let result = try await callClassMethod(
                method, arguments: values, this: instance, className: instance.className, range: info.declaration.nameRange)
        else {
            throw XtendError(
                .unknownFeature, "The class '\(className)' has no method '\(method)' for \(values.count) argument(s)",
                range: info.declaration.nameRange, document: info.declaration.document)
        }
        return await hostValue(of: result)
    }

    /// Runs a generator over a resource.
    ///
    /// The generator is the named class or else the first class that is not abstract and has
    /// a method named after one of ``XtendLanguage/generatorMethodNames`` that takes the
    /// resource and the file system access, optionally followed by a generator context, which
    /// is passed as `null` (see ``XtendProgram/generatorClass(named:)``).
    ///
    /// - Parameters:
    ///   - resource: The input resource.
    ///   - fileSystem: The file system access that receives the generated files.
    ///   - className: The simple or qualified name of the generator class, or `nil` to find it.
    /// - Throws: ``XtendError`` if no generator is found or evaluation fails.
    public func generate(resource: Resource, fileSystem: any XtendFileSystemAccess, className: String? = nil) async throws {
        addResource(resource)
        guard let entry = program.generatorEntry(className: className), let info = program.classes[entry.className] else {
            throw XtendError(
                .unknownFeature,
                "No generator class with a method \(XtendLanguage.generatorMethodNames.joined(separator: " or "))(resource, fsa) was found")
        }
        let instance = try await instantiate(entry.className, arguments: [], range: info.declaration.nameRange)
        var arguments: [XtendValue] = [.resource(resource), .fileSystem(fileSystem)]
        if entry.arity > arguments.count { arguments.append(.null) }
        _ = try await callClassMethod(
            entry.methodName, arguments: arguments, this: instance, className: instance.className,
            range: info.declaration.nameRange)
    }

    /// Evaluates a standalone expression.
    ///
    /// The expression can use the given variables, the library functions and the types of
    /// the program, but no instance members.
    ///
    /// - Parameters:
    ///   - expression: The source text of the expression.
    ///   - variables: The variables visible to the expression.
    /// - Returns: The value of the expression.
    /// - Throws: ``XtendError`` if the expression cannot be parsed or evaluation fails.
    public func evaluate(_ expression: String, variables: [String: XtendHostValue] = [:]) async throws -> XtendHostValue {
        let (parsed, diagnostics) = XtendParser.parseExpression(expression, document: Self.expressionDocument)
        guard let parsed, !diagnostics.contains(where: { $0.severity == .error }) else {
            throw XtendError(diagnostics: diagnostics.filter { $0.severity == .error })
        }
        var validator = XtendValidator(resolver: program.resolver, classes: program.classes)
        validator.validate(expression: parsed)
        if !validator.diagnostics.isEmpty { throw XtendError(diagnostics: validator.diagnostics) }
        let scope = XtendScope()
        for (name, host) in variables { scope.declare(name, await value(of: host), isMutable: true) }
        let context = XtendContext(scope: scope, this: nil, className: nil)
        do {
            return await hostValue(of: try await eval(parsed, context))
        } catch is XtendReturnSignal {
            return await hostValue(of: returnValue)
        }
    }

    /// The document name used for diagnostics of standalone expressions.
    static let expressionDocument = "expression"

    // MARK: - Errors

    /// Creates an evaluation error.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The extent of the failing expression.
    ///   - context: The context, which identifies the document.
    func failure(_ code: XtendDiagnosticCode, _ message: String, _ range: SourceRange?, _ context: XtendContext?) -> XtendError {
        let document = context?.className.flatMap { program.classes[$0]?.declaration.document } ?? Self.expressionDocument
        return XtendError(code, message, range: range, document: document)
    }

    /// Counts an evaluation step and enforces the step limit.
    func step(_ range: SourceRange, _ context: XtendContext) throws {
        steps += 1
        if let maximum = options.maximumSteps, steps > maximum {
            throw failure(.stepLimit, "Evaluation exceeded \(maximum) steps", range, context)
        }
    }

    // MARK: - Classes and instances

    /// The imports in effect for code of a class.
    func imports(of context: XtendContext) -> [XtendImport] {
        context.className.flatMap { program.classes[$0]?.imports } ?? []
    }

    /// Resolves a type reference in a context.
    func resolve(_ type: XtendTypeReference, _ context: XtendContext) -> XtendRuntimeType? {
        program.resolver.resolve(type, imports: imports(of: context))
    }

    /// The class and its superclasses, most derived first.
    func classChain(_ className: String) -> [XtendClassInfo] {
        program.classChain(className)
    }

    /// The methods with a name and number of parameters, most derived first, without
    /// overridden methods.
    func methods(named name: String, arity: Int, in className: String) -> [(method: XtendMethod, owner: String)] {
        var result: [(method: XtendMethod, owner: String)] = []
        for info in classChain(className) {
            for method in info.declaration.methods
            where method.name == name && method.parameters.count == arity && !method.isConstructor {
                let signature = method.parameters.map { $0.type?.simpleName ?? "" }
                if !result.contains(where: { $0.method.parameters.map { $0.type?.simpleName ?? "" } == signature }) {
                    result.append((method, info.declaration.qualifiedName))
                }
            }
        }
        return result
    }

    /// Creates an instance of a class of the compilation set.
    ///
    /// Fields are initialised from the root class down; extension fields of a class type
    /// without an initialiser receive a new instance of that class. A constructor with a
    /// matching number of parameters runs afterwards.
    func instantiate(_ className: String, arguments: [XtendValue], range: SourceRange) async throws -> XtendInstance {
        let chain = classChain(className)
        guard let info = chain.first else {
            throw XtendError(.unknownClass, "The compilation set declares no class '\(className)'", range: range)
        }
        if info.declaration.isAbstract {
            throw XtendError(
                .typeMismatch, "The abstract class '\(info.declaration.name)' cannot be instantiated", range: range,
                document: info.declaration.document)
        }
        depth += 1
        defer { depth -= 1 }
        if depth > options.maximumCallDepth {
            throw XtendError(.recursionLimit, "Instantiation nested deeper than \(options.maximumCallDepth) levels", range: range)
        }
        let instance = newInstance(of: info.declaration.qualifiedName)
        for owner in chain.reversed() {
            let context = XtendContext(scope: XtendScope(), this: instance, className: owner.declaration.qualifiedName)
            for field in owner.declaration.fields where !field.modifiers.isStatic {
                instance.fields[field.name] = try await initialValue(of: field, context)
            }
        }
        let constructors = info.declaration.methods.filter { $0.isConstructor && $0.parameters.count == arguments.count }
        if let constructor = constructors.first {
            _ = try await invoke(constructor, owner: info.declaration.qualifiedName, this: instance, arguments: arguments, range: range)
        } else if !arguments.isEmpty {
            throw XtendError(
                .unknownFeature, "The class '\(info.declaration.name)' has no constructor for \(arguments.count) argument(s)",
                range: range, document: info.declaration.document)
        }
        return instance
    }

    /// Creates an instance with a new serial number and no field values.
    ///
    /// - Parameter className: The qualified name of the class.
    /// - Returns: The new instance.
    func newInstance(of className: String) -> XtendInstance {
        instanceCount += 1
        return XtendInstance(className: className, serial: instanceCount)
    }

    /// The initial value of a field.
    func initialValue(of field: XtendField, _ context: XtendContext) async throws -> XtendValue {
        if let initialiser = field.initialiser { return try await eval(initialiser, context) }
        if let type = field.type, let resolved = resolve(type, context) {
            switch resolved {
            case .xtendClass(let name)
            where field.modifiers.isExtension || field.annotations.contains { $0.simpleName == "Inject" }:
                return .instance(try await instantiate(name, arguments: [], range: field.range))
            case .builtin(.integer): return .int(0)
            case .builtin(.double): return .double(0)
            case .builtin(.boolean) where type.name == "boolean": return .bool(false)
            default: break
            }
        }
        return .null
    }

    /// The value of a static field, initialising it on first use.
    func staticField(_ name: String, in className: String, range: SourceRange) async throws -> XtendValue? {
        for info in classChain(className) {
            let owner = info.declaration.qualifiedName
            guard let field = info.declaration.fields.first(where: { $0.name == name && $0.modifiers.isStatic }) else { continue }
            if let value = staticFields[owner]?[name] { return value }
            let context = XtendContext(scope: XtendScope(), this: nil, className: owner)
            let value = try await initialValue(of: field, context)
            staticFields[owner, default: [:]][name] = value
            return value
        }
        return nil
    }

    // MARK: - Invocation

    /// Whether a value conforms to a type.
    func conforms(_ value: XtendValue, to type: XtendRuntimeType) -> Bool {
        switch type {
        case .builtin(let builtin):
            if case .null = value { return builtin == .void }
            if case .object(let reference) = value, reference.metaKind == nil {
                return XtendBuiltinType.eObject.conforms(to: builtin)
            }
            return value.builtinKind.conforms(to: builtin)
        case .modelClass(let eClass):
            guard case .object(let reference) = value, let objectClass = reference.eClass else { return false }
            return XtendTypeResolver.eClass(objectClass, conformsTo: eClass)
        case .modelEnum(let eEnum):
            guard case .string(let literal) = value else { return false }
            return eEnum.literals.contains { $0.name == literal }
        case .xtendClass(let name):
            guard case .instance(let instance) = value else { return false }
            return program.resolver.isClass(instance.className, subclassOf: name)
        }
    }

    /// Whether a method accepts arguments by the declared types of its parameters.
    private func accepts(_ method: XtendMethod, owner: String, _ arguments: [XtendValue]) -> Bool {
        let context = XtendContext(scope: XtendScope(), this: nil, className: owner)
        for (parameter, argument) in zip(method.parameters, arguments) {
            guard let declared = parameter.type, let type = resolve(declared, context) else { continue }
            if case .null = argument {
                if method.modifiers.isDispatch {
                    if case .builtin(.void) = type { continue }
                    return false
                }
                continue
            }
            if case .builtin(.double) = type, case .int = argument { continue }
            if case .builtin(.function) = type { continue }
            if !conforms(argument, to: type) { return false }
        }
        return true
    }

    /// The parameter types of a method, with untyped parameters as `Object`.
    private func parameterTypes(_ method: XtendMethod, owner: String) -> [XtendRuntimeType] {
        let context = XtendContext(scope: XtendScope(), this: nil, className: owner)
        return method.parameters.map { parameter in
            parameter.type.flatMap { resolve($0, context) } ?? .builtin(.object)
        }
    }

    /// Chooses the most specific method that accepts the arguments.
    ///
    /// Dispatch cases are ordered by the inheritance of their parameter types from left to
    /// right; the first case whose parameter types are all at least as specific as those of
    /// every other applicable case wins.
    func select(
        _ candidates: [(method: XtendMethod, owner: String)], arguments: [XtendValue]
    ) -> (method: XtendMethod, owner: String)? {
        let applicable = candidates.filter { accepts($0.method, owner: $0.owner, arguments) }
        let types = applicable.map { parameterTypes($0.method, owner: $0.owner) }
        for (index, candidate) in applicable.enumerated() {
            let isMostSpecific = types.indices.allSatisfy { other in
                other == index || zip(types[index], types[other]).allSatisfy { program.resolver.isSubtype($0, of: $1) }
                    || !zip(types[other], types[index]).allSatisfy { program.resolver.isSubtype($0, of: $1) }
            }
            if isMostSpecific { return candidate }
        }
        return applicable.first
    }

    /// Calls a method of a class by name.
    ///
    /// - Returns: The result, or `nil` if the class has no applicable method of that name.
    /// - Throws: ``XtendDiagnosticCode/noDispatchCase`` if a dispatch method of that name
    ///   exists but has no case for the arguments, or the error of the method.
    func callClassMethod(
        _ name: String, arguments: [XtendValue], this: XtendInstance?, className: String, range: SourceRange,
        context: XtendContext? = nil
    ) async throws -> XtendValue? {
        var candidates = methods(named: name, arity: arguments.count, in: className)
        if this == nil { candidates = candidates.filter { $0.method.modifiers.isStatic } }
        guard !candidates.isEmpty else { return nil }
        guard let chosen = select(candidates, arguments: arguments) else {
            if candidates.contains(where: { $0.method.modifiers.isDispatch }) {
                let types = arguments.map(\.typeDescription).joined(separator: ", ")
                throw failure(.noDispatchCase, "Unhandled parameter types for dispatch method '\(name)': [\(types)]", range, context)
            }
            return nil
        }
        return try await invoke(chosen.method, owner: chosen.owner, this: this, arguments: arguments, range: range)
    }

    /// Invokes a method with arguments.
    func invoke(
        _ method: XtendMethod, owner: String, this: XtendInstance?, arguments: [XtendValue], range: SourceRange
    ) async throws -> XtendValue {
        depth += 1
        defer { depth -= 1 }
        let scope = XtendScope()
        let context = XtendContext(scope: scope, this: method.modifiers.isStatic ? nil : this, className: owner)
        if depth > options.maximumCallDepth {
            throw failure(.recursionLimit, "Calls nested deeper than \(options.maximumCallDepth) levels", range, context)
        }
        for (parameter, argument) in zip(method.parameters, arguments) {
            var value = argument
            if case .int(let number) = argument, let type = parameter.type,
                case .builtin(.double)? = resolve(type, context)
            {
                value = .double(Double(number))
            }
            scope.declare(parameter.name, value, isExtension: parameter.isExtension)
        }
        if let create = method.createClause {
            let cacheName = "\(owner).\(method.name)/\(arguments.count)"
            let receiver: XtendKey = this.map { .instance($0.serial) } ?? .null
            let key = XtendKey.sequence([receiver] + arguments.map(\.key))
            if let cached = createCaches[cacheName]?[key] { return cached }
            let created = try await eval(create.expression, context)
            createCaches[cacheName, default: [:]][key] = created
            scope.declare(create.name, created)
            if let body = method.body { _ = try await run(body, context) }
            return created
        }
        guard let body = method.body else {
            throw failure(.unknownFeature, "The method '\(method.name)' has no body", range, context)
        }
        return try await run(body, context)
    }

    /// Evaluates a method or lambda body, catching `return`.
    func run(_ body: XtendExpression, _ context: XtendContext) async throws -> XtendValue {
        do {
            return try await eval(body, context)
        } catch is XtendReturnSignal {
            let value = returnValue
            returnValue = .null
            return value
        }
    }

    /// Calls a lambda expression.
    ///
    /// A lambda without declared parameters binds a single argument to `it`.
    func callLambda(_ lambda: XtendLambda, _ arguments: [XtendValue], range: SourceRange) async throws -> XtendValue {
        depth += 1
        defer { depth -= 1 }
        let context = lambda.context.nested()
        if depth > options.maximumCallDepth {
            throw failure(.recursionLimit, "Calls nested deeper than \(options.maximumCallDepth) levels", range, context)
        }
        if lambda.explicitParameters {
            guard lambda.parameters.count == arguments.count else {
                throw failure(
                    .invalidArgument,
                    "The lambda expression takes \(lambda.parameters.count) parameter(s) but was called with \(arguments.count)",
                    range, context)
            }
            for (parameter, argument) in zip(lambda.parameters, arguments) {
                context.scope.declare(parameter.name, argument)
            }
        } else if arguments.count == 1 {
            context.scope.declare(XtendLanguage.implicitParameter, arguments[0])
        } else {
            for (index, argument) in arguments.enumerated() { context.scope.declare("$\(index + 1)", argument) }
        }
        return try await run(lambda.body, context)
    }

    /// Calls a value that should be a lambda expression.
    func callFunction(_ function: XtendValue, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext)
        async throws -> XtendValue
    {
        guard case .lambda(let lambda) = function else {
            throw failure(.typeMismatch, "Expected a lambda expression but found \(function.typeDescription)", range, context)
        }
        return try await callLambda(lambda, arguments, range: range)
    }

    // MARK: - Host values

    /// Converts a host value into an interpreter value.
    func value(of host: XtendHostValue) async -> XtendValue {
        switch host {
        case .null: return .null
        case .bool(let value): return .bool(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .string(let value): return .string(value)
        case .list(let elements):
            var values: [XtendValue] = []
            for element in elements { values.append(await value(of: element)) }
            return .collection(XtendCollection(values))
        case .set(let elements):
            var values: [XtendValue] = []
            for element in elements { values.append(await value(of: element)) }
            return .collection(XtendCollection(values, isSet: true))
        case .map(let entries):
            let map = XtendMap()
            for entry in entries { map.put(await value(of: entry.key), await value(of: entry.value)) }
            return .map(map)
        case .pair(let key, let value):
            return .pair(XtendPair(await self.value(of: key), await self.value(of: value)))
        case .object(let id, let resource):
            if let resource { addResource(resource) }
            return await objectValue(id: id, preferring: resource) ?? .null
        case .resource(let resource):
            addResource(resource)
            return .resource(resource)
        case .fileSystem(let fileSystem): return .fileSystem(fileSystem)
        case .other(let text): return .string(text)
        }
    }

    /// Converts an interpreter value into a host value.
    func hostValue(of value: XtendValue) async -> XtendHostValue {
        switch value {
        case .null: return .null
        case .bool(let value): return .bool(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .string(let value): return .string(value)
        case .collection(let collection):
            var elements: [XtendHostValue] = []
            for element in collection.elements { elements.append(await hostValue(of: element)) }
            return collection.isSet ? .set(elements) : .list(elements)
        case .map(let map):
            var entries: [(key: XtendHostValue, value: XtendHostValue)] = []
            for (key, value) in zip(map.keys, map.values) {
                entries.append((await hostValue(of: key), await hostValue(of: value)))
            }
            return .map(entries)
        case .pair(let pair): return .pair(await hostValue(of: pair.key), await hostValue(of: pair.value))
        case .range(let range): return .list(range.elements.map { .int($0) })
        case .object(let reference): return .object(reference.id, reference.resource)
        case .resource(let resource): return .resource(resource)
        case .fileSystem(let fileSystem): return .fileSystem(fileSystem)
        default: return .other(await text(of: value))
        }
    }
}

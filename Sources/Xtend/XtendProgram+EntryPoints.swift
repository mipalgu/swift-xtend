//
//  XtendProgram+EntryPoints.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// A generator method of a program: the class that declares or inherits it, its name and its
/// number of parameters.
struct XtendGeneratorEntry: Sendable, Equatable {
    /// The qualified name of the generator class.
    let className: String

    /// The name of the generator method, one of ``XtendLanguage/generatorMethodNames``.
    let methodName: String

    /// The number of parameters of the method, one of ``XtendLanguage/generatorArities``.
    let arity: Int
}

/// The classes and methods by which a program is entered.
extension XtendProgram {
    /// The generator class of the program.
    ///
    /// Without a name, the generator class is the first class, in declaration order, that is not
    /// abstract and declares or inherits a method named after one of
    /// ``XtendLanguage/generatorMethodNames`` that takes the input resource and a file system
    /// access, optionally followed by a generator context. This is the class that
    /// ``XtendInterpreter/generate(resource:fileSystem:className:)`` runs when it is given no
    /// class name.
    ///
    /// - Parameter name: The simple or qualified name of the class, or `nil` to find it.
    /// - Returns: The declaration of the generator class, or `nil` if the named class does not
    ///   exist or has no generator method, or if no class has one.
    public func generatorClass(named name: String? = nil) -> XtendClass? {
        generatorEntry(className: name).flatMap { classes[$0.className]?.declaration }
    }

    /// The generator method of the program.
    ///
    /// - Parameter className: The simple or qualified name of the class, or `nil` to find it as
    ///   ``generatorClass(named:)`` does.
    /// - Returns: The class, name and number of parameters of the generator method, or `nil` if
    ///   there is none.
    func generatorEntry(className: String?) -> XtendGeneratorEntry? {
        let candidates = className.map { [$0] } ?? classNames
        for name in candidates {
            guard let info = classInfo(name), className != nil || !info.declaration.isAbstract else { continue }
            let methods = classChain(info.declaration.qualifiedName).flatMap(\.declaration.methods).filter { !$0.isConstructor }
            for methodName in XtendLanguage.generatorMethodNames {
                for arity in XtendLanguage.generatorArities
                where methods.contains(where: { $0.name == methodName && $0.parameters.count == arity }) {
                    return XtendGeneratorEntry(className: info.declaration.qualifiedName, methodName: methodName, arity: arity)
                }
            }
        }
        return nil
    }

    /// The parameters of the dispatcher of a dispatch method.
    ///
    /// As in Xtend, the cases of a dispatch method with the same number of parameters share one
    /// dispatcher, whose parameter types are, position by position, the most specific common
    /// supertype of the parameter types of the cases. A parameter whose cases all declare the
    /// same type keeps that type as written, such as `int`; an untyped parameter counts as
    /// `Object`. Classes of a metamodel without a common superclass share `EObject`, and types
    /// without any other common supertype share `Object`. The dispatcher's parameters take the
    /// names of the first case. Cases that the class inherits count as well.
    ///
    /// - Parameters:
    ///   - method: The name of the dispatch method.
    ///   - arity: The number of parameters.
    ///   - className: The simple or qualified name of the class.
    /// - Returns: The parameters of the dispatcher, or `nil` if the class does not exist or has
    ///   no dispatch case of that name and number of parameters.
    public func dispatcherParameters(of method: String, arity: Int, in className: String) -> [XtendParameter]? {
        guard let info = classInfo(className) else { return nil }
        var cases: [(method: XtendMethod, imports: [XtendImport])] = []
        for owner in classChain(info.declaration.qualifiedName) {
            for candidate in owner.declaration.methods
            where candidate.name == method && candidate.parameters.count == arity && candidate.modifiers.isDispatch
                && !candidate.isConstructor
            {
                cases.append((candidate, owner.imports))
            }
        }
        guard let first = cases.first else { return nil }
        return first.method.parameters.indices.map { position in
            let parameter = first.method.parameters[position]
            let declared = cases.map { $0.method.parameters[position].type }
            if let type = declared[0], declared.allSatisfy({ $0?.name == type.name }) { return parameter }
            let types = cases.map { entry in
                entry.method.parameters[position].type.flatMap { resolver.resolve($0, imports: entry.imports) }
                    ?? .builtin(.object)
            }
            let common = resolver.commonSupertype(of: types)
            let range = parameter.type?.range ?? parameter.range
            return XtendParameter(
                name: parameter.name, type: XtendTypeReference(name: common.referenceName, range: range),
                isExtension: parameter.isExtension, range: parameter.range)
        }
    }

    /// The class and its superclasses of the compilation set, most derived first.
    ///
    /// - Parameter className: The qualified name of the class.
    /// - Returns: The classes, ending at the first superclass outside the compilation set.
    func classChain(_ className: String) -> [XtendClassInfo] {
        var chain: [XtendClassInfo] = []
        var current: String? = className
        var visited: Set<String> = []
        while let name = current, visited.insert(name).inserted, let info = classes[name] {
            chain.append(info)
            current = info.superclass
        }
        return chain
    }
}

extension XtendRuntimeType {
    /// The name by which a type reference denotes the type: the simple name of a metamodel
    /// classifier, the qualified name of a class of the compilation set, or the name of a
    /// built-in type.
    var referenceName: String {
        switch self {
        case .builtin(let type): return type.rawValue
        case .modelClass(let eClass): return eClass.name
        case .modelEnum(let eEnum): return eEnum.name
        case .xtendClass(let name): return name
        }
    }
}

extension XtendTypeResolver {
    /// The most specific type that every one of the given types conforms to.
    ///
    /// The supertypes of the first type are tried from the most to the least specific, and the
    /// first one that every type conforms to is the result.
    ///
    /// - Parameter types: The types.
    /// - Returns: The common supertype, `Object` if there is no other or no type is given.
    func commonSupertype(of types: [XtendRuntimeType]) -> XtendRuntimeType {
        guard let first = types.first else { return .builtin(.object) }
        for candidate in supertypes(of: first) where types.allSatisfy({ isSubtype($0, of: candidate) }) {
            return candidate
        }
        return .builtin(.object)
    }

    /// A type and its supertypes, from the most to the least specific.
    ///
    /// - Parameter type: The type.
    /// - Returns: The type, its supertypes breadth first, and `Object` last.
    func supertypes(of type: XtendRuntimeType) -> [XtendRuntimeType] {
        var result: [XtendRuntimeType] = [type]
        switch type {
        case .builtin(let builtin):
            var queue = builtin.supertypes
            var seen: Set<XtendBuiltinType> = [builtin]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                guard seen.insert(next).inserted else { continue }
                result.append(.builtin(next))
                queue += next.supertypes
            }
        case .modelClass(let eClass):
            result += eClass.allSuperTypes.map { .modelClass($0) }
            result.append(.builtin(.eObject))
        case .modelEnum:
            result.append(.builtin(.string))
        case .xtendClass(let name):
            var current = superclasses[name]
            var visited: Set<String> = [name]
            while let superclass = current, visited.insert(superclass).inserted {
                result.append(.xtendClass(superclass))
                current = superclasses[superclass]
            }
        }
        result.append(.builtin(.object))
        return result
    }
}

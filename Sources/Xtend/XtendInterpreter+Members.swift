//
//  XtendInterpreter+Members.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

extension XtendInterpreter {
    // MARK: - Name resolution

    /// The spellings under which a property-style name can be found.
    ///
    /// Xtend lets `x.name` stand for `x.getName()` and `x.empty` for `x.isEmpty()`, and
    /// `x.getName()` reach a feature called `name`.
    static func nameVariants(_ name: String) -> [String] {
        var variants = [name]
        /// Lowercases the first character of a name.
        ///
        /// - Parameter text: The name to convert.
        /// - Returns: The name starting with a lowercase letter.
        func decapitalised(_ text: Substring) -> String { text.prefix(1).lowercased() + text.dropFirst() }
        if name.count > 3, name.hasPrefix("get"), name.dropFirst(3).first?.isUppercase == true {
            variants.append(decapitalised(name.dropFirst(3)))
        } else if name.count > 2, name.hasPrefix("is"), name.dropFirst(2).first?.isUppercase == true {
            variants.append(decapitalised(name.dropFirst(2)))
        } else {
            if name.first?.isUppercase == true { variants.append(decapitalised(Substring(name))) }
            let capitalised = name.prefix(1).uppercased() + name.dropFirst()
            variants.append("get" + capitalised)
            variants.append("is" + capitalised)
        }
        return variants
    }

    /// The name of a setter's feature, if the name is a setter such as `setName`.
    static func setterFeature(_ name: String) -> String? {
        guard name.count > 3, name.hasPrefix("set"), name.dropFirst(3).first?.isUppercase == true else { return nil }
        return name.dropFirst(3).prefix(1).lowercased() + name.dropFirst(4)
    }

    /// The spelling under which a member of an allow-list is reached, if any.
    static func allowedName(_ name: String, in allowList: Set<String>) -> String? {
        nameVariants(name).first { allowList.contains($0) }
    }

    /// The extension providers visible in a context: extension variables and parameters,
    /// then extension fields of the receiver's class.
    func extensionProviders(_ context: XtendContext) -> [XtendValue] {
        var providers = context.scope.extensionValues
        if let this = context.this {
            for info in classChain(this.className) {
                for field in info.declaration.fields where field.modifiers.isExtension {
                    if let value = this.fields[field.name] { providers.append(value) }
                }
            }
        }
        return providers
    }

    /// Tries a method as an extension method: on the running class, the extension providers
    /// and the classes imported with `import static extension`.
    ///
    /// - Returns: The result, or `nil` if no extension method applies.
    func callExtension(_ name: String, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext)
        async throws -> XtendValue?
    {
        if let className = context.className,
            let result = try await callClassMethod(
                name, arguments: arguments, this: context.this, className: className, range: range, context: context)
        {
            return result
        }
        for provider in extensionProviders(context) {
            guard case .instance(let instance) = provider else { continue }
            if let result = try await callClassMethod(
                name, arguments: arguments, this: instance, className: instance.className, range: range, context: context)
            {
                return result
            }
        }
        if let className = context.className, let info = program.classes[className] {
            for imported in info.staticExtensionClasses {
                if let result = try await callClassMethod(
                    name, arguments: arguments, this: nil, className: imported, range: range, context: context)
                {
                    return result
                }
            }
        }
        return nil
    }

    /// Evaluates a name without a receiver: a variable, a member of `it`, a field or method
    /// of the running class, an extension method, a library function or a type.
    func featureCall(
        _ name: String, arguments: [XtendExpression], explicitCall: Bool, range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        let isProperty = arguments.isEmpty && !explicitCall
        if isProperty, let variable = context.scope.lookup(name) { return variable.value }
        if explicitCall, name == XtendLanguage.Keyword.this.rawValue || name == XtendLanguage.Keyword.super.rawValue {
            return try await delegateConstructor(toSuperclass: name != XtendLanguage.Keyword.this.rawValue, arguments, range: range, context)
        }
        let values = try await evalAll(arguments, context)
        let it = context.scope.lookup(XtendLanguage.implicitParameter)?.value
        if let it, !it.isNull, case .type = it {
        } else if let it, !it.isNull,
            let result = try await member(of: it, name, values, explicitCall: explicitCall, range: range, context)
        {
            return result
        }
        if isProperty, let this = context.this, let field = classChain(this.className).first(where: { info in
            info.declaration.fields.contains { $0.name == name && !$0.modifiers.isStatic }
        }) {
            _ = field
            return this.fields[name] ?? .null
        }
        if isProperty, let className = context.className, let value = try await staticField(name, in: className, range: range) {
            return value
        }
        if let result = try await callExtension(name, values, range: range, context) { return result }
        if let it, let result = try await callExtension(name, [it] + values, range: range, context) {
            return result
        }
        if let result = try await globalFunction(name, values, range: range, context) { return result }
        if let first = values.first,
            let result = try await extensionFunction(name, receiver: first, Array(values.dropFirst()), range: range, context)
        {
            return result
        }
        if let it, let result = try await extensionFunction(name, receiver: it, values, range: range, context) {
            return result
        }
        if isProperty, let type = program.resolver.resolve(name: name, imports: imports(of: context)) {
            return .type(type)
        }
        throw failure(
            .unknownFeature,
            "'\(name)' cannot be resolved to a variable, field, feature, method or type" + (values.isEmpty ? "" : " for \(values.count) argument(s)"),
            range, context)
    }

    /// Runs another constructor of the running class, or a constructor of its superclass,
    /// on the instance under construction.
    private func delegateConstructor(
        toSuperclass: Bool, _ arguments: [XtendExpression], range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        guard let this = context.this, let className = context.className,
            let target = toSuperclass ? program.classes[className]?.superclass : className,
            let info = program.classes[target]
        else {
            throw failure(.unknownFeature, "A constructor can only be called from another constructor", range, context)
        }
        let values = try await evalAll(arguments, context)
        guard let constructor = info.declaration.methods.first(where: { $0.isConstructor && $0.parameters.count == values.count })
        else {
            if toSuperclass && values.isEmpty { return .null }
            throw failure(
                .unknownFeature, "The class '\(info.declaration.name)' has no constructor for \(values.count) argument(s)",
                range, context)
        }
        _ = try await invoke(constructor, owner: target, this: this, arguments: values, range: range)
        return .null
    }

    /// Evaluates a member access `receiver.name(arguments)`.
    func memberCall(
        _ receiverExpression: XtendExpression, name: String, arguments: [XtendExpression], explicitCall: Bool,
        nullSafe: Bool, range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        if case .superReference = receiverExpression.kind {
            guard let this = context.this, let className = context.className,
                let superclass = program.classes[className]?.superclass
            else {
                throw failure(.unknownFeature, "'super' is not available here", range, context)
            }
            let values = try await evalAll(arguments, context)
            guard
                let result = try await callClassMethod(
                    name, arguments: values, this: this, className: superclass, range: range, context: context)
            else {
                throw failure(.unknownFeature, "The superclass has no method '\(name)'", range, context)
            }
            return result
        }
        if case .featureCall(let typeName, let typeArguments, false) = receiverExpression.kind, typeArguments.isEmpty,
            context.scope.lookup(typeName) == nil, XtendJavaSubset.staticMembers[typeName] != nil,
            program.resolver.resolve(name: typeName, imports: imports(of: context)) == nil
        {
            let values = try await evalAll(arguments, context)
            return try await staticJava(typeName, name, values, range: range, context)
        }
        let receiver = try await eval(receiverExpression, context)
        if receiver.isNull && nullSafe { return .null }
        let values = try await evalAll(arguments, context)
        if case .type(let type) = receiver {
            return try await staticMember(of: type, typeName: type.name, name, values, range: range, context)
        }
        if !receiver.isNull,
            let result = try await member(of: receiver, name, values, explicitCall: explicitCall, range: range, context)
        {
            return result
        }
        if let result = try await callExtension(name, [receiver] + values, range: range, context) { return result }
        if let result = try await extensionFunction(name, receiver: receiver, values, range: range, context) { return result }
        if receiver.isNull {
            throw failure(.nullPointer, "Cannot access '\(name)' of null", range, context)
        }
        throw unknownMember(receiver, name, range: range, context)
    }

    /// The error for a member that a receiver does not have.
    func unknownMember(_ receiver: XtendValue, _ name: String, range: SourceRange, _ context: XtendContext) -> XtendError {
        switch receiver {
        case .string, .collection, .map, .pair, .range, .int, .double, .bool, .lambda, .exception:
            return failure(
                .unsupportedJavaMember,
                "The Java member '\(name)' of \(receiver.typeDescription) is outside the supported subset", range, context)
        case .object(let reference):
            let owner = reference.eClass?.name ?? reference.metaKind?.rawValue ?? "EObject"
            return failure(.unknownFeature, "The class '\(owner)' has no feature or operation '\(name)'", range, context)
        default:
            return failure(.unknownFeature, "\(receiver.typeDescription) has no member '\(name)'", range, context)
        }
    }

    // MARK: - Static members

    /// Evaluates a static member access `Type::name(arguments)`.
    func staticMember(
        _ type: XtendTypeReference, name: String, arguments: [XtendValue], explicitCall: Bool, range: SourceRange,
        _ context: XtendContext
    ) async throws -> XtendValue {
        guard let resolved = resolve(type, context) else {
            return try await staticJava(type.simpleName, name, arguments, range: range, context)
        }
        return try await staticMember(of: resolved, typeName: type.simpleName, name, arguments, range: range, context)
    }

    /// Evaluates a static member of a resolved type.
    func staticMember(
        of type: XtendRuntimeType, typeName: String, _ name: String, _ arguments: [XtendValue], range: SourceRange,
        _ context: XtendContext
    ) async throws -> XtendValue {
        switch type {
        case .modelEnum(let eEnum):
            if arguments.isEmpty, let literal = eEnum.literals.first(where: { $0.name == name || $0.literal == name }) {
                return .string(literal.name)
            }
            throw failure(.unknownFeature, "The enumeration '\(eEnum.name)' has no literal '\(name)'", range, context)
        case .xtendClass(let className):
            if arguments.isEmpty, let value = try await staticField(name, in: className, range: range) { return value }
            if let result = try await callClassMethod(
                name, arguments: arguments, this: nil, className: className, range: range, context: context)
            {
                return result
            }
            throw failure(.unknownFeature, "The class '\(className)' has no static member '\(name)'", range, context)
        case .builtin:
            return try await staticJava(typeName, name, arguments, range: range, context)
        case .modelClass(let eClass):
            throw failure(.unknownFeature, "The metamodel class '\(eClass.name)' has no static member '\(name)'", range, context)
        }
    }

    /// Evaluates a static member of the Java subset.
    func staticJava(
        _ typeName: String, _ name: String, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        guard XtendJavaSubset.staticMembers[typeName]?.contains(name) == true else {
            throw failure(
                .unsupportedJavaMember, "The static member '\(typeName)::\(name)' is outside the supported Java subset", range,
                context)
        }
        let first = arguments.first ?? .null
        /// Converts an argument to a number.
        ///
        /// - Parameter value: The argument value.
        /// - Returns: The numeric value.
        /// - Throws: A type mismatch failure if the value is not a number.
        func number(_ value: XtendValue) throws -> Double {
            guard let number = Self.number(value) else {
                throw failure(.typeMismatch, "'\(typeName)::\(name)' needs numbers", range, context)
            }
            return number
        }
        switch (typeName, name, arguments.count) {
        case ("String", "valueOf", 1): return .string(await text(of: first))
        case ("String", "join", _) where !arguments.isEmpty:
            let separator = await text(of: first)
            var parts: [XtendValue] = Array(arguments.dropFirst())
            if parts.count == 1, isIterable(parts[0]) { parts = try elements(of: parts[0], range: range, context) }
            var texts: [String] = []
            for part in parts { texts.append(await text(of: part)) }
            return .string(texts.joined(separator: separator))
        case ("Integer", "parseInt", 1), ("Integer", "valueOf", 1), ("Long", "parseLong", 1), ("Long", "valueOf", 1):
            if case .int = first { return first }
            guard let number = Int(await text(of: first).trimmingCharacters(in: .whitespaces)) else {
                throw failure(.invalidArgument, "'\(await text(of: first))' is not a whole number", range, context)
            }
            return .int(number)
        case ("Integer", "toString", 1): return .string(await text(of: first))
        case ("Integer", "MAX_VALUE", 0): return .int(Int(Int32.max))
        case ("Integer", "MIN_VALUE", 0): return .int(Int(Int32.min))
        case ("Long", "MAX_VALUE", 0): return .int(Int.max)
        case ("Long", "MIN_VALUE", 0): return .int(Int.min)
        case ("Double", "parseDouble", 1), ("Double", "valueOf", 1):
            if let number = Self.number(first) { return .double(number) }
            guard let number = Double(await text(of: first).trimmingCharacters(in: .whitespaces)) else {
                throw failure(.invalidArgument, "'\(await text(of: first))' is not a number", range, context)
            }
            return .double(number)
        case ("Boolean", "parseBoolean", 1), ("Boolean", "valueOf", 1):
            if case .bool = first { return first }
            return .bool(await text(of: first).lowercased() == "true")
        case ("Math", "max", 2), ("Math", "min", 2):
            if case .int(let left) = first, case .int(let right) = arguments[1] {
                return .int(name == "max" ? max(left, right) : min(left, right))
            }
            let left = try number(first)
            let right = try number(arguments[1])
            return .double(name == "max" ? max(left, right) : min(left, right))
        case ("Math", "abs", 1):
            if case .int(let value) = first { return .int(abs(value)) }
            return .double(abs(try number(first)))
        case ("Math", "floor", 1): return .double((try number(first)).rounded(.down))
        case ("Math", "ceil", 1): return .double((try number(first)).rounded(.up))
        case ("Math", "round", 1): return .int(Int((try number(first) + 0.5).rounded(.down)))
        case ("Math", "sqrt", 1): return .double((try number(first)).squareRoot())
        case ("Math", "pow", 2): return .double(pow(try number(first), try number(arguments[1])))
        default:
            throw failure(
                .invalidArgument, "'\(typeName)::\(name)' does not take \(arguments.count) argument(s)", range, context)
        }
    }

    // MARK: - Members

    /// Evaluates a member of a value: a model feature, a field or method of an instance, or a
    /// member of the Java subset.
    ///
    /// - Returns: The value, or `nil` if the receiver has no such member.
    func member(
        of receiver: XtendValue, _ name: String, _ arguments: [XtendValue], explicitCall: Bool, range: SourceRange,
        _ context: XtendContext
    ) async throws -> XtendValue? {
        switch receiver {
        case .string(let text):
            return try stringMember(text, name, arguments, range: range, context)
        case .collection(let collection):
            return try await collectionMember(collection, name, arguments, range: range, context)
        case .range(let integers):
            let collection = XtendCollection(integers.elements.map { .int($0) }, isMutable: false)
            return try await collectionMember(collection, name, arguments, range: range, context)
        case .map(let map):
            return try await mapMember(map, name, arguments, range: range, context)
        case .pair(let pair):
            switch Self.allowedName(name, in: XtendJavaSubset.pairMembers) {
            case "key", "getKey": return arguments.isEmpty ? pair.key : nil
            case "value", "getValue": return arguments.isEmpty ? pair.value : nil
            default: return try await commonMember(receiver, name, arguments)
            }
        case .object(let reference):
            return try await objectMember(reference, name, arguments, explicitCall: explicitCall, range: range, context)
        case .instance(let instance):
            if arguments.isEmpty, !explicitCall,
                classChain(instance.className).contains(where: { $0.declaration.fields.contains { $0.name == name } })
            {
                return instance.fields[name] ?? .null
            }
            if let result = try await callClassMethod(
                name, arguments: arguments, this: instance, className: instance.className, range: range, context: context)
            {
                return result
            }
            return try await commonMember(receiver, name, arguments)
        case .lambda(let lambda):
            if name == "apply" { return try await callLambda(lambda, arguments, range: range) }
            return try await commonMember(receiver, name, arguments)
        case .resource(let resource):
            guard arguments.isEmpty else { return nil }
            switch Self.allowedName(name, in: XtendJavaSubset.resourceMembers) {
            case "contents", "getContents":
                var values: [XtendValue] = []
                for object in await resource.getRootObjects() { values.append(await wrap(object, holder: resource)) }
                return .collection(XtendCollection(values, isMutable: false))
            case "allContents", "getAllContents":
                let roots = Set(await resource.getRootObjects().map(\.id))
                var values: [XtendValue] = []
                for object in await resource.getAllObjectsIncludingContents() where !roots.contains(object.id) {
                    values.append(await wrap(object, holder: resource))
                }
                return .collection(XtendCollection(values, isMutable: false))
            case "URI", "uri", "getURI": return .string(resource.uri)
            default: return nil
            }
        case .fileSystem(let fileSystem):
            guard name == "generateFile", arguments.count == 2 || arguments.count == 3 else { return nil }
            let path = await text(of: arguments[0])
            let configuration = arguments.count == 3 ? await text(of: arguments[1]) : XtendLanguage.defaultOutputConfiguration
            let contents = await text(of: arguments[arguments.count - 1])
            do {
                try await fileSystem.generateFile(path, outputConfiguration: configuration, contents: contents)
            } catch let error as XtendError {
                throw failure(.fileAccess, error.diagnostics.first?.message ?? "\(error)", range, context)
            } catch {
                throw failure(.fileAccess, "Cannot write '\(path)': \(error)", range, context)
            }
            return .null
        case .exception(_, let message):
            if Self.allowedName(name, in: XtendJavaSubset.exceptionMembers) == "getMessage" {
                return message.map { .string($0) } ?? .null
            }
            return try await commonMember(receiver, name, arguments)
        case .int(let number):
            switch Self.allowedName(name, in: XtendJavaSubset.valueMembers) {
            case "intValue", "longValue": return arguments.isEmpty ? receiver : nil
            case "doubleValue", "floatValue": return arguments.isEmpty ? .double(Double(number)) : nil
            case "compareTo" where arguments.count == 1:
                return .int(try compare(receiver, arguments[0], range: range, context))
            default: return try await commonMember(receiver, name, arguments)
            }
        case .double(let number):
            switch Self.allowedName(name, in: XtendJavaSubset.valueMembers) {
            case "intValue", "longValue": return arguments.isEmpty ? .int(Int(number)) : nil
            case "doubleValue", "floatValue": return arguments.isEmpty ? receiver : nil
            case "compareTo" where arguments.count == 1:
                return .int(try compare(receiver, arguments[0], range: range, context))
            default: return try await commonMember(receiver, name, arguments)
            }
        case .bool:
            if Self.allowedName(name, in: XtendJavaSubset.valueMembers) == "booleanValue", arguments.isEmpty { return receiver }
            return try await commonMember(receiver, name, arguments)
        case .null, .type:
            return nil
        }
    }

    /// The members that every value has: `toString`, `equals` and `hashCode`.
    func commonMember(_ receiver: XtendValue, _ name: String, _ arguments: [XtendValue]) async throws -> XtendValue? {
        switch (name, arguments.count) {
        case ("toString", 0): return .string(await text(of: receiver))
        case ("equals", 1): return .bool(XtendValue.areEqual(receiver, arguments[0]))
        case ("hashCode", 0): return .int(Self.javaHash(await text(of: receiver)))
        default: return nil
        }
    }

    /// The hash code that Java computes for a string.
    static func javaHash(_ text: String) -> Int {
        var hash: Int32 = 0
        for unit in text.utf16 { hash = hash &* 31 &+ Int32(unit) }
        return Int(hash)
    }

    // MARK: - Strings

    /// Evaluates a member of a string.
    func stringMember(_ text: String, _ name: String, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext)
        throws -> XtendValue?
    {
        guard let member = Self.allowedName(name, in: XtendJavaSubset.stringMembers) else { return nil }
        let units = Array(text.utf16)
        /// Reads a string argument.
        ///
        /// - Parameter index: The position of the argument.
        /// - Returns: The string value.
        /// - Throws: An invalid argument failure if the argument is missing or not a string.
        func string(_ index: Int) throws -> String {
            guard index < arguments.count, case .string(let value) = arguments[index] else {
                throw failure(.invalidArgument, "'\(member)' needs a string argument", range, context)
            }
            return value
        }
        /// Reads a whole-number argument.
        ///
        /// - Parameter index: The position of the argument.
        /// - Returns: The integer value.
        /// - Throws: An invalid argument failure if the argument is missing or not a whole number.
        func integer(_ index: Int) throws -> Int {
            guard index < arguments.count, case .int(let value) = arguments[index] else {
                throw failure(.invalidArgument, "'\(member)' needs a whole-number argument", range, context)
            }
            return value
        }
        /// Extracts a substring by UTF-16 offsets.
        ///
        /// - Parameters:
        ///   - from: The inclusive start offset.
        ///   - to: The exclusive end offset.
        /// - Returns: The substring between the offsets.
        /// - Throws: An index out of bounds failure if the offsets do not fit the string.
        func substring(_ from: Int, _ to: Int) throws -> String {
            guard from >= 0, to <= units.count, from <= to else {
                throw failure(.indexOutOfBounds, "begin \(from), end \(to), length \(units.count)", range, context)
            }
            return String(decoding: units[from..<to], as: UTF16.self)
        }
        /// Finds a pattern in the string.
        ///
        /// - Parameters:
        ///   - needle: The text to look for.
        ///   - start: The offset at which the search begins.
        ///   - last: Whether to return the last match rather than the first.
        /// - Returns: The UTF-16 offset of the match, or -1 if there is none.
        func indexOf(_ needle: String, from start: Int, last: Bool) -> Int {
            let pattern = Array(needle.utf16)
            guard pattern.count <= units.count else { return -1 }
            let positions = Array(max(0, start)...(units.count - pattern.count))
            for position in (last ? positions.reversed() : positions)
            where Array(units[position..<(position + pattern.count)]) == pattern {
                return position
            }
            return -1
        }
        switch (member, arguments.count) {
        case ("length", 0): return .int(units.count)
        case ("isEmpty", 0): return .bool(units.isEmpty)
        case ("isBlank", 0): return .bool(text.allSatisfy(\.isWhitespace))
        case ("charAt", 1):
            let index = try integer(0)
            return .string(try substring(index, index + 1))
        case ("substring", 1): return .string(try substring(try integer(0), units.count))
        case ("substring", 2): return .string(try substring(try integer(0), try integer(1)))
        case ("indexOf", 1): return .int(indexOf(try string(0), from: 0, last: false))
        case ("indexOf", 2): return .int(indexOf(try string(0), from: try integer(1), last: false))
        case ("lastIndexOf", 1): return .int(indexOf(try string(0), from: 0, last: true))
        case ("contains", 1): return .bool(try string(0).isEmpty || text.contains(try string(0)))
        case ("startsWith", 1): return .bool(text.hasPrefix(try string(0)))
        case ("endsWith", 1): return .bool(text.hasSuffix(try string(0)))
        case ("toUpperCase", 0): return .string(text.uppercased())
        case ("toLowerCase", 0): return .string(text.lowercased())
        case ("trim", 0):
            return .string(String(text.unicodeScalars.drop { $0.value <= 0x20 }.reversed().drop { $0.value <= 0x20 }.reversed().map(Character.init)))
        case ("strip", 0): return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case ("replace", 2): return .string(text.replacingOccurrences(of: try string(0), with: try string(1)))
        case ("replaceAll", 2):
            let expression = try regularExpression(try string(0), range: range, context)
            return .string(
                expression.stringByReplacingMatches(
                    in: text, range: NSRange(text.startIndex..., in: text), withTemplate: try string(1)))
        case ("matches", 1):
            let expression = try regularExpression("^(?:" + (try string(0)) + ")$", range: range, context)
            return .bool(expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil)
        case ("split", 1):
            let expression = try regularExpression(try string(0), range: range, context)
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            guard !matches.isEmpty else { return .collection(XtendCollection([.string(text)])) }
            var parts: [String] = []
            var start = text.startIndex
            for match in matches {
                guard let matched = Range(match.range, in: text) else { continue }
                if matched.isEmpty && matched.lowerBound == text.startIndex { continue }
                if matched.isEmpty && matched.lowerBound >= text.endIndex { break }
                parts.append(String(text[start..<matched.lowerBound]))
                start = matched.upperBound
            }
            parts.append(String(text[start...]))
            while parts.last?.isEmpty == true { parts.removeLast() }
            return .collection(XtendCollection(parts.map { .string($0) }))
        case ("equals", 1):
            if case .string(let other) = arguments[0] { return .bool(other == text) }
            return .bool(false)
        case ("equalsIgnoreCase", 1):
            if case .string(let other) = arguments[0] { return .bool(other.lowercased() == text.lowercased()) }
            return .bool(false)
        case ("compareTo", 1): return .int(Self.compareStrings(text, try string(0)))
        case ("concat", 1): return .string(text + (try string(0)))
        case ("repeat", 1):
            let count = try integer(0)
            guard count >= 0 else { throw failure(.invalidArgument, "count is negative: \(count)", range, context) }
            return .string(String(repeating: text, count: count))
        case ("toString", 0): return .string(text)
        case ("hashCode", 0): return .int(Self.javaHash(text))
        case ("toCharArray", 0): return .collection(XtendCollection(text.map { .string(String($0)) }))
        case ("lines", 0):
            return .collection(
                XtendCollection(text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { .string(String($0)) }))
        default:
            return nil
        }
    }

    /// Compiles a Java-style regular expression.
    private func regularExpression(_ pattern: String, range: SourceRange, _ context: XtendContext) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw failure(.invalidArgument, "Invalid regular expression '\(pattern)'", range, context)
        }
    }

    // MARK: - Collections and maps

    /// Evaluates a member of a list or set.
    func collectionMember(
        _ collection: XtendCollection, _ name: String, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue? {
        guard let member = Self.allowedName(name, in: XtendJavaSubset.collectionMembers) else { return nil }
        let isMutator = ["add", "addAll", "remove", "removeAll", "clear", "set"].contains(member)
        if isMutator, !collection.isMutable {
            throw failure(.immutableCollection, "Cannot change an immutable collection with '\(member)'", range, context)
        }
        /// Converts an argument to a list position.
        ///
        /// - Parameters:
        ///   - value: The argument value.
        ///   - inclusive: Whether the position just past the last element is allowed.
        /// - Returns: The position.
        /// - Throws: An index out of bounds failure if the value is not a valid position.
        func index(_ value: XtendValue, inclusive: Bool = false) throws -> Int {
            guard case .int(let position) = value, position >= 0,
                position < collection.elements.count + (inclusive ? 1 : 0)
            else {
                throw failure(
                    .indexOutOfBounds, "Index \(value) out of bounds for length \(collection.elements.count)", range, context)
            }
            return position
        }
        let result: XtendValue
        switch (member, arguments.count) {
        case ("size", 0): return .int(collection.elements.count)
        case ("isEmpty", 0): return .bool(collection.elements.isEmpty)
        case ("contains", 1): return .bool(collection.contains(arguments[0]))
        case ("containsAll", 1):
            return .bool(try elements(of: arguments[0], range: range, context).allSatisfy { collection.contains($0) })
        case ("get", 1) where !collection.isSet: return collection.elements[try index(arguments[0])]
        case ("indexOf", 1):
            return .int(collection.elements.firstIndex { XtendValue.areEqual($0, arguments[0]) } ?? -1)
        case ("lastIndexOf", 1):
            return .int(collection.elements.lastIndex { XtendValue.areEqual($0, arguments[0]) } ?? -1)
        case ("subList", 2) where !collection.isSet:
            let from = try index(arguments[0], inclusive: true)
            let to = try index(arguments[1], inclusive: true)
            guard from <= to else { throw failure(.indexOutOfBounds, "fromIndex(\(from)) > toIndex(\(to))", range, context) }
            return .collection(XtendCollection(Array(collection.elements[from..<to])))
        case ("add", 1): result = .bool(collection.insert(arguments[0]))
        case ("add", 2) where !collection.isSet:
            collection.insert(arguments[1], at: try index(arguments[0], inclusive: true))
            result = .null
        case ("addAll", 1):
            var changed = false
            for element in try elements(of: arguments[0], range: range, context) { changed = collection.insert(element) || changed }
            result = .bool(changed)
        case ("remove", 1):
            if !collection.isSet, case .int = arguments[0] {
                result = collection.remove(at: try index(arguments[0]))
            } else {
                result = .bool(collection.remove(arguments[0]))
            }
        case ("removeAll", 1):
            var changed = false
            for element in try elements(of: arguments[0], range: range, context) { changed = collection.remove(element) || changed }
            result = .bool(changed)
        case ("clear", 0):
            collection.replaceAll([])
            result = .null
        case ("set", 2) where !collection.isSet:
            let position = try index(arguments[0])
            let previous = collection.elements[position]
            var updated = collection.elements
            updated[position] = arguments[1]
            collection.replaceAll(updated)
            result = previous
        default:
            return try await commonMember(.collection(collection), member, arguments)
        }
        try await writeBack(collection, range: range, context)
        return result
    }

    /// Evaluates a member of a map.
    func mapMember(_ map: XtendMap, _ name: String, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext)
        async throws -> XtendValue?
    {
        guard let member = Self.allowedName(name, in: XtendJavaSubset.mapMembers) else { return nil }
        if ["put", "putAll", "remove", "clear"].contains(member), !map.isMutable {
            throw failure(.immutableCollection, "Cannot change an immutable map with '\(member)'", range, context)
        }
        switch (member, arguments.count) {
        case ("size", 0): return .int(map.count)
        case ("isEmpty", 0): return .bool(map.count == 0)
        case ("get", 1): return map.get(arguments[0]) ?? .null
        case ("getOrDefault", 2): return map.get(arguments[0]) ?? arguments[1]
        case ("put", 2): return map.put(arguments[0], arguments[1]) ?? .null
        case ("putAll", 1):
            guard case .map(let other) = arguments[0] else { return nil }
            for (key, value) in zip(other.keys, other.values) { map.put(key, value) }
            return .null
        case ("remove", 1): return map.remove(arguments[0]) ?? .null
        case ("containsKey", 1): return .bool(map.get(arguments[0]) != nil)
        case ("containsValue", 1): return .bool(map.values.contains { XtendValue.areEqual($0, arguments[0]) })
        case ("keySet", 0): return .collection(XtendCollection(map.keys, isSet: true, isMutable: false))
        case ("values", 0): return .collection(XtendCollection(map.values, isMutable: false))
        case ("entrySet", 0):
            return .collection(
                XtendCollection(zip(map.keys, map.values).map { .pair(XtendPair($0, $1)) }, isSet: true, isMutable: false))
        case ("clear", 0):
            map.removeAll()
            return .null
        default:
            return try await commonMember(.map(map), member, arguments)
        }
    }
}

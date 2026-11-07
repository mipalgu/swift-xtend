//
//  XtendInterpreter+Expressions.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

extension XtendInterpreter {
    /// Evaluates an expression.
    ///
    /// - Parameters:
    ///   - expression: The expression.
    ///   - context: The scope, receiver and class of the running code.
    /// - Returns: The value of the expression.
    func eval(_ expression: XtendExpression, _ context: XtendContext) async throws -> XtendValue {
        let range = expression.range
        try step(range, context)
        switch expression.kind {
        case .nullLiteral: return .null
        case .booleanLiteral(let value): return .bool(value)
        case .integerLiteral(let value): return .int(value)
        case .doubleLiteral(let value): return .double(value)
        case .stringLiteral(let value): return .string(value)
        case .richString(let template):
            return .string(try await render(template, context))
        case .listLiteral(let elements):
            return .collection(XtendCollection(try await evalAll(elements, context), isMutable: false))
        case .setLiteral(let elements):
            let values = try await evalAll(elements, context)
            let pairs = values.compactMap { value -> XtendPair? in
                if case .pair(let pair) = value { return pair }
                return nil
            }
            if !values.isEmpty, pairs.count == values.count {
                return .map(XtendMap(pairs.map { ($0.key, $0.value) }, isMutable: false))
            }
            return .collection(XtendCollection(values, isSet: true, isMutable: false))
        case .lambda(let parameters, let explicitParameters, let body):
            return .lambda(XtendLambda(parameters: parameters, explicitParameters: explicitParameters, body: body, context: context))
        case .featureCall(let name, let arguments, let explicitCall):
            return try await featureCall(name, arguments: arguments, explicitCall: explicitCall, range: range, context)
        case .memberCall(let receiver, let name, let arguments, let explicitCall, let nullSafe):
            return try await memberCall(
                receiver, name: name, arguments: arguments, explicitCall: explicitCall, nullSafe: nullSafe, range: range,
                context)
        case .staticCall(let type, let name, let arguments, let explicitCall):
            let values = try await evalAll(arguments, context)
            return try await staticMember(type, name: name, arguments: values, explicitCall: explicitCall, range: range, context)
        case .assignment(let target, let value):
            let newValue = try await eval(value, context)
            try await assign(target, newValue, range: range, context)
            return newValue
        case .compoundAssignment(let operatorText, let target, let value):
            return try await compoundAssign(operatorText, target: target, value: value, range: range, context)
        case .binary(let operatorText, let left, let right):
            return try await binary(operatorText, left, right, range: range, context)
        case .unary(let operatorText, let operand):
            let value = try await eval(operand, context)
            switch (operatorText, value) {
            case ("!", .bool(let truth)): return .bool(!truth)
            case ("-", .int(let number)): return .int(0 &- number)
            case ("-", .double(let number)): return .double(-number)
            case ("+", .int), ("+", .double): return value
            default:
                throw failure(
                    .typeMismatch, "The operator '\(operatorText)' cannot be applied to \(value.typeDescription)", range, context)
            }
        case .postfix(let operatorText, let operand):
            let current = try await eval(operand, context)
            let next = try await arithmetic(operatorText == "++" ? "+" : "-", current, .int(1), range: range, context)
            try await assign(operand, next, range: range, context)
            return current
        case .instanceOf(let operand, let type):
            let value = try await eval(operand, context)
            let resolved = try resolveOrFail(type, context)
            return .bool(!value.isNull && conforms(value, to: resolved))
        case .cast(let operand, let type):
            let value = try await eval(operand, context)
            if value.isNull { return .null }
            let resolved = try resolveOrFail(type, context)
            switch (value, resolved) {
            case (.int(let number), .builtin(.double)): return .double(Double(number))
            case (.double(let number), .builtin(.integer)): return .int(Int(number))
            default:
                guard conforms(value, to: resolved) else {
                    throw failure(.invalidCast, "Cannot cast \(value.typeDescription) to \(resolved.name)", range, context)
                }
                return value
            }
        case .ifExpression(let condition, let then, let otherwise):
            if try await truth(of: condition, context) { return try await eval(then, context) }
            if let otherwise { return try await eval(otherwise, context) }
            return .null
        case .switchExpression(let switchExpression):
            return try await evalSwitch(switchExpression, context)
        case .forEach(let parameter, let iterable, let body):
            let collection = try await eval(iterable, context)
            for element in try elements(of: collection, range: iterable.range, context) {
                let inner = context.nested()
                inner.scope.declare(parameter.name, element)
                _ = try await eval(body, inner)
            }
            return .null
        case .basicFor(let initialisers, let condition, let updates, let body):
            let loop = context.nested()
            for initialiser in initialisers { _ = try await eval(initialiser, loop) }
            while true {
                if let condition, !(try await truth(of: condition, loop)) { break }
                _ = try await eval(body, loop.nested())
                for update in updates { _ = try await eval(update, loop) }
            }
            return .null
        case .whileLoop(let condition, let body):
            while try await truth(of: condition, context) { _ = try await eval(body, context.nested()) }
            return .null
        case .doWhileLoop(let body, let condition):
            repeat { _ = try await eval(body, context.nested()) } while try await truth(of: condition, context)
            return .null
        case .block(let expressions):
            let inner = context.nested()
            var result = XtendValue.null
            for item in expressions {
                result = try await eval(item, inner)
                if case .variableDeclaration = item.kind { result = .null }
            }
            return result
        case .variableDeclaration(let name, let type, let isMutable, let isExtension, let initialiser):
            var value = XtendValue.null
            if let initialiser { value = try await eval(initialiser, context) }
            if let type, let resolved = resolve(type, context) {
                switch (value, resolved) {
                case (.int(let number), .builtin(.double)): value = .double(Double(number))
                case (.null, .builtin(.integer)) where initialiser == nil: value = .int(0)
                case (.null, .builtin(.double)) where initialiser == nil: value = .double(0)
                default: break
                }
            }
            context.scope.declare(name, value, isMutable: isMutable, isExtension: isExtension)
            return .null
        case .returnExpression(let value):
            var result = XtendValue.null
            if let value { result = try await eval(value, context) }
            returnValue = result
            throw XtendReturnSignal()
        case .throwExpression(let value):
            let thrown = try await eval(value, context)
            let message: String
            if case .exception(let name, let text) = thrown {
                message = text.map { "\(name): \($0)" } ?? name
            } else {
                message = await text(of: thrown)
            }
            throw failure(.thrownException, message, range, context)
        case .constructorCall(let type, let arguments):
            let values = try await evalAll(arguments, context)
            return try await construct(type, arguments: values, range: range, context)
        case .typeLiteral(let type):
            return .type(try resolveOrFail(type, context))
        case .this:
            guard let this = context.this else {
                throw failure(.unknownFeature, "'this' is not available in a static context", range, context)
            }
            return .instance(this)
        case .superReference:
            throw failure(.unknownFeature, "'super' can only be used to call a method", range, context)
        case .unsupported(let construct):
            throw failure(.unsupportedConstruct, "The construct '\(construct)' is not supported by the interpreter", range, context)
        }
    }

    /// Evaluates expressions in order.
    func evalAll(_ expressions: [XtendExpression], _ context: XtendContext) async throws -> [XtendValue] {
        var values: [XtendValue] = []
        values.reserveCapacity(expressions.count)
        for expression in expressions { values.append(try await eval(expression, context)) }
        return values
    }

    /// Evaluates a condition, which must be a truth value.
    func truth(of expression: XtendExpression, _ context: XtendContext) async throws -> Bool {
        let value = try await eval(expression, context)
        guard case .bool(let truth) = value else {
            throw failure(.typeMismatch, "A condition must be a Boolean but is \(value.typeDescription)", expression.range, context)
        }
        return truth
    }

    /// Resolves a type reference or fails.
    func resolveOrFail(_ type: XtendTypeReference, _ context: XtendContext) throws -> XtendRuntimeType {
        guard let resolved = resolve(type, context) else {
            throw failure(.unsupportedJavaType, "Unknown type '\(type.name)'", type.range, context)
        }
        return resolved
    }

    /// The elements of an iterable value.
    func elements(of value: XtendValue, range: SourceRange, _ context: XtendContext) throws -> [XtendValue] {
        switch value {
        case .collection(let collection): return collection.elements
        case .range(let integers): return integers.elements.map { .int($0) }
        case .map(let map): return zip(map.keys, map.values).map { .pair(XtendPair($0, $1)) }
        case .null: throw failure(.nullPointer, "Cannot iterate over null", range, context)
        default: throw failure(.typeMismatch, "Cannot iterate over \(value.typeDescription)", range, context)
        }
    }

    // MARK: - Switch

    /// Evaluates a switch expression and returns the value of the first matching case.
    ///
    /// A case matches when its type guard (if any) conforms and its condition (if any) holds. Matching cases without
    /// a body fall through to the next case with one; otherwise the default branch is evaluated.
    ///
    /// - Parameters:
    ///   - switchExpression: The switch expression to evaluate.
    ///   - context: The evaluation context.
    /// - Returns: The value of the selected branch, or null if nothing matches.
    /// - Throws: An Xtend failure if evaluating the subject, a guard or a branch fails.
    private func evalSwitch(_ switchExpression: XtendSwitch, _ context: XtendContext) async throws -> XtendValue {
        let subject = try await eval(switchExpression.subject, context)
        let inner = context.nested()
        if let name = switchExpression.declaredName { inner.scope.declare(name, subject) }
        var matched: Int?
        for (index, item) in switchExpression.cases.enumerated() {
            if let typeGuard = item.typeGuard {
                let type = try resolveOrFail(typeGuard, context)
                if subject.isNull || !conforms(subject, to: type) { continue }
            }
            if let condition = item.condition {
                let value = try await eval(condition, inner)
                if case .bool(let truth) = value, subject.builtinKind != .boolean {
                    if !truth { continue }
                } else if !XtendValue.areEqual(value, subject) {
                    continue
                }
            }
            matched = index
            break
        }
        if let matched {
            for item in switchExpression.cases[matched...] {
                if let body = item.body { return try await eval(body, inner) }
            }
            return .null
        }
        if let defaultBranch = switchExpression.defaultBranch { return try await eval(defaultBranch, inner) }
        return .null
    }

    // MARK: - Operators

    /// Evaluates a binary operator application.
    ///
    /// Short-circuiting operators evaluate their right operand only when required.
    ///
    /// - Parameters:
    ///   - operatorText: The operator symbol.
    ///   - left: The left operand expression.
    ///   - right: The right operand expression.
    ///   - range: The source range used for failure reporting.
    ///   - context: The evaluation context.
    /// - Returns: The result of applying the operator.
    /// - Throws: An Xtend failure if an operand is invalid for the operator.
    private func binary(
        _ operatorText: String, _ left: XtendExpression, _ right: XtendExpression, range: SourceRange,
        _ context: XtendContext
    ) async throws -> XtendValue {
        switch operatorText {
        case "&&":
            guard try await truth(of: left, context) else { return .bool(false) }
            return .bool(try await truth(of: right, context))
        case "||":
            if try await truth(of: left, context) { return .bool(true) }
            return .bool(try await truth(of: right, context))
        case "?:":
            let value = try await eval(left, context)
            return value.isNull ? try await eval(right, context) : value
        case "=>":
            let value = try await eval(left, context)
            let function = try await eval(right, context)
            _ = try await callFunction(function, [value], range: right.range, context)
            return value
        default:
            let lhs = try await eval(left, context)
            let rhs = try await eval(right, context)
            return try await apply(operatorText, lhs, rhs, range: range, context)
        }
    }

    /// Applies a binary operator to evaluated operands.
    func apply(
        _ operatorText: String, _ lhs: XtendValue, _ rhs: XtendValue, range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        switch operatorText {
        case "==": return .bool(XtendValue.areEqual(lhs, rhs))
        case "!=": return .bool(!XtendValue.areEqual(lhs, rhs))
        case "===": return .bool(XtendValue.areIdentical(lhs, rhs))
        case "!==": return .bool(!XtendValue.areIdentical(lhs, rhs))
        case "->": return .pair(XtendPair(lhs, rhs))
        case "..", "..<", ">..":
            guard case .int(let start) = lhs, case .int(let end) = rhs else {
                throw failure(.typeMismatch, "Ranges need whole numbers", range, context)
            }
            switch operatorText {
            case "..": return .range(XtendRange(start: start, end: end, isInclusive: true, isDescending: start > end))
            case "..<": return .range(XtendRange(start: start, end: end, isInclusive: false, isDescending: false))
            default: return .range(XtendRange(start: start - 1, end: end, isInclusive: true, isDescending: true))
            }
        case "+":
            if case .string = lhs { return .string(await text(of: lhs) + text(of: rhs)) }
            if case .string = rhs { return .string(await text(of: lhs) + text(of: rhs)) }
            if isIterable(lhs), isIterable(rhs) {
                let combined = try elements(of: lhs, range: range, context) + elements(of: rhs, range: range, context)
                return .collection(XtendCollection(combined, isMutable: false))
            }
            return try await arithmetic(operatorText, lhs, rhs, range: range, context)
        case "-", "*", "/", "%", "**":
            return try await arithmetic(operatorText, lhs, rhs, range: range, context)
        case "<", "<=", ">", ">=":
            let order = try compare(lhs, rhs, range: range, context)
            switch operatorText {
            case "<": return .bool(order < 0)
            case "<=": return .bool(order <= 0)
            case ">": return .bool(order > 0)
            default: return .bool(order >= 0)
            }
        default:
            throw failure(.unsupportedConstruct, "The operator '\(operatorText)' is not supported", range, context)
        }
    }

    /// Whether a value can be iterated.
    func isIterable(_ value: XtendValue) -> Bool {
        switch value {
        case .collection, .range: return true
        default: return false
        }
    }

    /// Applies an arithmetic operator.
    func arithmetic(
        _ operatorText: String, _ lhs: XtendValue, _ rhs: XtendValue, range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        if case .int(let left) = lhs, case .int(let right) = rhs {
            switch operatorText {
            case "+": return .int(left &+ right)
            case "-": return .int(left &- right)
            case "*": return .int(left &* right)
            case "**": return .double(pow(Double(left), Double(right)))
            case "/", "%":
                guard right != 0 else { throw failure(.divisionByZero, "Division by zero", range, context) }
                return .int(operatorText == "/" ? left / right : left % right)
            default: break
            }
        }
        guard let left = Self.number(lhs), let right = Self.number(rhs) else {
            throw failure(
                .typeMismatch,
                "The operator '\(operatorText)' cannot be applied to \(lhs.typeDescription) and \(rhs.typeDescription)",
                range, context)
        }
        switch operatorText {
        case "+": return .double(left + right)
        case "-": return .double(left - right)
        case "*": return .double(left * right)
        case "/": return .double(left / right)
        case "%": return .double(left.truncatingRemainder(dividingBy: right))
        case "**": return .double(pow(left, right))
        default: throw failure(.unsupportedConstruct, "The operator '\(operatorText)' is not supported", range, context)
        }
    }

    /// The numeric value of a number.
    static func number(_ value: XtendValue) -> Double? {
        switch value {
        case .int(let number): return Double(number)
        case .double(let number): return number
        default: return nil
        }
    }

    /// Compares numbers or strings.
    ///
    /// - Returns: A negative number, zero or a positive number.
    func compare(_ lhs: XtendValue, _ rhs: XtendValue, range: SourceRange, _ context: XtendContext) throws -> Int {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)): return left < right ? -1 : left == right ? 0 : 1
        case (.string(let left), .string(let right)): return Self.compareStrings(left, right)
        case (.bool(let left), .bool(let right)): return left == right ? 0 : (left ? 1 : -1)
        default:
            guard let left = Self.number(lhs), let right = Self.number(rhs) else {
                throw failure(.typeMismatch, "Cannot compare \(lhs.typeDescription) with \(rhs.typeDescription)", range, context)
            }
            return left < right ? -1 : left == right ? 0 : 1
        }
    }

    /// Compares strings by their UTF-16 code units, as Java's `compareTo` does.
    static func compareStrings(_ lhs: String, _ rhs: String) -> Int {
        for (left, right) in zip(lhs.utf16, rhs.utf16) where left != right {
            return Int(left) - Int(right)
        }
        return lhs.utf16.count - rhs.utf16.count
    }

    // MARK: - Assignment

    /// Assigns a value to a variable, field or feature.
    func assign(_ target: XtendExpression, _ value: XtendValue, range: SourceRange, _ context: XtendContext) async throws {
        switch target.kind {
        case .featureCall(let name, _, _):
            if let variable = context.scope.lookup(name) {
                guard variable.isMutable else {
                    throw failure(.invalidAssignment, "Cannot assign a value to the final variable '\(name)'", range, context)
                }
                _ = context.scope.assign(name, value)
                return
            }
            if let it = context.scope.lookup(XtendLanguage.implicitParameter)?.value, !it.isNull,
                try await setMember(of: it, name, value, range: range, context)
            {
                return
            }
            if let this = context.this, classChain(this.className).contains(where: { info in
                info.declaration.fields.contains { $0.name == name && !$0.modifiers.isStatic }
            }) {
                this.fields[name] = value
                return
            }
            if let className = context.className, try await staticField(name, in: className, range: range) != nil {
                for info in classChain(className) where info.declaration.fields.contains(where: { $0.name == name }) {
                    staticFields[info.declaration.qualifiedName, default: [:]][name] = value
                    return
                }
            }
            throw failure(.invalidAssignment, "Cannot assign to '\(name)': no such variable, field or feature", range, context)
        case .memberCall(let receiverExpression, let name, _, _, let nullSafe):
            let receiver = try await eval(receiverExpression, context)
            if receiver.isNull {
                if nullSafe { return }
                throw failure(.nullPointer, "Cannot assign '\(name)' of null", range, context)
            }
            guard try await setMember(of: receiver, name, value, range: range, context) else {
                throw failure(
                    .invalidAssignment, "Cannot assign '\(name)' of \(receiver.typeDescription): no such feature", range, context)
            }
        default:
            throw failure(.invalidAssignment, "This expression cannot be assigned", range, context)
        }
    }

    /// Changes a feature of a model object or a field of an instance.
    ///
    /// - Returns: `false` if the receiver has no such feature or field.
    func setMember(of receiver: XtendValue, _ name: String, _ value: XtendValue, range: SourceRange, _ context: XtendContext)
        async throws -> Bool
    {
        switch receiver {
        case .object(let reference):
            return try await setFeature(of: reference, name, value, range: range, context)
        case .instance(let instance):
            guard classChain(instance.className).contains(where: { $0.declaration.fields.contains { $0.name == name } }) else {
                return false
            }
            instance.fields[name] = value
            return true
        default:
            return false
        }
    }

    /// Evaluates a compound assignment such as `+=` and stores the result in the target.
    ///
    /// - Parameters:
    ///   - operatorText: The compound assignment operator symbol.
    ///   - target: The assignable expression receiving the result.
    ///   - value: The right-hand side expression.
    ///   - range: The source range used for failure reporting.
    ///   - context: The evaluation context.
    /// - Returns: The assigned value.
    /// - Throws: An Xtend failure if the target is immutable or the operands are invalid.
    private func compoundAssign(
        _ operatorText: String, target: XtendExpression, value: XtendExpression, range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        let current = try await eval(target, context)
        let operand = try await eval(value, context)
        if case .collection(let collection) = current, operatorText == "+=" || operatorText == "-=" {
            guard collection.isMutable else {
                throw failure(.immutableCollection, "Cannot change an immutable collection", range, context)
            }
            let items = isIterable(operand) ? try elements(of: operand, range: range, context) : [operand]
            var changed = false
            for item in items {
                changed = (operatorText == "+=" ? collection.insert(item) : collection.remove(item)) || changed
            }
            try await writeBack(collection, range: range, context)
            return .bool(changed)
        }
        if case .map(let map) = current, operatorText == "+=" {
            guard map.isMutable else { throw failure(.immutableCollection, "Cannot change an immutable map", range, context) }
            if case .pair(let pair) = operand {
                return map.put(pair.key, pair.value) ?? .null
            }
            if case .map(let other) = operand {
                for (key, entry) in zip(other.keys, other.values) { map.put(key, entry) }
                return .null
            }
        }
        let result = try await apply(String(operatorText.dropLast()), current, operand, range: range, context)
        try await assign(target, result, range: range, context)
        return result
    }

    // MARK: - Construction

    /// Creates an instance of a type from a constructor call.
    ///
    /// - Parameters:
    ///   - type: The type reference to instantiate.
    ///   - arguments: The evaluated constructor arguments.
    ///   - range: The source range used for failure reporting.
    ///   - context: The evaluation context.
    /// - Returns: The newly created value.
    /// - Throws: An Xtend failure if the type is unknown or cannot be constructed with the arguments.
    private func construct(
        _ type: XtendTypeReference, arguments: [XtendValue], range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue {
        guard let resolved = resolve(type, context) else {
            throw failure(.unsupportedJavaConstructor, "Cannot create an instance of the unknown type '\(type.name)'", range, context)
        }
        switch resolved {
        case .xtendClass(let name):
            return .instance(try await instantiate(name, arguments: arguments, range: range))
        case .modelClass(let eClass):
            guard arguments.isEmpty else {
                throw failure(.invalidArgument, "Model objects are created without arguments", range, context)
            }
            guard !eClass.isAbstract, !eClass.isInterface else {
                throw failure(.typeMismatch, "The abstract class '\(eClass.name)' cannot be instantiated", range, context)
            }
            return await createObject(eClass)
        case .builtin(.list), .builtin(.set):
            let isSet: Bool
            if case .builtin(.set) = resolved { isSet = true } else { isSet = false }
            if let first = arguments.first, isIterable(first) {
                return .collection(XtendCollection(try elements(of: first, range: range, context), isSet: isSet))
            }
            return .collection(XtendCollection([], isSet: isSet))
        case .builtin(.map):
            let map = XtendMap()
            if case .map(let source)? = arguments.first {
                for (key, value) in zip(source.keys, source.values) { map.put(key, value) }
            }
            return .map(map)
        case .builtin(.exception):
            let message = arguments.isEmpty ? nil : await text(of: arguments[0])
            return .exception(type.simpleName, message)
        case .builtin(.object):
            return .instance(newInstance(of: XtendBuiltinType.object.rawValue))
        default:
            throw failure(
                .unsupportedJavaConstructor, "The type '\(type.name)' cannot be instantiated by the interpreter", range, context)
        }
    }

    // MARK: - Templates

    /// Renders a rich string.
    func render(_ template: XtendTemplate, _ context: XtendContext) async throws -> String {
        var builder = XtendStringConcatenation()
        try await execute(template.instructions, into: &builder, context)
        return builder.text
    }

    /// Executes template instructions, appending their output to a string builder.
    ///
    /// - Parameters:
    ///   - instructions: The template instructions to execute.
    ///   - builder: The string concatenation receiving the output.
    ///   - context: The evaluation context.
    /// - Throws: An Xtend failure if evaluating an embedded expression fails.
    private func execute(
        _ instructions: [XtendTemplateInstruction], into builder: inout XtendStringConcatenation, _ context: XtendContext
    ) async throws {
        for instruction in instructions {
            switch instruction {
            case .literal(let text):
                builder.append(text)
            case .newLine:
                builder.newLine()
            case .newLineIfNotEmpty:
                builder.newLineIfNotEmpty()
            case .expression(let expression, let indentation):
                let value = try await eval(expression, context)
                if !value.isNull { builder.append(await text(of: value), indentation: indentation) }
            case .loop(let loop):
                let collection = try await eval(loop.iterable, context)
                let items = try elements(of: collection, range: loop.iterable.range, context)
                for (index, item) in items.enumerated() {
                    if index == 0 {
                        if let before = loop.before {
                            let value = try await eval(before, context)
                            if !value.isNull { builder.append(await text(of: value), indentation: loop.indentation) }
                        }
                    } else if let separator = loop.separator {
                        let value = try await eval(separator, context)
                        if !value.isNull { builder.appendImmediate(await text(of: value), indentation: loop.indentation) }
                    }
                    let inner = context.nested()
                    inner.scope.declare(loop.parameter.name, item)
                    try await execute(loop.body, into: &builder, inner)
                }
                if !items.isEmpty, let after = loop.after {
                    let value = try await eval(after, context)
                    if !value.isNull { builder.append(await text(of: value), indentation: loop.indentation) }
                }
            case .conditional(let conditional):
                var matched = false
                for branch in conditional.branches {
                    if try await truth(of: branch.condition, context) {
                        try await execute(branch.body, into: &builder, context)
                        matched = true
                        break
                    }
                }
                if !matched, let otherwise = conditional.otherwise {
                    try await execute(otherwise, into: &builder, context)
                }
            }
        }
    }
}

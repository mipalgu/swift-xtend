//
//  XtendInterpreter+Library.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The functions of the Xbase library that the interpreter implements natively.
///
/// Global functions are called without a receiver, such as `newArrayList(1, 2)` or
/// `println(x)`. Extension functions are called on a receiver, such as `list.map[name]`
/// or `name.toFirstUpper`.
public enum XtendLibrary {
    /// The functions that are called without a receiver (from `CollectionLiterals` and
    /// `InputOutput`).
    public static let globalFunctions: Set<String> = [
        "newArrayList", "newLinkedList", "newHashSet", "newLinkedHashSet", "newTreeSet", "newHashMap", "newLinkedHashMap",
        "newTreeMap", "emptyList", "emptySet", "emptyMap", "newImmutableList", "newImmutableSet", "newImmutableMap",
        "println", "print",
    ]

    /// The extension functions on lists, sets and ranges (from `IterableExtensions`,
    /// `ListExtensions` and `CollectionExtensions`).
    public static let iterableFunctions: Set<String> = [
        "map", "filter", "filterNull", "forEach", "exists", "forall", "findFirst", "findLast", "head", "last", "tail",
        "take", "drop", "takeWhile", "dropWhile", "join", "sortBy", "sort", "sortWith", "reverse", "reverseView",
        "toList", "toSet", "toMap", "toInvertedMap", "groupBy", "flatten", "flatMap", "size", "isEmpty",
        "isNullOrEmpty", "reduce", "fold", "indexed", "max", "min", "maxBy", "minBy", "toIterable", "elementsEqual",
        "contains",
    ]

    /// The extension functions on strings (from `StringExtensions`).
    public static let stringFunctions: Set<String> = ["toFirstUpper", "toFirstLower", "isNullOrEmpty"]

    /// The extension functions on maps (from `MapExtensions`).
    public static let mapFunctions: Set<String> = ["forEach", "filter", "mapValues"]

    /// The extension functions on whole numbers (from `IntegerExtensions`).
    public static let integerFunctions: Set<String> = ["upTo"]
}

extension XtendInterpreter {
    /// Calls a library function without a receiver.
    ///
    /// - Returns: The result, or `nil` if there is no such function.
    func globalFunction(_ name: String, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext)
        async throws -> XtendValue?
    {
        guard XtendLibrary.globalFunctions.contains(name) else { return nil }
        switch name {
        case "newArrayList", "newLinkedList":
            return .collection(XtendCollection(arguments))
        case "newHashSet", "newLinkedHashSet", "newTreeSet":
            return .collection(XtendCollection(arguments, isSet: true))
        case "newImmutableList":
            return .collection(XtendCollection(arguments, isMutable: false))
        case "newImmutableSet":
            return .collection(XtendCollection(arguments, isSet: true, isMutable: false))
        case "newHashMap", "newLinkedHashMap", "newTreeMap", "newImmutableMap":
            let map = XtendMap()
            for argument in arguments {
                guard case .pair(let pair) = argument else {
                    throw failure(.invalidArgument, "'\(name)' needs pairs created with '->'", range, context)
                }
                map.put(pair.key, pair.value)
            }
            return .map(name == "newImmutableMap" ? XtendMap(zip(map.keys, map.values).map { ($0, $1) }, isMutable: false) : map)
        case "emptyList":
            return arguments.isEmpty ? .collection(XtendCollection([], isMutable: false)) : nil
        case "emptySet":
            return arguments.isEmpty ? .collection(XtendCollection([], isSet: true, isMutable: false)) : nil
        case "emptyMap":
            return arguments.isEmpty ? .map(XtendMap([], isMutable: false)) : nil
        case "println", "print":
            guard arguments.count <= 1 else { return nil }
            let text = arguments.isEmpty ? "" : await text(of: arguments[0])
            outputText += text + (name == "println" ? XtendLanguage.lineDelimiter : "")
            return arguments.first ?? .null
        default:
            return nil
        }
    }

    /// Calls a library extension function on a receiver.
    ///
    /// - Returns: The result, or `nil` if there is no such function for the receiver.
    func extensionFunction(
        _ name: String, receiver: XtendValue, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue? {
        switch receiver {
        case .collection, .range:
            guard let function = Self.allowedName(name, in: XtendLibrary.iterableFunctions) else { return nil }
            return try await iterableFunction(function, receiver, arguments, range: range, context)
        case .string(let text):
            guard let function = Self.allowedName(name, in: XtendLibrary.stringFunctions), arguments.isEmpty else { return nil }
            switch function {
            case "toFirstUpper": return .string(text.prefix(1).uppercased() + text.dropFirst())
            case "toFirstLower": return .string(text.prefix(1).lowercased() + text.dropFirst())
            default: return .bool(text.isEmpty)
            }
        case .map(let map):
            guard let function = Self.allowedName(name, in: XtendLibrary.mapFunctions), arguments.count == 1 else { return nil }
            let entries = Array(zip(map.keys, map.values))
            switch function {
            case "forEach":
                for (key, value) in entries { _ = try await callFunction(arguments[0], [key, value], range: range, context) }
                return .null
            case "filter":
                let result = XtendMap()
                for (key, value) in entries {
                    if try await predicate(arguments[0], [key, value], range: range, context) { result.put(key, value) }
                }
                return .map(result)
            default:
                let result = XtendMap()
                for (key, value) in entries {
                    result.put(key, try await callFunction(arguments[0], [value], range: range, context))
                }
                return .map(result)
            }
        case .int(let start):
            guard Self.allowedName(name, in: XtendLibrary.integerFunctions) != nil, arguments.count == 1,
                case .int(let end) = arguments[0]
            else { return nil }
            return .range(XtendRange(start: start, end: end, isInclusive: true, isDescending: false))
        case .null:
            if Self.allowedName(name, in: ["isNullOrEmpty"]) != nil, arguments.isEmpty { return .bool(true) }
            return nil
        default:
            return nil
        }
    }

    /// Calls a lambda expression that must return a truth value.
    private func predicate(_ function: XtendValue, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext)
        async throws -> Bool
    {
        let result = try await callFunction(function, arguments, range: range, context)
        guard case .bool(let truth) = result else {
            throw failure(.typeMismatch, "The lambda expression must return a Boolean but returned \(result.typeDescription)", range, context)
        }
        return truth
    }

    /// How ``sorted(_:by:range:_:)`` orders values.
    private enum SortOrder {
        /// The natural order of numbers and strings.
        case natural
        /// The natural order of the values of pairs.
        case pairValues
        /// The order a comparator lambda expression defines.
        case comparator(XtendValue)
    }

    /// Whether one value comes before another in a sort order.
    private func isOrdered(_ left: XtendValue, before right: XtendValue, by order: SortOrder, range: SourceRange, _ context: XtendContext)
        async throws -> Bool
    {
        switch order {
        case .natural:
            return try compare(left, right, range: range, context) < 0
        case .pairValues:
            guard case .pair(let lhs) = left, case .pair(let rhs) = right else { return false }
            return try compare(lhs.value, rhs.value, range: range, context) < 0
        case .comparator(let function):
            let result = try await callFunction(function, [left, right], range: range, context)
            guard case .int(let comparison) = result else {
                throw failure(.typeMismatch, "A comparator must return a whole number", range, context)
            }
            return comparison < 0
        }
    }

    /// Sorts values, keeping equal values in their order.
    private func sorted(_ values: [XtendValue], by order: SortOrder, range: SourceRange, _ context: XtendContext)
        async throws -> [XtendValue]
    {
        guard values.count > 1 else { return values }
        let middle = values.count / 2
        let left = try await sorted(Array(values[..<middle]), by: order, range: range, context)
        let right = try await sorted(Array(values[middle...]), by: order, range: range, context)
        var result: [XtendValue] = []
        result.reserveCapacity(values.count)
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < left.count, rightIndex < right.count {
            if try await isOrdered(right[rightIndex], before: left[leftIndex], by: order, range: range, context) {
                result.append(right[rightIndex])
                rightIndex += 1
            } else {
                result.append(left[leftIndex])
                leftIndex += 1
            }
        }
        result.append(contentsOf: left[leftIndex...])
        result.append(contentsOf: right[rightIndex...])
        return result
    }

    /// Calls a library function on a list, set or range.
    private func iterableFunction(
        _ function: String, _ receiver: XtendValue, _ arguments: [XtendValue], range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue? {
        let items = try elements(of: receiver, range: range, context)
        /// Wraps values in a list value.
        ///
        /// - Parameters:
        ///   - values: The elements of the list.
        ///   - mutable: Whether the list can be modified.
        /// - Returns: The list value.
        func list(_ values: [XtendValue], mutable: Bool = false) -> XtendValue {
            .collection(XtendCollection(values, isMutable: mutable))
        }
        switch (function, arguments.count) {
        case ("map", 1):
            var result: [XtendValue] = []
            for item in items { result.append(try await callFunction(arguments[0], [item], range: range, context)) }
            return list(result)
        case ("filter", 1):
            if case .type(let type) = arguments[0] {
                return list(items.filter { !$0.isNull && conforms($0, to: type) })
            }
            var result: [XtendValue] = []
            for item in items {
                if try await predicate(arguments[0], [item], range: range, context) { result.append(item) }
            }
            return list(result)
        case ("filterNull", 0): return list(items.filter { !$0.isNull })
        case ("forEach", 1):
            let takesIndex: Bool
            if case .lambda(let lambda) = arguments[0] { takesIndex = lambda.explicitParameters && lambda.parameters.count == 2 } else {
                takesIndex = false
            }
            for (index, item) in items.enumerated() { _ = try await callFunction(arguments[0], takesIndex ? [item, .int(index)] : [item], range: range, context) }
            return .null
        case ("exists", 1):
            for item in items {
                if try await predicate(arguments[0], [item], range: range, context) { return .bool(true) }
            }
            return .bool(false)
        case ("forall", 1):
            for item in items {
                if !(try await predicate(arguments[0], [item], range: range, context)) { return .bool(false) }
            }
            return .bool(true)
        case ("findFirst", 1):
            for item in items {
                if try await predicate(arguments[0], [item], range: range, context) { return item }
            }
            return .null
        case ("findLast", 1):
            for item in items.reversed() {
                if try await predicate(arguments[0], [item], range: range, context) { return item }
            }
            return .null
        case ("head", 0): return items.first ?? .null
        case ("last", 0): return items.last ?? .null
        case ("tail", 0): return list(Array(items.dropFirst()))
        case ("take", 1), ("drop", 1):
            guard case .int(let count) = arguments[0], count >= 0 else {
                throw failure(.invalidArgument, "'\(function)' needs a non-negative count", range, context)
            }
            return list(function == "take" ? Array(items.prefix(count)) : Array(items.dropFirst(count)))
        case ("takeWhile", 1), ("dropWhile", 1):
            var prefix = 0
            while prefix < items.count, try await predicate(arguments[0], [items[prefix]], range: range, context) { prefix += 1 }
            return list(function == "takeWhile" ? Array(items[..<prefix]) : Array(items[prefix...]))
        case ("join", 0), ("join", 1), ("join", 2), ("join", 4):
            var texts: [String] = []
            let mapper: XtendValue? = arguments.count == 2 ? arguments[1] : arguments.count == 4 ? arguments[3] : nil
            for item in items {
                var value = item
                if let mapper { value = try await callFunction(mapper, [item], range: range, context) }
                texts.append(await text(of: value))
            }
            switch arguments.count {
            case 0: return .string(texts.joined())
            case 4:
                guard !items.isEmpty else { return .string("") }
                return .string(
                    await text(of: arguments[0]) + texts.joined(separator: await text(of: arguments[1])) + text(of: arguments[2]))
            default: return .string(texts.joined(separator: await text(of: arguments[0])))
            }
        case ("sort", 0):
            return list(try await sorted(items, by: .natural, range: range, context), mutable: true)
        case ("sortBy", 1):
            var keyed: [XtendValue] = []
            for item in items { keyed.append(.pair(XtendPair(item, try await callFunction(arguments[0], [item], range: range, context)))) }
            let ordered = try await sorted(keyed, by: .pairValues, range: range, context)
            return list(ordered.map { if case .pair(let pair) = $0 { return pair.key } else { return .null } }, mutable: true)
        case ("sortWith", 1):
            return list(try await sorted(items, by: .comparator(arguments[0]), range: range, context), mutable: true)
        case ("reverse", 0), ("reverseView", 0): return list(items.reversed())
        case ("toList", 0): return list(items, mutable: true)
        case ("toIterable", 0): return receiver
        case ("toSet", 0): return .collection(XtendCollection(items, isSet: true))
        case ("toMap", 1), ("toMap", 2):
            let map = XtendMap()
            for item in items {
                let key = try await callFunction(arguments[0], [item], range: range, context)
                let value = arguments.count == 2 ? try await callFunction(arguments[1], [item], range: range, context) : item
                map.put(key, value)
            }
            return .map(map)
        case ("toInvertedMap", 1):
            let map = XtendMap()
            for item in items { map.put(item, try await callFunction(arguments[0], [item], range: range, context)) }
            return .map(map)
        case ("groupBy", 1):
            let map = XtendMap()
            for item in items {
                let key = try await callFunction(arguments[0], [item], range: range, context)
                if case .collection(let group)? = map.get(key) {
                    group.insert(item)
                } else {
                    map.put(key, .collection(XtendCollection([item])))
                }
            }
            return .map(map)
        case ("flatten", 0):
            var result: [XtendValue] = []
            for item in items { result.append(contentsOf: try elements(of: item, range: range, context)) }
            return list(result)
        case ("flatMap", 1):
            var result: [XtendValue] = []
            for item in items { result.append(contentsOf: try elements(of: try await callFunction(arguments[0], [item], range: range, context), range: range, context)) }
            return list(result)
        case ("size", 0): return .int(items.count)
        case ("isEmpty", 0), ("isNullOrEmpty", 0): return .bool(items.isEmpty)
        case ("contains", 1): return .bool(items.contains { XtendValue.areEqual($0, arguments[0]) })
        case ("reduce", 1):
            guard var result = items.first else { return .null }
            for item in items.dropFirst() { result = try await callFunction(arguments[0], [result, item], range: range, context) }
            return result
        case ("fold", 2):
            var result = arguments[0]
            for item in items { result = try await callFunction(arguments[1], [result, item], range: range, context) }
            return result
        case ("indexed", 0):
            return list(items.enumerated().map { .pair(XtendPair(.int($0.offset), $0.element)) })
        case ("max", 0), ("min", 0):
            guard var best = items.first else { return .null }
            for item in items.dropFirst() {
                let order = try compare(item, best, range: range, context)
                if function == "max" ? order > 0 : order < 0 { best = item }
            }
            return best
        case ("maxBy", 1), ("minBy", 1):
            guard let first = items.first else { return .null }
            var best = first
            var bestKey = try await callFunction(arguments[0], [first], range: range, context)
            for item in items.dropFirst() {
                let key = try await callFunction(arguments[0], [item], range: range, context)
                let order = try compare(key, bestKey, range: range, context)
                if function == "maxBy" ? order > 0 : order < 0 {
                    best = item
                    bestKey = key
                }
            }
            return best
        case ("elementsEqual", 1):
            let others = try elements(of: arguments[0], range: range, context)
            return .bool(others.count == items.count && zip(items, others).allSatisfy { XtendValue.areEqual($0, $1) })
        default:
            return nil
        }
    }
}

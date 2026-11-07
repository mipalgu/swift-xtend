//
//  XtendHostValue.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// A value passed into or returned from an ``XtendInterpreter``.
///
/// Inside the interpreter, collections, maps and class instances have Java reference
/// semantics. Host values are immutable snapshots that can cross concurrency domains.
/// Values without a host representation, such as lambda expressions and class instances,
/// are returned as ``other(_:)`` with their textual form.
public indirect enum XtendHostValue: Sendable, CustomStringConvertible {
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
    /// A list.
    case list([XtendHostValue])
    /// A set, in insertion order.
    case set([XtendHostValue])
    /// A map as its entries in insertion order.
    case map([(key: XtendHostValue, value: XtendHostValue)])
    /// A pair.
    case pair(XtendHostValue, XtendHostValue)
    /// A model object by identifier, with the resource that holds it, if known.
    case object(EUUID, Resource?)
    /// A model resource.
    case resource(Resource)
    /// A file system access for generators.
    case fileSystem(any XtendFileSystemAccess)
    /// A value without a host representation, by its textual form.
    case other(String)

    /// The string, if this is a string.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The whole number, if this is one.
    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// The truth value, if this is one.
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The elements, if this is a list or a set.
    public var elements: [XtendHostValue]? {
        switch self {
        case .list(let elements), .set(let elements): return elements
        default: return nil
        }
    }

    /// The identifier, if this is a model object.
    public var objectID: EUUID? {
        if case .object(let id, _) = self { return id }
        return nil
    }

    /// A textual form of the value, following Java's conventions for numbers and collections.
    public var description: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return String(value)
        case .int(let value): return String(value)
        case .double(let value): return XtendInterpreter.javaText(value)
        case .string(let value): return value
        case .list(let elements), .set(let elements): return "[" + elements.map(\.description).joined(separator: ", ") + "]"
        case .map(let entries): return "{" + entries.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") + "}"
        case .pair(let key, let value): return "\(key)->\(value)"
        case .object(let id, _): return "EObject(\(id))"
        case .resource(let resource): return resource.uri
        case .fileSystem: return XtendBuiltinType.fileSystemAccess.rawValue
        case .other(let text): return text
        }
    }
}

//
//  XtendInterpreter+Model.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

extension XtendInterpreter {
    // MARK: - Wrapping objects

    /// The built-in kind of a native metamodel element.
    static func metaKind(of object: any EObject) -> XtendBuiltinType? {
        switch object {
        case is DynamicEObject: return nil
        case is EPackage: return .ePackage
        case is EClass: return .eClass
        case is EEnum: return .eEnum
        case is EDataType: return .eDataType
        case is EAttribute: return .eAttribute
        case is EReference: return .eReference
        case is EEnumLiteral: return .eEnumLiteral
        default: return object is any ENamedElement ? .eNamedElement : nil
        }
    }

    /// Wraps a model object, recording the resource that holds it.
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - holder: The resource known to hold the object, if any; otherwise the resources of
    ///     the interpreter are searched.
    func wrap(_ object: any EObject, holder: Resource? = nil) async -> XtendValue {
        var resource = holder
        if resource == nil {
            for candidate in resources where await candidate.resolve(object.id)?.id == object.id {
                resource = candidate
                break
            }
        }
        let dynamicClass = (object as? DynamicEObject)?.eClass
        return .object(
            XtendObjectReference(
                id: object.id, resource: resource, eClass: dynamicClass,
                metaKind: dynamicClass == nil ? Self.metaKind(of: object) : nil,
                snapshot: resource == nil ? object : nil))
    }

    /// Finds an object by identifier in the resources of the interpreter.
    func objectValue(id: EUUID, preferring preferred: Resource?) async -> XtendValue? {
        var candidates = resources
        if let preferred {
            candidates.removeAll { $0 === preferred }
            candidates.insert(preferred, at: 0)
        }
        for resource in candidates {
            if let object = await resource.resolve(id), object.id == id {
                return await wrap(object, holder: resource)
            }
        }
        return nil
    }

    /// The current state of a referenced object.
    func resolveObject(_ reference: XtendObjectReference) async -> (any EObject)? {
        if let snapshot = reference.snapshot { return snapshot }
        return await reference.resource?.resolve(reference.id)
    }

    /// The class that describes an object: its metamodel class, or the Ecore class of a
    /// metamodel element.
    static func metaClass(of object: any EObject) -> EClass? {
        object.eClass as? EClass
    }

    /// Creates a model object in the target resource.
    func createObject(_ eClass: EClass) async -> XtendValue {
        let object = DynamicEObject(eClass: eClass)
        await targetResource.add(object)
        return .object(XtendObjectReference(id: object.id, resource: targetResource, eClass: eClass, metaKind: nil, snapshot: nil))
    }

    // MARK: - Reading and writing features

    /// Converts a stored feature value into an interpreter value.
    func convert(_ value: (any EcoreValue)?, owner: Resource?) async -> XtendValue {
        guard let value else { return .null }
        switch value {
        case let text as String: return .string(text)
        case let truth as Bool: return .bool(truth)
        case let number as Int: return .int(number)
        case let number as Int64: return .int(Int(number))
        case let number as Int16: return .int(Int(number))
        case let number as Int8: return .int(Int(number))
        case let number as Double: return .double(number)
        case let number as Float: return .double(Double(number))
        case let number as Decimal: return .double(NSDecimalNumber(decimal: number).doubleValue)
        case let character as Character: return .string(String(character))
        case let id as EUUID: return await objectValue(id: id, preferring: owner) ?? .null
        case let ids as [EUUID]:
            var values: [XtendValue] = []
            for id in ids { if let object = await objectValue(id: id, preferring: owner) { values.append(object) } }
            return .collection(XtendCollection(values))
        case let array as EcoreValueArray:
            var values: [XtendValue] = []
            for element in array.values { values.append(await convert(element, owner: owner)) }
            return .collection(XtendCollection(values))
        case let object as any EObject:
            return await wrap(object)
        case let date as Date:
            return .string(date.description)
        case let array as [any EcoreValue]:
            var values: [XtendValue] = []
            for element in array { values.append(await convert(element, owner: owner)) }
            return .collection(XtendCollection(values))
        default:
            return .string(String(describing: value))
        }
    }

    /// Finds a structural feature of a class by any of the spellings of a name.
    static func feature(named name: String, in eClass: EClass) -> (any EStructuralFeature)? {
        for candidate in nameVariants(name) {
            if let feature = eClass.getStructuralFeature(name: candidate) { return feature }
        }
        return nil
    }

    /// Whether a feature holds many values.
    static func isMany(_ feature: any EStructuralFeature) -> Bool {
        if let attribute = feature as? EAttribute { return attribute.isMany }
        if let reference = feature as? EReference { return reference.isMany }
        return false
    }

    /// Reads a feature of a model object or metamodel element.
    ///
    /// Unset features read as their defaults, and many-valued features as lists that write
    /// changes back to the object.
    ///
    /// - Returns: The value, or `nil` if the object has no such feature.
    func readFeature(of reference: XtendObjectReference, _ name: String) async -> XtendValue? {
        guard let object = await resolveObject(reference), let eClass = Self.metaClass(of: object),
            let feature = Self.feature(named: name, in: eClass)
        else { return nil }
        var raw = object.eGet(feature)
        if raw == nil, let dynamic = object as? DynamicEObject { raw = dynamic.eGetWithDefault(feature) }
        var value = await convert(raw, owner: reference.resource)
        if Self.isMany(feature) {
            let items: [XtendValue]
            if case .collection(let collection) = value {
                items = collection.elements
            } else {
                items = value.isNull ? [] : [value]
            }
            let collection = XtendCollection(items, isMutable: object is DynamicEObject && reference.resource != nil)
            collection.binding = XtendFeatureBinding(owner: reference, feature: feature.name)
            value = .collection(collection)
        }
        return value
    }

    /// Changes a feature of a model object.
    ///
    /// - Returns: `false` if the object has no such feature.
    /// - Throws: ``XtendDiagnosticCode/modelAccess`` if the object cannot be changed, or
    ///   ``XtendDiagnosticCode/typeMismatch`` if the value does not fit the feature.
    func setFeature(
        of reference: XtendObjectReference, _ name: String, _ value: XtendValue, range: SourceRange, _ context: XtendContext
    ) async throws -> Bool {
        guard let object = await resolveObject(reference), let eClass = Self.metaClass(of: object),
            let feature = Self.feature(named: name, in: eClass)
        else { return false }
        guard object is DynamicEObject, let resource = reference.resource else {
            throw failure(.modelAccess, "The feature '\(feature.name)' of a metamodel element cannot be changed", range, context)
        }
        let stored = try storedValue(value, for: feature, range: range, context)
        guard await resource.eSet(objectId: reference.id, feature: feature.name, value: stored) else {
            throw failure(.modelAccess, "The feature '\(feature.name)' of '\(eClass.name)' could not be changed", range, context)
        }
        return true
    }

    /// Writes a collection back to the model feature it was read from, if any.
    func writeBack(_ collection: XtendCollection, range: SourceRange, _ context: XtendContext) async throws {
        guard let binding = collection.binding else { return }
        _ = try await setFeature(of: binding.owner, binding.feature, .collection(collection), range: range, context)
    }

    /// Converts an interpreter value into the value stored for a feature.
    private func storedValue(
        _ value: XtendValue, for feature: any EStructuralFeature, range: SourceRange, _ context: XtendContext
    ) throws -> (any EcoreValue)? {
        if value.isNull { return nil }
        let items = Self.isMany(feature) ? (isIterable(value) ? try elements(of: value, range: range, context) : [value]) : [value]
        if feature is EReference {
            var identifiers: [EUUID] = []
            identifiers.reserveCapacity(items.count)
            for item in items {
                guard case .object(let target) = item else {
                    throw failure(
                        .typeMismatch, "The reference '\(feature.name)' needs model objects, not \(item.typeDescription)",
                        range, context)
                }
                identifiers.append(target.id)
            }
            return Self.isMany(feature) ? identifiers : identifiers.first
        }
        let dataType = (feature as? EAttribute)?.eType
        var scalars: [any EcoreValue] = []
        scalars.reserveCapacity(items.count)
        for item in items { scalars.append(try scalar(item, type: dataType, feature: feature.name, range: range, context)) }
        guard Self.isMany(feature) else { return scalars.first }
        if let texts = scalars as? [String] { return texts }
        if let numbers = scalars as? [Int] { return numbers }
        if let numbers = scalars as? [Double] { return numbers }
        if let truths = scalars as? [Bool] { return truths }
        return EcoreValueArray(scalars)
    }

    /// Converts a value into an attribute value of a data type.
    ///
    /// Strings, whole numbers, floating point numbers and truth values must match the
    /// attribute's data type, and enumeration values must name one of its literals.
    private func scalar(
        _ value: XtendValue, type: (any EClassifier)?, feature: String, range: SourceRange, _ context: XtendContext
    ) throws -> any EcoreValue {
        let expected = type.map(XtendTypeResolver.type(of:))
        switch (value, expected) {
        case (.string(let text), .modelEnum(let eEnum)?) where eEnum.literals.contains { $0.name == text }:
            return text
        case (.string(let text), .builtin(.string)?), (.string(let text), .builtin(.object)?), (.string(let text), nil):
            return text
        case (.bool(let truth), .builtin(.boolean)?), (.bool(let truth), .builtin(.object)?), (.bool(let truth), nil):
            return truth
        case (.int(let number), .builtin(.double)?): return Double(number)
        case (.int(let number), .builtin(.integer)?), (.int(let number), .builtin(.object)?), (.int(let number), nil):
            return number
        case (.double(let number), .builtin(.double)?), (.double(let number), .builtin(.object)?), (.double(let number), nil):
            return number
        default:
            throw failure(
                .typeMismatch,
                "The attribute '\(feature)' of type \(type?.name ?? "unknown") cannot hold \(value.typeDescription)", range,
                context)
        }
    }

    // MARK: - Object members

    /// Evaluates a member of a model object or metamodel element.
    ///
    /// - Returns: The value, or `nil` if the object has no such member.
    func objectMember(
        _ reference: XtendObjectReference, _ name: String, _ arguments: [XtendValue], explicitCall: Bool,
        range: SourceRange, _ context: XtendContext
    ) async throws -> XtendValue? {
        let receiver = XtendValue.object(reference)
        if arguments.isEmpty, let value = await readFeature(of: reference, name) { return value }
        if arguments.count == 1, let feature = Self.setterFeature(name),
            try await setFeature(of: reference, feature, arguments[0], range: range, context)
        {
            return .null
        }
        guard let object = await resolveObject(reference) else { return nil }
        switch (Self.allowedName(name, in: XtendJavaSubset.eObjectMembers) ?? name, arguments.count) {
        case ("eClass", 0):
            guard let eClass = Self.metaClass(of: object) else { return .null }
            return await wrap(eClass)
        case ("eContainer", 0):
            guard let resource = reference.resource else { return .null }
            if let container = await resource.eContainer(of: object, scope: .anyResource) {
                return await wrap(container)
            }
            if let meta = object as? any EMetaObject, let containerID = meta.eContainerID {
                return await objectValue(id: containerID, preferring: resource) ?? .null
            }
            return .null
        case ("eContents", 0), ("eAllContents", 0):
            let contents: [any EObject]
            if let resource = reference.resource {
                contents = name == "eContents" ? await resource.eContents(of: object) : await resource.eAllContents(of: object)
            } else if let meta = object as? any EMetaObject {
                contents = name == "eContents" ? meta.eContents : meta.eAllContents
            } else {
                contents = []
            }
            var values: [XtendValue] = []
            for item in contents { values.append(await wrap(item, holder: reference.resource)) }
            return .collection(XtendCollection(values, isMutable: false))
        case ("eResource", 0):
            return reference.resource.map { .resource($0) } ?? .null
        case ("eContainingFeature", 0):
            guard let resource = reference.resource,
                let feature = await resource.eContainingFeature(of: object, scope: .anyResource) as? any EObject
            else { return .null }
            return await wrap(feature)
        case ("eGet", 1), ("eIsSet", 1):
            let featureName: String
            switch arguments[0] {
            case .string(let text): featureName = text
            case .object(let featureReference):
                guard let feature = await resolveObject(featureReference) as? any EStructuralFeature else { return nil }
                featureName = feature.name
            default: return nil
            }
            guard let value = await readFeature(of: reference, featureName) else {
                throw failure(.unknownFeature, "No feature '\(featureName)'", range, context)
            }
            if name == "eGet" { return value }
            if let dynamic = object as? DynamicEObject { return .bool(dynamic.eIsSet(featureName)) }
            return .bool(!value.isNull)
        case ("eSet", 2):
            guard case .string(let featureName) = arguments[0] else { return nil }
            guard try await setFeature(of: reference, featureName, arguments[1], range: range, context) else {
                throw failure(.unknownFeature, "No feature '\(featureName)'", range, context)
            }
            return .null
        default:
            break
        }
        if let eClass = object as? EClass {
            switch (name, arguments.count) {
            case ("isSuperTypeOf", 1):
                guard case .object(let other) = arguments[0], let otherClass = await resolveObject(other) as? EClass else {
                    return .bool(false)
                }
                return .bool(eClass.isSuperTypeOf(otherClass))
            case ("getEStructuralFeature", 1):
                guard case .string(let featureName) = arguments[0],
                    let feature = eClass.getStructuralFeature(name: featureName) as? any EObject
                else { return .null }
                return await wrap(feature)
            default: break
            }
        }
        if let package = object as? EPackage, name == "getEClassifier", arguments.count == 1, case .string(let classifierName) = arguments[0] {
            guard let classifier = package.eClassifiers.first(where: { $0.name == classifierName }) as? any EObject else {
                return .null
            }
            return await wrap(classifier)
        }
        return try await commonMember(receiver, name, arguments)
    }

    // MARK: - Text

    /// The text of a value, following Java's `toString` conventions.
    func text(of value: XtendValue) async -> String {
        switch value {
        case .null: return "null"
        case .bool(let truth): return String(truth)
        case .int(let number): return String(number)
        case .double(let number): return Self.javaText(number)
        case .string(let text): return text
        case .collection(let collection):
            var parts: [String] = []
            for element in collection.elements { parts.append(await text(of: element)) }
            return "[" + parts.joined(separator: ", ") + "]"
        case .range(let integers):
            return "[" + integers.elements.map(String.init).joined(separator: ", ") + "]"
        case .map(let map):
            var parts: [String] = []
            for (key, entry) in zip(map.keys, map.values) { parts.append(await text(of: key) + "=" + text(of: entry)) }
            return "{" + parts.joined(separator: ", ") + "}"
        case .pair(let pair): return await text(of: pair.key) + "->" + text(of: pair.value)
        case .object(let reference): return await objectText(reference)
        case .instance(let instance): return instance.className.split(separator: ".").last.map(String.init) ?? instance.className
        case .lambda: return XtendBuiltinType.function.rawValue
        case .type(let type): return type.name
        case .resource(let resource): return resource.uri
        case .fileSystem: return XtendBuiltinType.fileSystemAccess.rawValue
        case .exception(let name, let message): return message.map { "\(name): \($0)" } ?? name
        }
    }

    /// The text of a floating point number in the style of Java's `Double.toString`.
    ///
    /// Magnitudes from one thousandth up to ten million are written in decimal notation, and
    /// all others in computerised scientific notation such as `1.0E10`, each with the
    /// shortest digits that identify the number.
    ///
    /// - Parameter number: The number.
    /// - Returns: The text of the number.
    static func javaText(_ number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number < 0 ? "-Infinity" : "Infinity" }
        if number == 0 { return number.sign == .minus ? "-0.0" : "0.0" }
        let magnitude = abs(number)
        if magnitude >= 1e-3 && magnitude < 1e7 {
            let text = String(number)
            return text.contains(".") || text.contains("e") ? text : text + ".0"
        }
        let parts = String(magnitude).split(separator: "e")
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(mantissa[0] + (mantissa.count > 1 ? mantissa[1] : ""))
        var point = mantissa[0].count
        while digits.count > 1, digits.first == "0" {
            digits.removeFirst()
            point -= 1
        }
        while digits.count > 1, digits.last == "0" { digits.removeLast() }
        let fraction = digits.count > 1 ? String(digits.dropFirst()) : "0"
        return (number < 0 ? "-" : "") + "\(digits[0]).\(fraction)E\(point - 1 + exponent)"
    }

    /// The text of a model object: the name of a metamodel element, or the class of a model
    /// object followed by its set attributes.
    private func objectText(_ reference: XtendObjectReference) async -> String {
        guard let object = await resolveObject(reference) else { return "EObject" }
        if let dynamic = object as? DynamicEObject {
            var parts: [String] = []
            for attribute in dynamic.eClass.eAllAttributes where dynamic.eIsSet(attribute) {
                parts.append("\(attribute.name): \(await text(of: await convert(dynamic.eGet(attribute), owner: reference.resource)))")
            }
            return parts.isEmpty ? dynamic.eClass.name : "\(dynamic.eClass.name) (\(parts.joined(separator: ", ")))"
        }
        if let named = object as? any ENamedElement { return named.name }
        return Self.metaClass(of: object)?.name ?? "EObject"
    }
}

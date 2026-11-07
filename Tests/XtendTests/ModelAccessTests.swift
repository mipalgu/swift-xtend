//
//  ModelAccessTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import Xtend

/// Tests of reflective model access, metamodel elements and model errors.
@Suite("Model access")
struct ModelAccessTests {
    /// Reflective `eGet`, `eIsSet` and `eSet`, the textual form of objects, and metamodel members.
    @Test("Reflection and metamodel members")
    func reflection() async throws {
        let fixtures = try await ModelFixtures.load()
        func source(_ extra: String) -> String {
            """
            import entities.*
            import org.eclipse.emf.ecore.EClass
            import org.eclipse.emf.ecore.EObject
            import org.eclipse.emf.ecore.EPackage
            import org.eclipse.emf.ecore.resource.Resource

            class Reflect {
                def run(Resource r) {
                    val model = r.contents.head as Model
                    val customer = model.entities.get(1)
                    val nameAttribute = customer.eClass.getEStructuralFeature('name')
                    val entityClass = customer.eClass
                    val featureClass = (entityClass.EPackage as EPackage).getEClassifier('Feature') as EClass
                    val attributeClass = customer.features.head.eClass
                    customer.eSet('abstract', true)
                    #[
                        customer.eGet(nameAttribute),
                        customer.eIsSet('superType'),
                        customer.eIsSet('features'),
                        customer.abstract,
                        featureClass.isSuperTypeOf(attributeClass),
                        attributeClass.isSuperTypeOf(featureClass),
                        customer.features.head.eContainingFeature.name,
                        customer instanceof EObject,
                        entityClass instanceof EClass,
                        nameAttribute.eContainer.name,
                        entityClass.eContents.size > 0,
                        entityClass.eAllContents.size > 0,
                        customer.features.head.toString,
                        entityClass.toString\(extra)
                    ]
                }
            }
            """
        }
        let program = try XtendTestSupport.program(["Reflect.xtend": source(",\n customer.eGet('missing')")], metamodels: [fixtures.entities])
        let interpreter = try XtendInterpreter(program: program, resources: [fixtures.shop, fixtures.entitiesResource])
        await #expect {
            _ = try await interpreter.call("run", of: "Reflect", arguments: [.resource(fixtures.shop)])
        } throws: { error in
            (error as? XtendError)?.code == .unknownFeature && (error as? XtendError)?.diagnostics.first?.range?.start.line == 31
                && (error as? XtendError)?.diagnostics.first?.range?.start.column == 2
        }
        let program2 = try XtendTestSupport.program(["Reflect.xtend": source("")], metamodels: [fixtures.entities])
        let interpreter2 = try XtendInterpreter(program: program2, resources: [fixtures.shop, fixtures.entitiesResource])
        let result = try await interpreter2.call("run", of: "Reflect", arguments: [.resource(fixtures.shop)])
        #expect(
            result.description
                == "[Customer, true, true, true, true, false, features, true, true, Entity, true, true, Attribute (name: loyaltyPoints, type: INTEGER), Entity]")
    }

    /// Model operations that cannot succeed fail with diagnostics.
    @Test(
        "Model errors",
        arguments: [
            ("new Entity => [ superType = 'x' ]", XtendDiagnosticCode.typeMismatch),
            ("new Entity => [ features = #[1] ]", .typeMismatch), ("(new Entity).foo", .unknownFeature),
            ("val e = new Entity; e.eSet('colour', 1)", .unknownFeature), ("new Entity(1)", .invalidArgument),
            ("DataKind::NONE", .unknownFeature), ("Entity::foo", .unknownFeature), ("new Attribute => [ type = 'NONE' ]", .typeMismatch),
            ("new Entity => [ name = #[1] ]", .typeMismatch), ("(new Entity).eClass => [ name = 'x' ]", .modelAccess),
            ("new Entity => [ it.unknown = 1 ]", .invalidAssignment),
        ])
    func modelErrors(expression: String, expected: XtendDiagnosticCode) async throws {
        let fixtures = try await ModelFixtures.load()
        let program = XtendProgram(sources: [], metamodels: [fixtures.entities])
        let interpreter = try XtendInterpreter(program: program)
        do {
            _ = try await interpreter.evaluate(expression)
            Issue.record("Expected \(expected)")
        } catch let error as XtendError {
            #expect(error.code == expected, "\(error)")
        }
    }

    /// Host values carry model objects in and out, and objects of unknown resources become null.
    @Test("Objects as host values")
    func objectHostValues() async throws {
        let fixtures = try await ModelFixtures.load()
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: [], metamodels: [fixtures.entities]))
        let root = try #require(await fixtures.shop.getRootObjects().first)
        let name = try await interpreter.evaluate("model.name", variables: ["model": .object(root.id, fixtures.shop)])
        #expect(name.stringValue == "shop")
        let entities = try await interpreter.evaluate("model.entities", variables: ["model": .object(root.id, nil)])
        #expect(entities.elements?.count == 3)
        #expect(entities.elements?.first?.objectID != nil)
        let missing = try await interpreter.evaluate("x", variables: ["x": .object(EUUID(), nil)])
        #expect(missing.description == "null")
        let resource = try await interpreter.evaluate("r", variables: ["r": .resource(fixtures.shop)])
        #expect(resource.description == "test:/shop.xmi")
        let other = try await interpreter.evaluate("[int x | x]")
        if case .other(let text) = other { #expect(text == "Function") } else { Issue.record("Expected other") }
        let fileSystem = try await interpreter.evaluate("f", variables: ["f": .fileSystem(XtendInMemoryFileSystemAccess())])
        #expect(fileSystem.description == "IFileSystemAccess")
        #expect(try await interpreter.evaluate("#{1 -> 'a'}").description == "{1=a}")
        #expect(try await interpreter.evaluate("1..2").description == "[1, 2]")
        #expect(try await interpreter.evaluate("x", variables: ["x": .other("text")]).stringValue == "text")
        #expect(try await interpreter.evaluate("s.size", variables: ["s": .set([.int(1), .int(1)])]).intValue == 1)
    }

    /// Many-valued attributes store typed arrays.
    @Test("Many-valued attributes")
    func manyValuedAttributes() async throws {
        let ecore = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" \
            name="tags" nsURI="http://example.org/tags" nsPrefix="tags">
              <eClassifiers xsi:type="ecore:EClass" name="Tagged">
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="labels" upperBound="-1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="counts" upperBound="-1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"/>
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="weights" upperBound="-1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EDouble"/>
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="flags" upperBound="-1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EBoolean"/>
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="ratio" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EDouble"/>
              </eClassifiers>
            </ecore:EPackage>
            """
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            data: Data(ecore.utf8), uri: "test:/tags.ecore", format: .ecore, resourceSet: resourceSet)
        let package = try #require(loaded.packages.first)
        let target = Resource(uri: "test:/tags.xmi")
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: [], metamodels: [package]), targetResource: target)
        let result = try await interpreter.evaluate(
            """
            val t = new tags.Tagged
            t.labels += #['a', 'b']
            t.counts.add(3)
            t.weights += 1
            t.flags += true
            t.ratio = 2
            #[t.labels, t.counts, t.weights, t.flags, t.ratio, t.labels.binarySafe]
            """.replacingOccurrences(of: ", t.labels.binarySafe", with: ""))
        #expect(result.description == "[[a, b], [3], [1.0], [true], 2.0]")
        let object = try #require(await target.getRootObjects().first as? DynamicEObject)
        #expect(object.eGet("labels") as? [String] == ["a", "b"])
        #expect(object.eGet("counts") as? [Int] == [3])
        #expect(object.eGet("weights") as? [Double] == [1.0])
        #expect(object.eGet("flags") as? [Bool] == [true])
    }
}

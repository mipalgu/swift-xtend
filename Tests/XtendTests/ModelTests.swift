//
//  ModelTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import Xtend

/// Tests of generators and transformations over Ecore models.
@Suite("Models")
struct ModelTests {
    /// A generator in the style of an Xtext `AbstractGenerator` that writes one Swift-like
    /// file per concrete or abstract entity.
    static let swiftGenerator = """
        package generator

        import entities.Entity
        import entities.Attribute
        import entities.Reference
        import entities.DataKind
        import org.eclipse.emf.ecore.resource.Resource
        import org.eclipse.xtext.generator.AbstractGenerator
        import org.eclipse.xtext.generator.IFileSystemAccess2
        import org.eclipse.xtext.generator.IGeneratorContext

        class SwiftGenerator extends AbstractGenerator {
            override void doGenerate(Resource resource, IFileSystemAccess2 fsa, IGeneratorContext context) {
                for (entity : resource.allContents.toIterable.filter(Entity)) {
                    fsa.generateFile('Sources/' + entity.name + '.swift', entity.compile)
                }
                fsa.generateFile('Summary.txt', 'docs', '''
                    «FOR e : resource.contents.head.eAllContents.filter(Entity).toList SEPARATOR ', '»«e.name»«ENDFOR»
                ''')
            }

            def compile(Entity e) '''
                «IF e.isAbstract»
                /// An abstract «e.name.toLowerCase».
                «ENDIF»
                public «IF e.abstract»class«ELSE»final class«ENDIF» «e.name»«IF e.superType !== null»: «e.superType.name»«ENDIF» {
                    «FOR f : e.features»
                    «f.declaration»
                    «ENDFOR»
                }
            '''

            def dispatch declaration(Attribute a) '''public var «a.name.toFirstLower»: «a.swiftType»'''

            def dispatch declaration(Reference r) '''public var «r.name»: «IF r.many»[«r.target.name»]«ELSE»«r.target.name»?«ENDIF»'''

            def swiftType(Attribute a) {
                switch a.type {
                    case DataKind::STRING: 'String'
                    case DataKind.INTEGER: 'Int'
                    default: 'Bool'
                }
            }
        }
        """

    /// The generator writes the expected files with exact whitespace.
    @Test("Code generator with golden output")
    func generator() async throws {
        let fixtures = try await ModelFixtures.load()
        let program = try XtendTestSupport.program(["SwiftGenerator.xtend": Self.swiftGenerator], metamodels: [fixtures.entities])
        let interpreter = try XtendInterpreter(program: program, resources: [fixtures.shop])
        let files = XtendInMemoryFileSystemAccess()
        try await interpreter.generate(resource: fixtures.shop, fileSystem: files)
        let generated = await files.generatedFiles
        #expect(generated.keys.sorted() == ["Sources/Customer.swift", "Sources/Order.swift", "Sources/Party.swift"])
        #expect(
            generated["Sources/Party.swift"] == """
                /// An abstract party.
                public class Party {
                    public var name: String
                }

                """)
        #expect(
            generated["Sources/Customer.swift"] == """
                public final class Customer: Party {
                    public var loyaltyPoints: Int
                    public var orders: [Order]
                }

                """)
        #expect(
            generated["Sources/Order.swift"] == """
                public final class Order {
                    public var number: Int
                    public var express: Bool
                    public var customer: Customer?
                }

                """)
        #expect(await files.contents(of: "Summary.txt", outputConfiguration: "docs") == "Party, Customer, Order\n")
    }

    /// A model-to-model transformation with create methods and dispatch builds a target
    /// model whose references are resolved through the create caches.
    @Test("Model-to-model transformation")
    func transformation() async throws {
        let fixtures = try await ModelFixtures.load()
        let transformation = """
            import entities.*
            import relational.Schema
            import relational.Table
            import relational.Column

            class Entities2Tables {
                def create schema: new Schema toSchema(Model m) {
                    schema.name = m.name
                    schema.tables += m.entities.filter[!isAbstract].map[toTable]
                }

                def create new Table toTable(Entity e) {
                    name = e.name.toUpperCase
                    columns += e.allFeatures.map[column]
                }

                def Iterable<Feature> allFeatures(Entity e) {
                    (e.superType?.allFeatures ?: #[]) + e.features
                }

                def dispatch Column column(Attribute a) {
                    new Column => [
                        name = a.name
                        sqlType = a.sqlType
                        if (a.type == DataKind::STRING) width = 255
                    ]
                }

                def dispatch Column column(Reference r) {
                    val column = new Column
                    column.setName(r.name + '_id')
                    column.sqlType = 'INTEGER'
                    column.references = r.target.toTable
                    column
                }

                def sqlType(Attribute a) {
                    switch a.type {
                        case DataKind::STRING: 'VARCHAR'
                        case DataKind::INTEGER: 'INTEGER'
                        default: 'BOOLEAN'
                    }
                }
            }
            """
        let ddl = """
            import relational.*
            import org.eclipse.emf.ecore.resource.Resource
            import org.eclipse.xtext.generator.IFileSystemAccess

            class DdlGenerator {
                def generate(Resource resource, IFileSystemAccess fsa) {
                    val schema = resource.contents.filter(Schema).head
                    fsa.generateFile(schema.name + '.sql', schema.ddl)
                }

                def ddl(Schema s) '''
                    -- schema «s.name»
                    «FOR t : s.tables»

                    CREATE TABLE «t.name» (
                        «FOR c : t.columns SEPARATOR ','»
                        «c.name» «c.sqlType»«IF c.width > 0»(«c.width»)«ENDIF»«IF c.references !== null» REFERENCES «c.references.name»«ENDIF»
                        «ENDFOR»
                    );
                    «ENDFOR»
                '''
            }
            """
        let program = try XtendTestSupport.program(
            ["Entities2Tables.xtend": transformation, "DdlGenerator.xtend": ddl],
            metamodels: [fixtures.entities, fixtures.relational])
        let target = Resource(uri: "test:/shop-tables.xmi")
        let interpreter = try XtendInterpreter(program: program, resources: [fixtures.shop], targetResource: target)
        let root = try #require(await fixtures.shop.getRootObjects().first)
        let schema = try await interpreter.call("toSchema", of: "Entities2Tables", arguments: [.object(root.id, fixtures.shop)])
        let roots = await target.getRootObjects()
        #expect(roots.count == 1)
        #expect(roots.first?.id == schema.objectID)
        let files = XtendInMemoryFileSystemAccess()
        try await interpreter.generate(resource: target, fileSystem: files, className: "DdlGenerator")
        #expect(
            await files.contents(of: "shop.sql") == """
                -- schema shop

                CREATE TABLE CUSTOMER (
                    name VARCHAR(255),
                    loyaltyPoints INTEGER,
                    orders_id INTEGER REFERENCES ORDER
                );

                CREATE TABLE ORDER (
                    Number INTEGER,
                    express BOOLEAN,
                    customer_id INTEGER REFERENCES CUSTOMER
                );

                """)
    }

    /// Navigation through containers, contents, classes and features.
    @Test("Model navigation")
    func navigation() async throws {
        let fixtures = try await ModelFixtures.load()
        let source = """
            import entities.*
            import org.eclipse.emf.ecore.resource.Resource

            class Queries {
                def report(Resource r) {
                    val model = r.contents.head as Model
                    val order = model.entities.findFirst[name == 'Order']
                    val express = order.features.findFirst[name == 'express']
                    #[
                        express.eContainer === order,
                        express.eContainer.eContainer === model,
                        express.eClass.name,
                        model.eAllContents.size,
                        model.eContents.map[eClass.name].join(','),
                        order.getFeatures().size,
                        (order.features.last as Reference).target.name,
                        model.entities.map[superType?.name],
                        express.eResource === r,
                        model.getName,
                        express instanceof Feature && express instanceof Attribute && !(express instanceof Reference),
                        model.eGet('name'),
                        express.eClass.EAllAttributes.map[name]
                    ]
                }
            }
            """
        let program = try XtendTestSupport.program(["Queries.xtend": source], metamodels: [fixtures.entities])
        let interpreter = try XtendInterpreter(program: program, resources: [fixtures.shop])
        let result = try await interpreter.call("report", of: "Queries", arguments: [.resource(fixtures.shop)])
        #expect(
            result.description
                == "[true, true, Attribute, 9, Entity,Entity,Entity, 3, Customer, [null, Party, null], true, shop, true, shop, [name, many, type]]")
    }

    /// Model objects are created, changed and linked; containment removes them from the
    /// roots of the target resource.
    @Test("Creating and changing model objects")
    func changingObjects() async throws {
        let fixtures = try await ModelFixtures.load()
        let source = """
            import entities.*
            class Builder {
                def build() {
                    val model = new Model => [ name = 'built' ]
                    val entity = new Entity
                    entity.name = 'Thing'
                    entity.features.add(new Attribute => [ name = 'label'; type = DataKind::STRING ])
                    entity.features += new Attribute => [ name = 'count'; it.setType(DataKind.INTEGER); many = true ]
                    model.entities += entity
                    model.entities.head.features.map[name + ':' + type + ':' + many]
                }
                def invalid() { new Entity => [ name = 42 ] }
                def unknownFeature() { new Entity => [ colour = 'red' ] }
                def abstractClass() { new Feature }
            }
            """
        let program = try XtendTestSupport.program(["Builder.xtend": source], metamodels: [fixtures.entities])
        let target = Resource(uri: "test:/built.xmi")
        let interpreter = try XtendInterpreter(program: program, targetResource: target)
        let result = try await interpreter.call("build", of: "Builder")
        #expect(result.description == "[label:STRING:false, count:INTEGER:true]")
        let roots = await target.getRootObjects()
        #expect(roots.count == 1)
        #expect((roots.first as? DynamicEObject)?.eGet("name") as? String == "built")
        for method in ["invalid", "unknownFeature", "abstractClass"] {
            await #expect(throws: XtendError.self) { _ = try await interpreter.call(method, of: "Builder") }
        }
    }

    /// A generator can take an Ecore metamodel as its input model.
    @Test("Generator over a metamodel")
    func metamodelInput() async throws {
        let fixtures = try await ModelFixtures.load()
        let source = """
            import org.eclipse.emf.ecore.EClass
            import org.eclipse.emf.ecore.EEnum
            import org.eclipse.emf.ecore.EPackage
            import org.eclipse.emf.ecore.resource.Resource
            import org.eclipse.xtext.generator.IFileSystemAccess

            class Documenter {
                def generate(Resource r, IFileSystemAccess fsa) {
                    val pkg = r.contents.head as EPackage
                    fsa.generateFile(pkg.name + '.md', '''
                        # «pkg.name» («pkg.nsURI»)
                        «FOR c : r.allContents.filter(EClass)»
                        - «c.name»«IF c.abstract» (abstract)«ENDIF»«FOR s : c.ESuperTypes BEFORE ' extends '»«s.name»«ENDFOR»: «c.EAllStructuralFeatures.map[name + (if (many) '*' else '')].join(', ')»
                        «ENDFOR»
                        «FOR e : pkg.EClassifiers.filter(EEnum)»
                        - enum «e.name»: «e.ELiterals.map[name].join(' | ')»
                        «ENDFOR»
                    ''')
                }
            }
            """
        let program = try XtendTestSupport.program(["Documenter.xtend": source])
        let interpreter = try XtendInterpreter(program: program)
        let files = XtendInMemoryFileSystemAccess()
        try await interpreter.generate(resource: fixtures.entitiesResource, fileSystem: files)
        #expect(
            await files.contents(of: "entities.md") == """
                # entities (http://example.org/entities)
                - Model: name, entities*
                - Entity: name, abstract, superType, features*
                - Feature (abstract): name, many
                - Attribute extends Feature: name, many, type
                - Reference extends Feature: name, many, target
                - enum DataKind: STRING | INTEGER | BOOLEAN

                """)
    }
}

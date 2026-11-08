//
//  EntryPointTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import Xtend

/// Tests of how a program names its generator class and the dispatchers of its dispatch methods.
@Suite("Entry points")
struct EntryPointTests {
    /// A helper class without a generator method and a generator that uses it.
    private static let helper = """
        class Helper {
          def String greet(String name) { 'Hello ' + name }
        }
        """

    /// A generator that writes one file.
    private static let generator = """
        import org.eclipse.emf.ecore.resource.Resource
        import org.eclipse.xtext.generator.IFileSystemAccess

        class Pictures {
          extension Helper helper = new Helper
          def doGenerate(Resource resource, IFileSystemAccess fsa) { fsa.generateFile('a.txt', 'world'.greet) }
        }
        """

    /// Without a name, the generator class is the first class with a generator method, even if
    /// another class is declared first.
    @Test("The generator class is the first class with a generator method")
    func firstGeneratorClass() throws {
        let program = try XtendTestSupport.program(["A.xtend": Self.helper, "B.xtend": Self.generator])
        #expect(program.classNames == ["Helper", "Pictures"])
        #expect(program.generatorClass()?.qualifiedName == "Pictures")
        #expect(program.generatorClass(named: "Pictures")?.qualifiedName == "Pictures")
        #expect(program.generatorClass(named: "Helper") == nil)
        #expect(program.generatorClass(named: "Missing") == nil)
    }

    /// The interpreter runs the generator class that the program names when none is given.
    @Test("Generating without a class name runs the first generator class")
    func generateWithoutClassName() async throws {
        let program = try XtendTestSupport.program(["A.xtend": Self.helper, "B.xtend": Self.generator])
        let interpreter = try XtendInterpreter(program: program)
        let files = XtendInMemoryFileSystemAccess()
        try await interpreter.generate(resource: interpreter.targetResource, fileSystem: files)
        #expect(await files.contents(of: "a.txt") == "Hello world")
    }

    /// A generator method is found in a superclass, with a generator context, by its second
    /// name, and an abstract generator is passed over unless it is named.
    @Test("Inherited, three-parameter and abstract generators")
    func generatorVariants() throws {
        let source = """
            import org.eclipse.emf.ecore.resource.Resource
            import org.eclipse.xtext.generator.IFileSystemAccess
            import org.eclipse.xtext.generator.IGeneratorContext

            abstract class Base {
              def generate(Resource r, IFileSystemAccess fsa, IGeneratorContext context) {}
            }
            class Derived extends Base {}
            class Other {
              def doGenerate(Resource r) {}
            }
            """
        let program = try XtendTestSupport.program(["Test.xtend": source])
        #expect(program.generatorClass()?.qualifiedName == "Derived")
        #expect(program.generatorClass(named: "Base")?.qualifiedName == "Base")
        #expect(program.generatorClass(named: "Other") == nil)
    }

    /// The dispatcher of a dispatch method takes the common supertype of the parameter types of
    /// its cases, position by position.
    @Test("Dispatcher parameters take the common supertypes of the cases")
    func dispatcherParameters() async throws {
        let fixtures = try await ModelFixtures.load()
        let source = """
            import entities.Attribute
            import entities.Reference
            import entities.Entity

            class Measure {
              def dispatch kind(Attribute a, int depth) { 'attribute' }
              def dispatch kind(Reference r, int depth) { 'reference' }
              def dispatch same(Entity e) { e.name }
              def dispatch mixed(Entity e) { 'entity' }
              def dispatch mixed(String s) { 'text' }
              def dispatch numbers(Integer i) { i }
              def dispatch numbers(Double d) { d }
              def plain(Entity e) { e }
            }
            """
        let program = try XtendTestSupport.program(["Test.xtend": source], metamodels: [fixtures.entities])
        func types(_ method: String, _ arity: Int) -> [String?]? {
            program.dispatcherParameters(of: method, arity: arity, in: "Measure")?.map { $0.type?.name }
        }
        #expect(types("kind", 2) == ["Feature", "int"])
        #expect(program.dispatcherParameters(of: "kind", arity: 2, in: "Measure")?.map(\.name) == ["a", "depth"])
        #expect(types("same", 1) == ["Entity"])
        #expect(types("mixed", 1) == ["Object"])
        #expect(types("numbers", 1) == ["Number"])
        #expect(types("kind", 1) == nil)
        #expect(types("plain", 1) == nil)
        #expect(program.dispatcherParameters(of: "kind", arity: 2, in: "Missing") == nil)
    }

    /// Classes without a common superclass of the metamodel share `EObject`, and classes of the
    /// compilation set share their nearest common superclass.
    @Test("Common supertypes of unrelated and of compilation set classes")
    func commonSupertypes() async throws {
        let fixtures = try await ModelFixtures.load()
        let source = """
            import entities.Attribute
            import entities.Entity

            class Animal {}
            class Dog extends Animal {}
            class Cat extends Animal {}
            class Measure {
              def dispatch unrelated(Attribute a) { a }
              def dispatch unrelated(Entity e) { e }
              def dispatch pet(Dog d) { d }
              def dispatch pet(Cat c) { c }
              def dispatch stranger(Dog d) { d }
              def dispatch stranger(Entity e) { e }
            }
            """
        let program = try XtendTestSupport.program(["Test.xtend": source], metamodels: [fixtures.entities])
        func types(_ method: String) -> [String?]? {
            program.dispatcherParameters(of: method, arity: 1, in: "Measure")?.map { $0.type?.name }
        }
        #expect(types("unrelated") == ["EObject"])
        #expect(types("pet") == ["Animal"])
        #expect(types("stranger") == ["Object"])
    }
}

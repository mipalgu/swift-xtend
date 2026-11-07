//
//  ClassTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import Xtend

/// Tests of classes, dispatch methods, extension methods and create methods.
@Suite("Classes and methods")
struct ClassTests {
    private static let shapes = """
        package shapes

        abstract class Shape {}
        class Circle extends Shape { public val double radius = 1.0 }
        class Square extends Shape { public val double side = 2.0 }
        class Triangle extends Shape {}

        class Geometry {
          def dispatch area(Circle c) { 3 * c.radius * c.radius }
          def dispatch area(Square s) { s.side * s.side }
          def dispatch area(Shape s) { 0.0 }

          def dispatch describe(String s) { 'string ' + s }
          def dispatch describe(Integer i) { 'integer ' + i }
          def dispatch describe(Object o) { 'object' }
          def dispatch describe(Void v) { 'nothing' }

          def areas() { #[new Circle, new Square, new Triangle].map[area] }
          def descriptions() { #['x', 1, 2.5, null].map[describe] }
        }
        """

    /// Dispatch chooses the most specific case by the runtime type of the argument.
    @Test("Dispatch on runtime types")
    func dispatch() async throws {
        let areas = try await XtendTestSupport.call(Self.shapes, "areas", of: "Geometry")
        #expect(areas.description == "[3.0, 4.0, 0.0]")
        let descriptions = try await XtendTestSupport.call(Self.shapes, "descriptions", of: "shapes.Geometry")
        #expect(descriptions.description == "[string x, integer 1, object, nothing]")
    }

    /// A subclass overrides a dispatch case and inherits the others; `super` reaches the
    /// overridden case.
    @Test("Overriding dispatch cases")
    func overridingDispatch() async throws {
        let source = """
            class Base {
              def dispatch name(Object o) { 'object' }
              def dispatch name(String s) { 'string' }
            }
            class Derived extends Base {
              override dispatch name(String s) { 'derived ' + super.name(s) }
              def all() { #[name('a'), name(1)] }
            }
            """
        let result = try await XtendTestSupport.call(source, "all", of: "Derived")
        #expect(result.description == "[derived string, object]")
    }

    /// A dispatch method without a case for the argument fails with a diagnostic.
    @Test("Missing dispatch case")
    func missingDispatchCase() async throws {
        let source = """
            class T {
              def dispatch f(String s) { s }
              def dispatch f(Integer i) { i }
              def run() { f(true) }
            }
            """
        await #expect {
            _ = try await XtendTestSupport.call(source, "run", of: "T")
        } throws: { error in
            (error as? XtendError)?.code == .noDispatchCase && (error as? XtendError)?.diagnostics.first?.range?.start.line == 4
        }
    }

    /// Methods of the running class, extension fields, extension parameters, extension
    /// variables and statically imported classes all provide extension methods.
    @Test("Extension methods")
    func extensionMethods() async throws {
        let helpers = """
            package util
            class Helpers {
              def static triple(int i) { i * 3 }
            }
            class Strings {
              def shout(String s) { s.toUpperCase + '!' }
              def wrap(String s, String around) { around + s + around }
            }
            """
        let main = """
            import util.Strings
            import static extension util.Helpers.*

            class Main {
              extension Strings strings = new Strings
              def twice(String s) { s + s }
              def local() { 'ab'.twice }
              def field() { 'hey'.shout + 'x'.wrap('*') }
              def parameter(extension Strings h) { 'p'.shout }
              def variable() { val extension Strings s = new Strings; 'v'.wrap('|') }
              def imported() { 4.triple + Helpers::triple(1) + Helpers.triple(2) }
              def implicit() { #['a', 'b'].map[shout] }
            }
            """
        let program = try XtendTestSupport.program(["Helpers.xtend": helpers, "Main.xtend": main])
        let interpreter = try XtendInterpreter(program: program)
        #expect(try await interpreter.call("local", of: "Main").stringValue == "abab")
        #expect(try await interpreter.call("field", of: "Main").stringValue == "HEY!*x*")
        #expect(try await interpreter.call("variable", of: "Main").stringValue == "|v|")
        #expect(try await interpreter.call("imported", of: "Main").intValue == 21)
        #expect(try await interpreter.call("implicit", of: "Main").description == "[A!, B!]")
        let injected = try XtendTestSupport.program([
            "Helpers.xtend": helpers,
            "Main.xtend": """
            import util.Strings
            class Main {
              @Inject extension Strings
              def run(extension Strings h) { 'q'.shout }
              def call() { run(new Strings) }
            }
            """.replacingOccurrences(of: "@Inject extension Strings\n", with: "@Inject extension Strings strings\n"),
        ])
        #expect(try await XtendInterpreter(program: injected).call("call", of: "Main").stringValue == "Q!")
    }

    /// Create methods return the same object for the same arguments and run their body once.
    @Test("Create methods are cached")
    func createMethods() async throws {
        let source = """
            import java.util.List
            class Box { public var String label public var List<Box> parts = newArrayList }
            class Factory {
              var int created = 0
              def create new Box() box(String label) {
                created = created + 1
                it.label = label
              }
              def create result: new Box() cyclic(String label) {
                result.label = label
                result.parts += cyclic(label)
              }
              def run() {
                val first = box('a')
                val again = box('a')
                val other = box('b')
                #[first === again, first === other, created, again.label, cyclic('c').parts.head.label]
              }
            }
            """
        let result = try await XtendTestSupport.call(source, "run", of: "Factory")
        #expect(result.description == "[true, false, 2, a, c]")
    }

    /// Every call of the interpreter works with a new instance, whose create caches start
    /// empty, however often instances are created and released.
    @Test("Create caches belong to their instance")
    func createCachesPerInstance() async throws {
        let source = """
            class Box { public var String label }
            class Factory {
              var int created = 0
              def create new Box() box(String label) {
                created = created + 1
                it.label = label
              }
              def run(String label) { box(label).label + created }
            }
            """
        let interpreter = try XtendInterpreter(program: try XtendTestSupport.program(["T.xtend": source]))
        for _ in 0..<50 {
            #expect(try await interpreter.call("run", of: "Factory", arguments: [.string("a")]).stringValue == "a1")
        }
    }

    /// Constructors, fields, static fields, `this` and `return`.
    @Test("Constructors, fields and return")
    func constructorsAndFields() async throws {
        let source = """
            class Counter {
              static val PREFIX = 'n='
              var int count
              val String name
              new() { this('default') }
              new(String name) { this.name = name }
              def increment() { count = count + 1; this }
              def label() { return PREFIX + count + ' ' + name }
              def early(int x) {
                if (x > 0) return 'positive'
                'other'
              }
              def run() { new Counter('c').increment.increment.label + ' ' + early(1) + ' ' + early(-1) }
            }
            """
        #expect(try await XtendTestSupport.call(source, "run", of: "Counter").stringValue == "n=2 c positive other")
        #expect(try await XtendTestSupport.call(source, "label", of: "Counter").stringValue == "n=0 default")
    }

    /// Deep recursion fails with a diagnostic instead of exhausting the stack.
    @Test("Recursion limit")
    func recursionLimit() async throws {
        let source = "class T { def f(int n) { f(n + 1) } def run() { f(0) } }"
        let interpreter = try XtendInterpreter(
            program: try XtendTestSupport.program(["T.xtend": source]), options: XtendOptions(maximumCallDepth: 50))
        await #expect {
            _ = try await interpreter.call("run", of: "T")
        } throws: { error in
            (error as? XtendError)?.code == .recursionLimit
        }
    }

    /// Calling an unknown class or method fails clearly.
    @Test("Unknown classes and methods")
    func unknownEntryPoints() async throws {
        let interpreter = try XtendInterpreter(program: try XtendTestSupport.program(["T.xtend": "class T { def f() { 1 } }"]))
        await #expect(throws: XtendError.self) { _ = try await interpreter.call("f", of: "Missing") }
        await #expect(throws: XtendError.self) { _ = try await interpreter.call("g", of: "T") }
        #expect(try await interpreter.call("f", of: "T").intValue == 1)
    }
}

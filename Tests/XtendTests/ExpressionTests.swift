//
//  ExpressionTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import Xtend

/// Tests of expressions, operators, lambdas and the native library.
@Suite("Expressions")
struct ExpressionTests {
    /// Evaluates an expression and returns its textual form.
    private func value(_ expression: String) async throws -> String {
        XtendTestSupport.text(try await XtendTestSupport.evaluate(expression))
    }

    /// Arithmetic follows Java's rules for whole and floating point numbers.
    @Test(
        "Arithmetic",
        arguments: [
            ("1 + 2 * 3", "7"), ("7 / 2", "3"), ("7 % 3", "1"), ("7.0 / 2", "3.5"), ("2 ** 3", "8.0"), ("-(3 - 5)", "2"),
            ("1.5 + 1", "2.5"), ("10 - 2 - 3", "5"), ("1e10", "1.0E10"), ("0.0001", "1.0E-4"), ("0.001", "0.001"),
            ("1234567.5", "1234567.5"), ("-2.5e-7", "-2.5E-7"), ("1e7", "1.0E7"), ("0.0", "0.0"), ("100.0", "100.0"),
        ])
    func arithmetic(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Comparisons, equality, identity and Boolean operators.
    @Test(
        "Comparisons and logic",
        arguments: [
            ("1 < 2 && 2 <= 2", "true"), ("'a' < 'b'", "true"), ("3 > 4 || !false", "true"), ("1 == 1.0", "true"),
            ("'x' == 'x'", "true"), ("#[1, 2] == #[1, 2]", "true"), ("#[1] === #[1]", "false"), ("null == null", "true"),
            ("1 != 2", "true"), ("5 >= 6", "false"),
        ])
    func comparisons(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// String concatenation and the supported members of strings.
    @Test(
        "Strings",
        arguments: [
            ("'a' + 1 + true + null", "a1truenull"), ("'abc'.toUpperCase", "ABC"), ("'hello'.toFirstUpper", "Hello"),
            ("'Hello'.toFirstLower", "hello"), ("'abc'.length", "3"), ("'abc'.substring(1)", "bc"),
            ("'abcdef'.substring(1, 3)", "bc"), ("'  x '.trim", "x"), ("'a,b,,c,,'.split(',')", "[a, b, , c]"),
            ("'banana'.indexOf('an')", "1"), ("'banana'.lastIndexOf('an')", "3"), ("'abc'.charAt(1)", "b"),
            ("'a-b-c'.replace('-', '+')", "a+b+c"), ("'a1b22'.replaceAll('[0-9]+', '#')", "a#b#"),
            ("'abc'.startsWith('ab') && 'abc'.endsWith('bc') && 'abc'.contains('b')", "true"), ("''.empty", "true"),
            ("'ab'.repeat(3)", "ababab"), ("'abc'.matches('[a-c]+')", "true"), ("'Ab'.equalsIgnoreCase('aB')", "true"),
            ("'a'.compareTo('c')", "-2"), ("'x'.hashCode", "120"), ("(null as String).nullOrEmpty", "true"),
            ("'a.b'.split('\\\\.')", "[a, b]"), ("'abc'.split('x')", "[abc]"), ("'...'.split('\\\\.').size", "0"),
            ("'a1b2'.split('[0-9]')", "[a, b]"),
        ])
    func strings(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Null-safe calls, the elvis operator and the with operator.
    @Test(
        "Null handling and the with operator",
        arguments: [
            ("val String s = null; s?.length", "null"), ("null ?: 'fallback'", "fallback"), ("'x' ?: 'y'", "x"),
            ("newArrayList => [ add(1); add(2) ]", "[1, 2]"),
        ])
    func nullHandling(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// The native collection extensions.
    @Test(
        "Collection extensions",
        arguments: [
            ("#[3, 1, 2].sort", "[1, 2, 3]"), ("#[1, 2, 3].map[it * 2]", "[2, 4, 6]"), ("#[1, 2, 3, 4].filter[it % 2 == 0]", "[2, 4]"),
            ("#['a', 'bb'].map[length]", "[1, 2]"), ("#[1, 2, 3].reduce[a, b | a + b]", "6"),
            ("#[1, 2, 3].fold(10)[sum, x | sum + x]", "16"), ("#[#[1, 2], #[3]].flatten", "[1, 2, 3]"),
            ("#['a', 'b'].join(', ')", "a, b"), ("#['a', 'b'].join('<', '|', '>', [toUpperCase])", "<A|B>"),
            ("#[].join('<', '|', '>', [it])", ""), ("#[1, 2].join", "12"), ("#[1, 2, 3].head", "1"), ("#[1, 2, 3].last", "3"),
            ("#[1, 2, 3].tail", "[2, 3]"), ("#[1, 2, 3].exists[it > 2]", "true"), ("#[1, 2, 3].forall[it > 2]", "false"),
            ("#[1, 2, 3].findFirst[it > 1]", "2"), ("#[1, 2, 3].findLast[it < 3]", "2"), ("#{1, 2, 2}.size", "2"),
            ("#{'a' -> 1}.get('a')", "1"), ("(1..3).toList", "[1, 2, 3]"), ("(0..<3).map[it]", "[0, 1, 2]"),
            ("(3 >.. 0).toList", "[2, 1, 0]"), ("(3..1).toList", "[3, 2, 1]"), ("#['bb', 'a', 'ccc'].sortBy[length]", "[a, bb, ccc]"),
            ("#[1, 2, 3, 4].groupBy[it % 2]", "{1=[1, 3], 0=[2, 4]}"), ("#['a', 'bb'].toMap[length]", "{1=a, 2=bb}"),
            ("#['x', 'y'].indexed", "[0->x, 1->y]"), ("#[3, 7, 5].max", "7"), ("#['bb', 'a'].minBy[length]", "a"),
            ("#[1, 2, 3, 4].take(2)", "[1, 2]"), ("#[1, 2, 3, 4].drop(3)", "[4]"), ("#[1, 'a', 2].filter(Integer)", "[1, 2]"),
            ("#[1, null, 2].filterNull", "[1, 2]"), ("#[1, 2].isEmpty", "false"), ("#[1, 2].contains(2)", "true"),
            ("#[3, 1, 2].sortWith[a, b | b - a]", "[3, 2, 1]"), ("#[1, 2].reverse", "[2, 1]"), ("#[1, 2] + #[3]", "[1, 2, 3]"),
            ("#[1, 2].toSet", "[1, 2]"), ("#['a', 'b'].flatMap[#[it, it]]", "[a, a, b, b]"), ("#[1, 2, 3].takeWhile[it < 3]", "[1, 2]"),
            ("#{'a' -> 1, 'b' -> 2}.mapValues[it * 10]", "{a=10, b=20}"), ("#{'a' -> 1, 'b' -> 2}.filter[k, v | v > 1]", "{b=2}"),
            ("1.upTo(3).toList", "[1, 2, 3]"),
        ])
    func collections(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Variables, assignments, compound assignments and loops.
    @Test(
        "Variables and loops",
        arguments: [
            ("val list = newArrayList(1); list += 2; list += #[3, 4]; list", "[1, 2, 3, 4]"),
            ("val list = newArrayList(1, 2, 3); list -= 2; list", "[1, 3]"),
            ("var x = 1; x += 2; x *= 3; x", "9"), ("var i = 0; while (i < 5) i++; i", "5"),
            ("var sum = 0; for (var i = 1; i <= 4; i++) sum += i; sum", "10"), ("var s = ''; for (x : #['a', 'b']) s = s + x; s", "ab"),
            ("var n = 0; do { n = n + 2 } while (n < 5); n", "6"), ("val m = newHashMap('a' -> 1); m.put('b', 2); m", "{a=1, b=2}"),
            ("val m = newLinkedHashMap; m += 'k' -> 'v'; m.keySet", "[k]"), ("var String s; s", "null"), ("var int n; n", "0"),
            ("val l = newArrayList('a', 'b'); l.add(0, 'z'); l.remove(1); l", "[z, b]"),
            ("val l = newArrayList; #[1, 2].forEach[x, i | l += x * 10 + i]; l", "[10, 21]"),
        ])
    func variablesAndLoops(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Switch expressions with type guards, predicates, values and fall-through.
    @Test(
        "Switch expressions",
        arguments: [
            ("switch x : 42 { String: 'string' Integer case x > 40: 'big' Integer: 'small' default: 'other' }", "big"),
            ("switch x : 4 { String: 'string' Integer case x > 40: 'big' Integer: 'small' }", "small"),
            ("switch 'b' { case 'a', case 'b': 'a or b' default: 'other' }", "a or b"),
            ("switch 3.5 { Integer: 'int' default: 'other' }", "other"), ("switch 'z' { case 'a': 1 }", "null"),
            ("switch (1 > 0) { case true: 'yes' case false: 'no' }", "yes"),
        ])
    func switches(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Conditionals, type tests, casts, lambdas and static members of the Java subset.
    @Test(
        "Other expressions",
        arguments: [
            ("if (1 > 2) 'a' else 'b'", "b"), ("if (false) 'a'", "null"), ("'x' instanceof String", "true"),
            ("1 instanceof String", "false"), ("null instanceof Object", "false"), ("(3 as double) / 2", "1.5"),
            ("val f = [int x | x + 1]; f.apply(2)", "3"), ("val g = [String a, String b | a + b]; g.apply('x', 'y')", "xy"),
            ("Math::max(1, 2)", "2"), ("Math.min(1.5, 2)", "1.5"), ("Integer::parseInt('42') + 1", "43"),
            ("String::valueOf(3)", "3"), ("Integer::MAX_VALUE", "2147483647"), ("typeof(String)", "String"),
            ("'k' -> 'v'", "k->v"), ("(1 -> 2).key", "1"), ("{ val a = 1; val b = 2; a + b }", "3"),
        ])
    func otherExpressions(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Run-time problems fail with the right diagnostic codes.
    @Test(
        "Run-time failures",
        arguments: [
            ("#[1].add(2)", XtendDiagnosticCode.immutableCollection), ("val x = 1; x = 2", .invalidAssignment),
            ("1 / 0", .divisionByZero), ("'abc'.chars", .unsupportedJavaMember), ("val String s = null; s.length", .nullPointer),
            ("unknownThing", .unknownFeature), ("if (1) 2", .typeMismatch), ("'a' as Integer", .invalidCast),
            ("#[1, 2].get(5)", .indexOutOfBounds), ("throw new IllegalStateException('boom')", .thrownException),
            ("'abc'.substring(5)", .indexOutOfBounds),
        ])
    func failures(expression: String, expected: XtendDiagnosticCode) async {
        #expect(await XtendTestSupport.failureCode(of: expression) == expected)
    }

    /// The text written with `println` is collected.
    @Test("Standard output")
    func standardOutput() async throws {
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []))
        _ = try await interpreter.evaluate("println('one'); print(2); println")
        #expect(await interpreter.standardOutput == "one\n2\n")
    }

    /// Host values cross into and out of the interpreter.
    @Test("Host values")
    func hostValues() async throws {
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []))
        let result = try await interpreter.evaluate(
            "#[list.size, map.get('k'), flag, ratio * 2, pair.value]",
            variables: [
                "list": .list([.int(1), .int(2)]), "map": .map([(key: .string("k"), value: .string("v"))]),
                "flag": .bool(true), "ratio": .double(1.25), "pair": .pair(.string("a"), .int(9)),
            ])
        #expect(result.description == "[2, v, true, 2.5, 9]")
        #expect(result.elements?.count == 5)
        let set = try await interpreter.evaluate("#{1, 2}")
        #expect(set.elements?.compactMap(\.intValue) == [1, 2])
    }

    /// The step limit stops endless loops.
    @Test("Step limit")
    func stepLimit() async throws {
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []), options: XtendOptions(maximumSteps: 1_000))
        await #expect(throws: XtendError.self) { _ = try await interpreter.evaluate("while (true) {}") }
    }
}

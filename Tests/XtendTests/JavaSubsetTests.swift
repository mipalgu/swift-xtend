//
//  JavaSubsetTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import Xtend

/// Tests of the members and static members of the supported Java subset.
@Suite("Java subset")
struct JavaSubsetTests {
    private func value(_ expression: String) async throws -> String {
        XtendTestSupport.text(try await XtendTestSupport.evaluate(expression))
    }

    /// Static members of `String`, `Integer`, `Long`, `Double`, `Boolean` and `Math`.
    @Test(
        "Static members",
        arguments: [
            ("String::join('-', #['a', 'b'])", "a-b"), ("String::join('+', 'x', 'y')", "x+y"), ("Integer::valueOf(7)", "7"),
            ("Integer::toString(5)", "5"), ("Integer::MIN_VALUE", "-2147483648"), ("Long::MAX_VALUE > 0", "true"),
            ("Long::parseLong(' 12 ')", "12"), ("Double::parseDouble('2.5')", "2.5"), ("Double::valueOf(2)", "2.0"),
            ("Boolean::parseBoolean('TRUE')", "true"), ("Boolean::valueOf(false)", "false"), ("Math::abs(-3)", "3"),
            ("Math::abs(-2.5)", "2.5"), ("Math::floor(2.7)", "2.0"), ("Math::ceil(2.1)", "3.0"), ("Math::round(2.5)", "3"),
            ("Math::sqrt(16)", "4.0"), ("Math::pow(2, 10)", "1024.0"), ("Math::max(2.5, 1)", "2.5"), ("Long::MIN_VALUE < 0", "true"),
        ])
    func staticMembers(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Static members with wrong arguments or outside the subset fail.
    @Test(
        "Static member failures",
        arguments: [
            ("Integer::parseInt('x')", XtendDiagnosticCode.invalidArgument), ("Double::parseDouble('x')", .invalidArgument),
            ("Math::max('a', 'b')", .typeMismatch), ("Math::max(1)", .invalidArgument), ("Math.random()", .unsupportedJavaMember),
        ])
    func staticFailures(expression: String, expected: XtendDiagnosticCode) async {
        #expect(await XtendTestSupport.failureCode(of: expression) == expected)
    }

    /// Members of strings, numbers, Booleans, exceptions and lambda expressions.
    @Test(
        "Value members",
        arguments: [
            ("'a\nb'.lines", "[a, b]"), ("'ab'.toCharArray", "[a, b]"), ("'a'.equals(1)", "false"), ("'a'.equals('a')", "true"),
            ("'Ab'.equalsIgnoreCase(1)", "false"), ("' '.isBlank", "true"), ("' x\n'.strip", "x"), ("'abcabc'.indexOf('c', 3)", "5"),
            ("'ab'.concat('c')", "abc"), ("'abc'.indexOf('z')", "-1"), ("'a'.toString", "a"), ("'Hello'.toLowerCase", "hello"),
            ("3.intValue + 2.5.intValue", "5"), ("3.doubleValue", "3.0"), ("2.5.doubleValue", "2.5"), ("3.compareTo(4)", "-1"),
            ("2.5.compareTo(1)", "1"), ("true.booleanValue", "true"), ("true.toString", "true"), ("1.equals(1)", "true"),
            ("new IllegalArgumentException('bad').message", "bad"), ("new RuntimeException().getMessage", "null"),
            ("new RuntimeException('x').toString", "RuntimeException: x"), ("[int x | x].toString", "Function"),
            ("'abcd'.compareTo('ab')", "2"), ("'x'.hashCode == 'x'.hashCode", "true"), ("#[1].hashCode != 0", "true"),
            ("(1 -> 2).toString", "1->2"), ("(1..2).size", "2"), ("(1..3).contains(2)", "true"), ("2.5.longValue", "2"),
        ])
    func valueMembers(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Members of lists and sets.
    @Test(
        "Collection members",
        arguments: [
            ("#[1, 2, 3].containsAll(#[1, 3])", "true"), ("#[1, 2, 1].indexOf(1)", "0"), ("#[1, 2, 1].lastIndexOf(1)", "2"),
            ("#[1, 2, 3, 4].subList(1, 3)", "[2, 3]"), ("val l = newArrayList(1); l.addAll(#[2, 3]); l", "[1, 2, 3]"),
            ("val l = newArrayList(1, 2, 3); l.removeAll(#[1, 3]); l", "[2]"), ("val l = newArrayList(1); l.clear; l", "[]"),
            ("val l = newArrayList('a', 'b'); l.set(1, 'c'); l", "[a, c]"), ("val l = newArrayList('a', 'b'); l.remove('a'); l", "[b]"),
            ("val s = newHashSet(1); s.add(1); s.add(2); s", "[1, 2]"), ("val s = newLinkedHashSet(1, 2); s.remove(1); s", "[2]"),
            ("newImmutableList(1).size", "1"), ("newImmutableSet(1, 1).size", "1"), ("emptyList.size + emptySet.size + emptyMap.size", "0"),
            ("new java.util.ArrayList(#[1, 2]) => [ add(3) ]", "[1, 2, 3]"), ("new java.util.HashSet(#[1, 1])", "[1]"),
            ("new java.util.HashMap(newHashMap(1 -> 2))", "{1=2}"), ("new java.util.ArrayList", "[]"), ("#[1, 2].equals(#[1, 2])", "true"),
            ("val l = newArrayList; l += #{1, 2}; l", "[1, 2]"), ("#[1].toString", "[1]"), ("#[1, 2].elementsEqual(#[1, 2])", "true"),
            ("#[1, 2, 3].dropWhile[it < 2]", "[2, 3]"), ("#['a'].toInvertedMap[length]", "{a=1}"), ("#[1, 2].toMap([it], [it * 2])", "{1=2, 2=4}"),
            ("#[5, 3].min", "3"), ("#['a', 'bbb'].maxBy[length]", "bbb"), ("#[].head", "null"), ("#[].last", "null"),
            ("#[].reduce[a, b | a]", "null"), ("#[].max", "null"), ("#[].maxBy[it]", "null"), ("#[1].findFirst[it > 5]", "null"),
            ("#[1].findLast[it > 5]", "null"), ("#[1, 2].reverseView", "[2, 1]"), ("#[1].toIterable", "[1]"), ("(1..2).toIterable", "[1, 2]"),
            ("#[1, 2].isNullOrEmpty", "false"), ("#[1, 2].exists[it > 5]", "false"), ("#[1, 2].forall[it > 0]", "true"),
            ("val l = newArrayList; #[1, 2].forEach[l += it]; l", "[1, 2]"), ("newArrayList(1, 2) + #[3]", "[1, 2, 3]"),
        ])
    func collectionMembers(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Members of maps.
    @Test(
        "Map members",
        arguments: [
            ("val m = newHashMap('a' -> 1); m.putAll(newHashMap('b' -> 2)); m", "{a=1, b=2}"),
            ("#{'a' -> 1}.entrySet.map[key + value]", "[a1]"), ("val m = newHashMap('a' -> 1); m.clear; m.isEmpty", "true"),
            ("#{'a' -> 1, 'b' -> 2}.values", "[1, 2]"), ("#{'a' -> 1}.containsValue(1)", "true"), ("#{'a' -> 1}.containsKey('b')", "false"),
            ("#{'a' -> 1}.getOrDefault('z', 0)", "0"), ("val m = newHashMap('a' -> 1, 'b' -> 2); m.remove('a'); m", "{b=2}"),
            ("val m = newHashMap('a' -> 1); m.put('a', 3); m", "{a=3}"), ("#{'a' -> 1}.size", "1"), ("#{'a' -> 1}.toString", "{a=1}"),
            ("val m = newLinkedHashMap; m += newHashMap('k' -> 'v'); m", "{k=v}"), ("val l = newArrayList; #{'a' -> 1}.forEach[k, v | l += k + v]; l", "[a1]"),
            ("newTreeMap('a' -> 1).get('a')", "1"), ("newImmutableMap('a' -> 1).get('a')", "1"), ("#{'a' -> 1} == #{'a' -> 1}", "true"),
            ("var n = 0; for (e : #{'a' -> 1, 'b' -> 2}) n = n + e.value; n", "3"),
        ])
    func mapMembers(expression: String, expected: String) async throws {
        #expect(try await value(expression) == expected)
    }

    /// Collection and map members fail clearly when misused.
    @Test(
        "Collection failures",
        arguments: [
            ("#{'a' -> 1}.put('b', 2)", XtendDiagnosticCode.immutableCollection), ("#[1] += 2", .immutableCollection),
            ("#[1, 2].subList(2, 1)", .indexOutOfBounds), ("#[1].take(-1)", .invalidArgument), ("#[1].filter[it]", .typeMismatch),
            ("#[1, 2].sortWith[a, b | 'x']", .typeMismatch), ("newHashMap(1)", .invalidArgument), ("for (x : 1) {}", .typeMismatch),
            ("for (x : null) {}", .nullPointer), ("'a'.substring('b')", .invalidArgument), ("'a'.indexOf(1)", .invalidArgument),
            ("'a'.matches('(')", .invalidArgument), ("'a'.repeat(-1)", .invalidArgument), ("-'a'", .typeMismatch), ("'a' - 1", .typeMismatch),
            ("'a' < 1", .typeMismatch), ("'a' .. 2", .typeMismatch), ("[x | x].apply(1, 2)", .invalidArgument), ("#[1].map(3)", .typeMismatch),
            ("this", .unknownFeature), ("super", .unknownFeature), ("(1).foo = 2", .invalidAssignment), ("val String s = null; s.x = 1", .nullPointer),
            ("#[#[1]].map[size].foo", .unsupportedJavaMember), ("new Object().foo", .unknownFeature), ("typeof(Unknown)", .unsupportedJavaType),
        ])
    func collectionFailures(expression: String, expected: XtendDiagnosticCode) async {
        #expect(await XtendTestSupport.failureCode(of: expression) == expected)
    }

    /// Null-safe assignment does nothing for a null receiver, and an unsupported type is
    /// rejected before evaluation.
    @Test("Assignments to members")
    func memberAssignments() async throws {
        #expect(try await value("val String s = null; s?.x = 1; 'done'") == "done")
        let interpreter = try XtendInterpreter(program: XtendProgram(sources: []))
        await #expect(throws: XtendError.self) { _ = try await interpreter.evaluate("typeof(java.io.File)") }
        #expect(try await interpreter.evaluate("return 5").intValue == 5)
        #expect(try await interpreter.evaluate("#{}").elements?.isEmpty == true)
        #expect(try await interpreter.evaluate("new Object() instanceof Object").boolValue == true)
    }
}

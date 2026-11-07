//
//  XtendLexer.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A token of Xtend source text.
struct XtendToken: Sendable {
    /// The lexical category of a token.
    enum Kind: Sendable, Equatable {
        /// A name, possibly escaped with a caret.
        case identifier
        /// A reserved word.
        case keyword
        /// A whole-number literal.
        case integer
        /// A floating point literal.
        case double
        /// A string literal; the text is the decoded value.
        case string
        /// The opening delimiter of a rich string.
        case richStart
        /// Static text of a rich string; the text is the text without comments.
        case richText
        /// An opening guillemet inside a rich string.
        case richOpen
        /// A closing guillemet that returns to the text of a rich string.
        case richClose
        /// A comment inside a rich string, from `«««` to the end of the line.
        case richComment
        /// The closing delimiter of a rich string.
        case richEnd
        /// An operator or punctuation.
        case symbol
        /// The end of the text.
        case endOfFile
    }

    /// The lexical category.
    var kind: Kind

    /// The text of the token, decoded for literals and without the escape caret for names.
    var text: String

    /// The UTF-8 offset of the first byte of the token.
    var start: Int

    /// The UTF-8 offset just past the token.
    var end: Int

    /// Whether the token is the given symbol.
    func isSymbol(_ symbol: String) -> Bool { kind == .symbol && text == symbol }

    /// Whether the token is the given keyword.
    func isKeyword(_ keyword: XtendLanguage.Keyword) -> Bool { kind == .keyword && text == keyword.rawValue }
}

/// Splits Xtend source text into tokens.
///
/// The lexer switches between code and rich string text: a rich string delimiter starts
/// text, a guillemet returns to code until the matching closing guillemet, and nested rich
/// strings inside interpolations are handled with a stack of modes. Comments are collected
/// separately for syntax highlighting.
struct XtendLexer {
    /// The symbols, longest first so that the longest match wins.
    private static let symbols: [String] = [
        "===", "!==", "..<", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "++", "--",
        "->", "=>", "?.", "?:", "::", "..", "**", "+", "-", "*", "/", "%", "!", "<", ">", "=", "(", ")", "[",
        "]", "{", "}", ",", ";", ".", ":", "?", "#", "|", "@", "&",
    ]

    /// The reserved words by spelling.
    private static let keywords = Set(XtendLanguage.Keyword.allCases.map(\.rawValue))

    /// The lexical mode that determines how the next scalar is read.
    private enum Mode {
        /// Ordinary Xtend code.
        case code
        /// Code inside a guillemet interpolation of a rich string.
        case interpolation
        /// The literal text of a rich string.
        case text
    }

    /// The Unicode scalars of the source text.
    private let scalars: [Unicode.Scalar]
    /// The UTF-8 offset of each scalar, with a final entry for the end of the text.
    private let offsets: [Int]
    /// The identifier of the document, if any.
    private let document: String?
    /// The index of the next scalar to read.
    private var index = 0
    /// The stack of lexical modes, with the current mode last.
    private var modes: [Mode] = [.code]

    /// The tokens in order, ending with an end-of-file token.
    private(set) var tokens: [XtendToken] = []

    /// The comments, for syntax highlighting.
    private(set) var comments: [SourceToken] = []

    /// Problems found while splitting the text, as UTF-8 offset ranges with messages.
    private(set) var problems: [(code: XtendDiagnosticCode, message: String, start: Int, end: Int)] = []

    /// Creates a lexer and tokenises the text.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - lineTable: The line table of the text, for comment ranges.
    ///   - document: The identifier of the document.
    init(_ text: String, lineTable: LineTable, document: String?) {
        scalars = Array(text.unicodeScalars)
        var offsets: [Int] = []
        offsets.reserveCapacity(scalars.count + 1)
        var offset = 0
        for scalar in scalars {
            offsets.append(offset)
            offset += UTF8.width(scalar)
        }
        offsets.append(offset)
        self.offsets = offsets
        self.document = document
        run(lineTable: lineTable)
    }

    /// Returns the scalar at a distance from the current position.
    ///
    /// - Parameter distance: The number of scalars ahead of the current position.
    /// - Returns: The scalar, or `nil` if it lies beyond the end of the text.
    private func peek(_ distance: Int = 0) -> Unicode.Scalar? {
        let position = index + distance
        return position < scalars.count ? scalars[position] : nil
    }

    /// Tests whether the text occurs at a position.
    ///
    /// - Parameters:
    ///   - text: The text to look for.
    ///   - position: The index of the scalar at which the text would start.
    /// - Returns: `true` if the scalars at the position spell the text.
    private func matches(_ text: String, at position: Int) -> Bool {
        var cursor = position
        for scalar in text.unicodeScalars {
            guard cursor < scalars.count, scalars[cursor] == scalar else { return false }
            cursor += 1
        }
        return true
    }

    /// Appends a token that ends at the current position.
    ///
    /// - Parameters:
    ///   - kind: The kind of the token.
    ///   - text: The text of the token.
    ///   - start: The index of the first scalar of the token.
    private mutating func add(_ kind: XtendToken.Kind, _ text: String, from start: Int) {
        tokens.append(XtendToken(kind: kind, text: text, start: offsets[start], end: offsets[index]))
    }

    /// Records a problem that ends at the current position.
    ///
    /// - Parameters:
    ///   - code: The diagnostic code.
    ///   - message: The description of the problem.
    ///   - start: The index of the first scalar of the problem.
    private mutating func problem(_ code: XtendDiagnosticCode, _ message: String, from start: Int) {
        problems.append((code, message, offsets[start], offsets[max(index, start)]))
    }

    /// Reads the whole text, switching between code and rich string modes.
    ///
    /// - Parameter lineTable: The line table of the text, for comment ranges.
    private mutating func run(lineTable: LineTable) {
        while index < scalars.count {
            switch modes[modes.count - 1] {
            case .text:
                lexText(lineTable: lineTable)
            case .code, .interpolation:
                lexCode(lineTable: lineTable)
            }
        }
        if modes.contains(where: { if case .text = $0 { return true } else { return false } })
            || modes.count > 1
        {
            problems.append((.unterminatedRichString, "Unterminated rich string", offsets[index], offsets[index]))
        }
        tokens.append(XtendToken(kind: .endOfFile, text: "", start: offsets[index], end: offsets[index]))
    }

    // MARK: - Code

    /// Reads the next piece of code: whitespace, a comment, a literal, an identifier or a symbol.
    ///
    /// - Parameter lineTable: The line table of the text, for comment ranges.
    private mutating func lexCode(lineTable: LineTable) {
        guard let scalar = peek() else { return }
        let start = index
        if scalar.properties.isWhitespace {
            index += 1
            return
        }
        if scalar == "/", peek(1) == "/" {
            while let next = peek(), next != "\n", next != "\r" { index += 1 }
            comments.append(SourceToken(kind: .comment, range: lineTable.range(fromUTF8Offset: offsets[start], to: offsets[index])))
            return
        }
        if scalar == "/", peek(1) == "*" {
            let isDocumentation = peek(2) == "*" && peek(3) != "/"
            index += 2
            var closed = false
            while index < scalars.count {
                if scalars[index] == "*", peek(1) == "/" {
                    index += 2
                    closed = true
                    break
                }
                index += 1
            }
            if !closed { problem(.unterminatedComment, "Unterminated block comment", from: start) }
            comments.append(
                SourceToken(
                    kind: isDocumentation ? .documentation : .comment,
                    range: lineTable.range(fromUTF8Offset: offsets[start], to: offsets[index])))
            return
        }
        if matches(XtendLanguage.richStringDelimiter, at: index) {
            index += 3
            add(.richStart, XtendLanguage.richStringDelimiter, from: start)
            modes.append(.text)
            return
        }
        if scalar == XtendLanguage.closingGuillemet {
            index += 1
            if case .interpolation = modes[modes.count - 1] {
                modes.removeLast()
                add(.richClose, String(scalar), from: start)
            } else {
                problem(.invalidCharacter, "Unexpected '\(scalar)' outside a rich string", from: start)
            }
            return
        }
        if scalar == "'" || scalar == "\"" {
            lexString(quote: scalar)
            return
        }
        if scalar.properties.numericType != nil, ("0"..."9").contains(scalar) {
            lexNumber()
            return
        }
        if scalar == "^" || Self.isIdentifierStart(scalar) {
            let escaped = scalar == "^"
            if escaped { index += 1 }
            let nameStart = index
            while let next = peek(), Self.isIdentifierPart(next) { index += 1 }
            let name = String(String.UnicodeScalarView(scalars[nameStart..<index]))
            if name.isEmpty {
                problem(.invalidCharacter, "Expected a name after '^'", from: start)
                return
            }
            add(!escaped && Self.keywords.contains(name) ? .keyword : .identifier, name, from: start)
            return
        }
        for symbol in Self.symbols where matches(symbol, at: index) {
            index += symbol.unicodeScalars.count
            add(.symbol, symbol, from: start)
            return
        }
        index += 1
        problem(.invalidCharacter, "Unexpected character '\(scalar)'", from: start)
    }

    /// Tests whether a scalar can start an identifier.
    ///
    /// - Parameter scalar: The scalar.
    /// - Returns: `true` if the scalar can start an identifier.
    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar == "$" || scalar.properties.isAlphabetic
    }

    /// Tests whether a scalar can continue an identifier.
    ///
    /// - Parameter scalar: The scalar.
    /// - Returns: `true` if the scalar can be part of an identifier.
    private static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierStart(scalar) || ("0"..."9").contains(scalar)
    }

    /// Reads a quoted string literal, resolving escape sequences.
    ///
    /// - Parameter quote: The quote character that opens and closes the literal.
    private mutating func lexString(quote: Unicode.Scalar) {
        let start = index
        index += 1
        var value = ""
        while let scalar = peek() {
            if scalar == quote {
                index += 1
                add(.string, value, from: start)
                return
            }
            if scalar == "\\", let escaped = peek(1) {
                index += 2
                switch escaped {
                case "n": value += "\n"
                case "t": value += "\t"
                case "r": value += "\r"
                case "b": value += "\u{08}"
                case "f": value += "\u{0C}"
                case "0": value += "\0"
                case "u":
                    var hex = ""
                    while hex.count < 4, let digit = peek(), digit.properties.isASCIIHexDigit {
                        hex.unicodeScalars.append(digit)
                        index += 1
                    }
                    if let code = UInt32(hex, radix: 16), let decoded = Unicode.Scalar(code) {
                        value.unicodeScalars.append(decoded)
                    }
                default: value.unicodeScalars.append(escaped)
                }
                continue
            }
            value.unicodeScalars.append(scalar)
            index += 1
        }
        problem(.unterminatedString, "Unterminated string literal", from: start)
        add(.string, value, from: start)
    }

    /// Reads an integer or floating point literal, including any exponent or type suffix.
    private mutating func lexNumber() {
        let start = index
        var isDouble = false
        if peek() == "0", let x = peek(1), x == "x" || x == "X" {
            index += 2
            while let next = peek(), next.properties.isASCIIHexDigit || next == "_" { index += 1 }
            if let suffix = peek(), suffix == "L" || suffix == "l" { index += 1 }
        } else {
            while let next = peek(), ("0"..."9").contains(next) || next == "_" { index += 1 }
            if peek() == ".", let digit = peek(1), ("0"..."9").contains(digit) {
                isDouble = true
                index += 1
                while let next = peek(), ("0"..."9").contains(next) || next == "_" { index += 1 }
            }
            if let exponent = peek(), exponent == "e" || exponent == "E" {
                let sign = peek(1)
                let digitOffset = (sign == "+" || sign == "-") ? 2 : 1
                if let digit = peek(digitOffset), ("0"..."9").contains(digit) {
                    isDouble = true
                    index += digitOffset
                    while let next = peek(), ("0"..."9").contains(next) { index += 1 }
                }
            }
            if let suffix = peek() {
                switch suffix {
                case "d", "D", "f", "F":
                    isDouble = true
                    index += 1
                case "l", "L":
                    index += 1
                default: break
                }
            }
        }
        let text = String(String.UnicodeScalarView(scalars[start..<index]))
        add(isDouble ? .double : .integer, text, from: start)
    }

    // MARK: - Rich string text

    /// Reads the literal text of a rich string up to the next delimiter or interpolation.
    ///
    /// - Parameter lineTable: The line table of the text, for comment ranges.
    private mutating func lexText(lineTable: LineTable) {
        let start = index
        var value = ""
        var segmentStart = index
        /// Emits the pending text as a rich text token and clears it.
        ///
        /// - Parameter lexer: The lexer that receives the token.
        func flush(_ lexer: inout XtendLexer) {
            if lexer.index > segmentStart || !value.isEmpty {
                lexer.tokens.append(
                    XtendToken(kind: .richText, text: value, start: lexer.offsets[segmentStart], end: lexer.offsets[lexer.index]))
            }
            value = ""
        }
        _ = start
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "'" && matches(XtendLanguage.richStringDelimiter, at: index) {
                var run = 0
                while matches("'", at: index + run) { run += 1 }
                for _ in 0..<(run - 3) { value += "'" }
                index += run - 3
                flush(&self)
                let delimiterStart = index
                index += 3
                add(.richEnd, XtendLanguage.richStringDelimiter, from: delimiterStart)
                modes.removeLast()
                return
            }
            if scalar == XtendLanguage.openingGuillemet {
                if matches("«««", at: index) {
                    flush(&self)
                    let commentStart = index
                    while let next = peek(), next != "\n", next != "\r" { index += 1 }
                    add(.richComment, "", from: commentStart)
                    comments.append(
                        SourceToken(kind: .comment, range: lineTable.range(fromUTF8Offset: offsets[commentStart], to: offsets[index])))
                    segmentStart = index
                    continue
                }
                flush(&self)
                let openStart = index
                index += 1
                add(.richOpen, String(scalar), from: openStart)
                modes.append(.interpolation)
                return
            }
            value.unicodeScalars.append(scalar)
            index += 1
        }
        flush(&self)
    }
}

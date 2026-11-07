//
//  XtendParser.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The result of parsing an Xtend document.
public struct XtendParseResult: Sendable {
    /// The syntax tree; members that could not be parsed are left out.
    public var file: XtendFile

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The classified tokens for syntax highlighting, in source order.
    public var tokens: [SourceToken]

    /// The outline of the document: its classes with their fields and methods.
    public var outline: [OutlineNode]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - file: The syntax tree.
    ///   - diagnostics: The problems found.
    ///   - tokens: The classified tokens.
    ///   - outline: The outline of the document.
    public init(file: XtendFile, diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]) {
        self.file = file
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }

    /// Whether any diagnostic is an error.
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

/// Parses Xtend source text into a syntax tree.
///
/// The parser is a hand-written recursive descent parser for the interpreted subset of
/// Xtend. It recovers from errors at member boundaries, so that one malformed method does not
/// hide the rest of a class, and it reports constructs outside the subset (such as `try`,
/// interfaces and enumerations) as ``XtendDiagnosticCode/unsupportedConstruct``.
public enum XtendParser {
    /// Parses a document.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The identifier of the document, such as its URI.
    /// - Returns: The syntax tree, diagnostics, highlighting tokens and outline.
    public static func parse(_ text: String, document: String) -> XtendParseResult {
        let lineTable = LineTable(text)
        let lexer = XtendLexer(text, lineTable: lineTable, document: document)
        var parser = XtendParserState(tokens: lexer.tokens, lineTable: lineTable, document: document)
        for problem in lexer.problems {
            parser.diagnostics.append(
                .xtend(
                    problem.code, problem.message, range: lineTable.range(fromUTF8Offset: problem.start, to: problem.end),
                    document: document))
        }
        let file = parser.parseFile()
        let tokens = (highlightTokens(lexer.tokens, lineTable: lineTable) + lexer.comments)
            .sorted { $0.range.start.utf8Offset < $1.range.start.utf8Offset }
        let diagnostics = parser.diagnostics.sorted {
            ($0.range?.start.utf8Offset ?? 0) < ($1.range?.start.utf8Offset ?? 0)
        }
        return XtendParseResult(file: file, diagnostics: diagnostics, tokens: tokens, outline: outline(of: file))
    }

    /// Parses a standalone expression, which may be a block of several expressions.
    ///
    /// - Parameters:
    ///   - text: The source text of the expression.
    ///   - document: The identifier used in diagnostics.
    /// - Returns: The expression, or `nil` if it could not be parsed, and the diagnostics.
    public static func parseExpression(_ text: String, document: String) -> (XtendExpression?, [SourceDiagnostic]) {
        let lineTable = LineTable(text)
        let lexer = XtendLexer(text, lineTable: lineTable, document: document)
        var parser = XtendParserState(tokens: lexer.tokens, lineTable: lineTable, document: document)
        for problem in lexer.problems {
            parser.diagnostics.append(
                .xtend(
                    problem.code, problem.message, range: lineTable.range(fromUTF8Offset: problem.start, to: problem.end),
                    document: document))
        }
        let expression = parser.parseStandaloneExpression()
        return (expression, parser.diagnostics)
    }

    /// Classifies the lexer tokens for syntax highlighting.
    private static func highlightTokens(_ tokens: [XtendToken], lineTable: LineTable) -> [SourceToken] {
        var result: [SourceToken] = []
        var afterGuillemet = false
        var afterAt = false
        for token in tokens where token.kind != .endOfFile {
            let kind: SourceTokenKind
            switch token.kind {
            case .identifier:
                if afterAt {
                    kind = .directive
                } else if afterGuillemet, XtendLanguage.TemplateKeyword(rawValue: token.text) != nil {
                    kind = .keyword
                } else if XtendLanguage.TemplateKeyword(rawValue: token.text) != nil
                    && [.BEFORE, .SEPARATOR, .AFTER].contains(XtendLanguage.TemplateKeyword(rawValue: token.text))
                {
                    kind = .keyword
                } else if token.text.first?.isUppercase == true {
                    kind = .typeName
                } else {
                    kind = .identifier
                }
            case .keyword:
                kind = token.text == "true" || token.text == "false" ? .boolean : .keyword
            case .integer, .double: kind = .number
            case .string, .richText, .richStart, .richEnd: kind = .string
            case .richOpen, .richClose: kind = .punctuation
            case .richComment: continue
            case .symbol:
                kind = token.text == "@" ? .directive : ("(){}[],;.".contains(token.text) ? .punctuation : .operator)
            case .endOfFile: continue
            }
            afterGuillemet = token.kind == .richOpen
            afterAt = token.isSymbol("@")
            result.append(SourceToken(kind: kind, range: lineTable.range(fromUTF8Offset: token.start, to: token.end)))
        }
        return result
    }

    /// Builds the outline of a file.
    private static func outline(of file: XtendFile) -> [OutlineNode] {
        file.classes.map { declaration in
            var children: [OutlineNode] = []
            for field in declaration.fields {
                children.append(
                    OutlineNode(
                        id: "\(declaration.qualifiedName).\(field.name)", kind: XtendLanguage.OutlineKind.field.rawValue,
                        name: field.name, detail: field.type?.description, range: field.range,
                        selectionRange: field.nameRange))
            }
            for (index, method) in declaration.methods.enumerated() {
                let kind: XtendLanguage.OutlineKind =
                    method.isConstructor
                    ? .constructor
                    : method.modifiers.isDispatch ? .dispatchMethod : method.createClause != nil ? .createMethod : .method
                let parameters = method.parameters.map { $0.type?.description ?? $0.name }.joined(separator: ", ")
                children.append(
                    OutlineNode(
                        id: "\(declaration.qualifiedName).\(method.name)#\(index)", kind: kind.rawValue,
                        name: method.name, detail: "(\(parameters))" + (method.returnType.map { ": \($0.description)" } ?? ""),
                        range: method.range, selectionRange: method.nameRange))
            }
            return OutlineNode(
                id: declaration.qualifiedName, kind: XtendLanguage.OutlineKind.class.rawValue, name: declaration.name,
                detail: declaration.superclass?.description, range: declaration.range,
                selectionRange: declaration.nameRange, children: children)
        }
    }
}

/// A failure that unwinds the parser to the nearest recovery point.
struct XtendParseFailure: Error {}

/// The mutable state of a parse.
struct XtendParserState {
    /// The tokens of the document, ending with an end-of-file token.
    private let tokens: [XtendToken]
    /// The line table that converts offsets to line and column positions.
    private let lineTable: LineTable
    /// The identifier of the document, used in diagnostics.
    private let document: String
    /// The index of the current token.
    private var position = 0
    /// The problems found so far, in the order they were reported.
    var diagnostics: [SourceDiagnostic] = []

    /// Creates parser state.
    ///
    /// - Parameters:
    ///   - tokens: The tokens, ending with an end-of-file token.
    ///   - lineTable: The line table of the source text.
    ///   - document: The identifier of the document.
    init(tokens: [XtendToken], lineTable: LineTable, document: String) {
        self.tokens = tokens
        self.lineTable = lineTable
        self.document = document
    }

    // MARK: - Token access

    /// The token at the current position.
    private var current: XtendToken { tokens[position] }

    /// Returns a token ahead of the current position.
    ///
    /// - Parameter distance: The number of tokens to look ahead.
    /// - Returns: The token at that distance, or the end-of-file token if it lies beyond the end.
    private func peek(_ distance: Int) -> XtendToken {
        tokens[min(position + distance, tokens.count - 1)]
    }

    /// Whether the current token is the end-of-file token.
    private var atEnd: Bool { current.kind == .endOfFile }

    /// Consumes the current token.
    ///
    /// - Returns: The consumed token. The position stays on the end-of-file token once it is reached.
    @discardableResult
    private mutating func advance() -> XtendToken {
        let token = tokens[position]
        if position < tokens.count - 1 { position += 1 }
        return token
    }

    /// Consumes the current token if it is the given symbol.
    ///
    /// - Parameter symbol: The symbol text to accept.
    /// - Returns: `true` if the symbol was consumed.
    private mutating func accept(_ symbol: String) -> Bool {
        guard current.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    /// Consumes the current token if it is the given keyword.
    ///
    /// - Parameter keyword: The keyword to accept.
    /// - Returns: `true` if the keyword was consumed.
    private mutating func accept(_ keyword: XtendLanguage.Keyword) -> Bool {
        guard current.isKeyword(keyword) else { return false }
        advance()
        return true
    }

    /// Consumes the given symbol or fails.
    ///
    /// - Parameter symbol: The symbol text that must be next.
    /// - Throws: ``XtendParseFailure`` after reporting a diagnostic if the symbol is not next.
    private mutating func expect(_ symbol: String) throws {
        guard accept(symbol) else { throw unexpected("'\(symbol)'") }
    }

    /// Consumes the given keyword or fails.
    ///
    /// - Parameter keyword: The keyword that must be next.
    /// - Throws: ``XtendParseFailure`` after reporting a diagnostic if the keyword is not next.
    private mutating func expect(_ keyword: XtendLanguage.Keyword) throws {
        guard accept(keyword) else { throw unexpected("'\(keyword.rawValue)'") }
    }

    /// Consumes an identifier or fails.
    ///
    /// - Returns: The identifier token.
    /// - Throws: ``XtendParseFailure`` after reporting a diagnostic if the current token is not an identifier.
    private mutating func expectIdentifier() throws -> XtendToken {
        guard current.kind == .identifier else { throw unexpected("a name") }
        return advance()
    }

    /// Creates a source range from two UTF-8 offsets.
    ///
    /// - Parameters:
    ///   - start: The offset of the first byte.
    ///   - end: The offset after the last byte; values before `start` are treated as `start`.
    /// - Returns: The corresponding source range.
    private func range(from start: Int, to end: Int) -> SourceRange {
        lineTable.range(fromUTF8Offset: start, to: max(start, end))
    }

    /// Creates the source range of a token.
    ///
    /// - Parameter token: The token to locate.
    /// - Returns: The range covered by the token.
    private func range(of token: XtendToken) -> SourceRange {
        range(from: token.start, to: token.end)
    }

    /// The range from a start offset to the end of the previously consumed token.
    private func range(from start: Int) -> SourceRange {
        range(from: start, to: position > 0 ? tokens[position - 1].end : start)
    }

    /// Reports an unexpected token and creates the failure that unwinds the parser.
    ///
    /// - Parameter expectation: A description of what was expected.
    /// - Returns: The failure for the caller to throw.
    private mutating func unexpected(_ expectation: String) -> XtendParseFailure {
        let found = atEnd ? "the end of the document" : "'\(current.text)'"
        report(.unexpectedToken, "Expected \(expectation) but found \(found)", range: range(of: current))
        return XtendParseFailure()
    }

    /// Records a diagnostic.
    ///
    /// - Parameters:
    ///   - code: The diagnostic code.
    ///   - message: The message to show.
    ///   - range: The source range the diagnostic applies to.
    private mutating func report(_ code: XtendDiagnosticCode, _ message: String, range: SourceRange) {
        diagnostics.append(.xtend(code, message, range: range, document: document))
    }

    // MARK: - File

    /// Parses a whole file.
    mutating func parseFile() -> XtendFile {
        var file = XtendFile(document: document)
        if current.isKeyword(.package) {
            advance()
            file.packageName = try? parseQualifiedName()
            _ = accept(";")
        }
        while current.isKeyword(.import) {
            let start = advance().start
            var item = XtendImport(name: "", range: range(of: current))
            if accept(.static) { item.isStatic = true }
            if accept(.extension) { item.isExtension = true }
            if let name = try? parseQualifiedName() {
                item.name = name
                if current.isSymbol("."), peek(1).isSymbol("*") {
                    advance()
                    advance()
                    item.isWildcard = true
                }
            }
            _ = accept(";")
            item.range = range(from: start)
            file.imports.append(item)
        }
        while !atEnd {
            let before = position
            do {
                if let declaration = try parseTypeDeclaration(packageName: file.packageName) {
                    file.classes.append(declaration)
                }
            } catch {
                skipToTypeDeclaration()
            }
            if position == before { advance() }
        }
        return file
    }

    /// Parses a dot-separated name.
    ///
    /// - Returns: The name, with its segments joined by dots.
    /// - Throws: ``XtendParseFailure`` if the name does not start with an identifier.
    private mutating func parseQualifiedName() throws -> String {
        var name = try expectIdentifier().text
        while current.isSymbol("."), peek(1).kind == .identifier {
            advance()
            name += "." + advance().text
        }
        return name
    }

    /// Skips tokens up to the next class, interface or enumeration keyword, or the end of the document.
    private mutating func skipToTypeDeclaration() {
        while !atEnd {
            if current.isKeyword(.class) || current.isKeyword(.interface) || current.isKeyword(.enum) { return }
            advance()
        }
    }

    /// Parses any annotations at the current position, skipping their arguments.
    ///
    /// - Returns: The annotations found.
    /// - Throws: ``XtendParseFailure`` if an annotation is malformed.
    private mutating func parseAnnotations() throws -> [XtendAnnotation] {
        var annotations: [XtendAnnotation] = []
        while current.isSymbol("@") {
            let start = advance().start
            if current.isKeyword(.interface) {
                position -= 1
                break
            }
            let name = try parseQualifiedName()
            if current.isSymbol("(") { try skipBalanced(open: "(", close: ")") }
            annotations.append(XtendAnnotation(name: name, range: range(from: start)))
        }
        return annotations
    }

    /// Skips a balanced pair of delimiters, including anything nested between them.
    ///
    /// - Parameters:
    ///   - open: The opening symbol, which must be next.
    ///   - close: The closing symbol that ends the skipped region.
    /// - Throws: ``XtendParseFailure`` if the opening symbol is missing or the closing symbol is never found.
    private mutating func skipBalanced(open: String, close: String) throws {
        try expect(open)
        var depth = 1
        while depth > 0 {
            if atEnd { throw unexpected("'\(close)'") }
            if current.isSymbol(open) { depth += 1 }
            if current.isSymbol(close) { depth -= 1 }
            advance()
        }
    }

    /// Parses a class declaration, or skips an unsupported kind of type declaration.
    ///
    /// - Parameter packageName: The package of the file, if it has one.
    /// - Returns: The class, or `nil` if the declaration is of an unsupported kind and was skipped.
    /// - Throws: ``XtendParseFailure`` if the declaration is malformed.
    private mutating func parseTypeDeclaration(packageName: String?) throws -> XtendClass? {
        let start = current.start
        let annotations = try parseAnnotations()
        var isAbstract = false
        while current.kind == .keyword,
            [.public, .private, .protected, .abstract, .final, .static].contains(XtendLanguage.Keyword(rawValue: current.text))
        {
            if current.isKeyword(.abstract) { isAbstract = true }
            advance()
        }
        if current.isKeyword(.interface) || current.isKeyword(.enum) || current.isSymbol("@")
            || current.isKeyword(.annotation)
        {
            let keyword = current.text == "@" ? "annotation" : current.text
            report(
                .unsupportedConstruct, "Declarations of kind '\(keyword)' are not supported; only classes are",
                range: range(of: current))
            while !atEnd, !current.isSymbol("{") { advance() }
            if current.isSymbol("{") { try skipBalanced(open: "{", close: "}") }
            return nil
        }
        guard accept(.class) else { throw unexpected("a class declaration") }
        let nameToken = try expectIdentifier()
        if current.isSymbol("<") { try skipBalanced(open: "<", close: ">") }
        var superclass: XtendTypeReference?
        var interfaces: [XtendTypeReference] = []
        if accept(.extends) { superclass = try parseTypeReference() }
        if accept(.implements) {
            repeat { interfaces.append(try parseTypeReference()) } while accept(",")
        }
        try expect("{")
        var fields: [XtendField] = []
        var methods: [XtendMethod] = []
        while !current.isSymbol("}") && !atEnd {
            let before = position
            do {
                switch try parseMember() {
                case .field(let field)?: fields.append(field)
                case .method(let method)?: methods.append(method)
                case nil: break
                }
            } catch {
                skipToMember()
            }
            if position == before { advance() }
        }
        if !accept("}") { _ = unexpected("'}'") }
        return XtendClass(
            name: nameToken.text, packageName: packageName, superclass: superclass, interfaces: interfaces,
            isAbstract: isAbstract, fields: fields, methods: methods, annotations: annotations, document: document,
            range: range(from: start), nameRange: range(of: nameToken))
    }

    /// Skips to the start of the next member or the end of the class body.
    private mutating func skipToMember() {
        var depth = 0
        while !atEnd {
            if depth == 0 {
                if current.isSymbol("}") { return }
                if current.isKeyword(.def) || current.isKeyword(.override) || current.isSymbol("@") { return }
            }
            if current.isSymbol("{") { depth += 1 }
            if current.isSymbol("}") { depth -= 1 }
            if current.kind == .richStart {
                skipRichString()
                continue
            }
            advance()
        }
    }

    /// Skips a rich string, including any nested rich strings, up to its closing token.
    private mutating func skipRichString() {
        var depth = 0
        while !atEnd {
            let token = advance()
            if token.kind == .richStart { depth += 1 }
            if token.kind == .richEnd {
                depth -= 1
                if depth <= 0 { return }
            }
        }
    }

    /// A member of a class body.
    private enum Member {
        /// A field declaration.
        case field(XtendField)
        /// A method or constructor declaration.
        case method(XtendMethod)
    }

    /// Parses a member of a class body.
    ///
    /// - Returns: The field or method, or `nil` if the member was an empty statement.
    /// - Throws: ``XtendParseFailure`` if the member is malformed.
    private mutating func parseMember() throws -> Member? {
        let start = current.start
        let annotations = try parseAnnotations()
        var modifiers = XtendModifiers()
        var isMethod = false
        var isConstructor = false
        var declaresVariable: Bool?
        var createClause: XtendCreateClause?
        loop: while current.kind == .keyword {
            switch XtendLanguage.Keyword(rawValue: current.text) {
            case .public, .private, .protected:
                modifiers.visibility = current.text
            case .static: modifiers.isStatic = true
            case .extension: modifiers.isExtension = true
            case .abstract: modifiers.isAbstract = true
            case .final: modifiers.isFinal = true
            case .def: isMethod = true
            case .override:
                isMethod = true
                modifiers.isOverride = true
            case .dispatch: modifiers.isDispatch = true
            case .val: declaresVariable = false
            case .var: declaresVariable = true
            case .new:
                isConstructor = true
                advance()
                break loop
            case .create:
                advance()
                var name = XtendLanguage.implicitParameter
                if current.kind == .identifier, peek(1).isSymbol(":") {
                    name = advance().text
                    advance()
                }
                let expression = try parseExpression()
                createClause = XtendCreateClause(name: name, expression: expression)
                continue loop
            case .synchronized:
                report(.unsupportedConstruct, "Synchronised methods are not supported", range: range(of: current))
            default: break loop
            }
            advance()
        }
        if current.isSymbol(";") {
            advance()
            return nil
        }
        if isConstructor {
            let nameRange = range(from: start)
            let parameters = try parseParameters()
            try skipThrows()
            let body = try parseBlock()
            return .method(
                XtendMethod(
                    name: XtendLanguage.constructorName, parameters: parameters, returnType: nil, modifiers: modifiers,
                    createClause: nil, body: body, annotations: annotations, range: range(from: start),
                    nameRange: nameRange))
        }
        if isMethod || createClause != nil {
            var returnType: XtendTypeReference?
            if !(current.kind == .identifier && peek(1).isSymbol("(")) {
                returnType = try parseTypeReference()
            }
            let nameToken = try expectIdentifier()
            let parameters = try parseParameters()
            try skipThrows()
            var body: XtendExpression?
            if current.isSymbol("{") {
                body = try parseBlock()
            } else if current.kind == .richStart {
                body = try parseRichString()
            }
            _ = accept(";")
            return .method(
                XtendMethod(
                    name: nameToken.text, parameters: parameters, returnType: returnType, modifiers: modifiers,
                    createClause: createClause, body: body, annotations: annotations, range: range(from: start),
                    nameRange: range(of: nameToken)))
        }
        var type: XtendTypeReference?
        if startsTypedDeclaration() { type = try parseTypeReference() }
        let nameToken = try expectIdentifier()
        var initialiser: XtendExpression?
        if accept("=") { initialiser = try parseExpression() }
        _ = accept(";")
        return .field(
            XtendField(
                name: nameToken.text, type: type, modifiers: modifiers,
                isFinal: declaresVariable == false || modifiers.isFinal, initialiser: initialiser,
                annotations: annotations, range: range(from: start), nameRange: range(of: nameToken)))
    }

    /// Skips an optional `throws` clause.
    ///
    /// - Throws: ``XtendParseFailure`` if an exception type is malformed.
    private mutating func skipThrows() throws {
        if accept(.throws) {
            repeat { _ = try parseTypeReference() } while accept(",")
        }
    }

    /// Parses a parenthesised parameter list.
    ///
    /// - Returns: The parameters.
    /// - Throws: ``XtendParseFailure`` if the list is malformed.
    private mutating func parseParameters() throws -> [XtendParameter] {
        try expect("(")
        var parameters: [XtendParameter] = []
        if !current.isSymbol(")") {
            repeat {
                let start = current.start
                _ = try parseAnnotations()
                var isExtension = false
                while current.isKeyword(.extension) || current.isKeyword(.final) {
                    if current.isKeyword(.extension) { isExtension = true }
                    advance()
                }
                let type = try parseTypeReference()
                if current.isSymbol("...") { advance() }
                let name = try expectIdentifier()
                parameters.append(XtendParameter(name: name.text, type: type, isExtension: isExtension, range: range(from: start)))
            } while accept(",")
        }
        try expect(")")
        return parameters
    }

    // MARK: - Types

    /// Parses a type reference, including generic arguments, arrays and function types.
    private mutating func parseTypeReference() throws -> XtendTypeReference {
        let start = current.start
        if current.isSymbol("(") || current.isSymbol("=>") {
            var arguments: [XtendTypeReference] = []
            if accept("(") {
                if !current.isSymbol(")") {
                    repeat { arguments.append(try parseTypeReference()) } while accept(",")
                }
                try expect(")")
            }
            try expect("=>")
            arguments.append(try parseTypeReference())
            return XtendTypeReference(name: XtendTypeReference.functionTypeName, arguments: arguments, range: range(from: start))
        }
        if current.isSymbol("?") {
            advance()
            if accept(.extends) || accept(.super) { return try parseTypeReference() }
            return XtendTypeReference(name: XtendBuiltinType.object.rawValue, range: range(from: start))
        }
        let name = try parseQualifiedName()
        var arguments: [XtendTypeReference] = []
        if current.isSymbol("<") {
            advance()
            if !current.isSymbol(">") {
                repeat { arguments.append(try parseTypeReference()) } while accept(",")
            }
            try expect(">")
        }
        var dimensions = 0
        while current.isSymbol("["), peek(1).isSymbol("]") {
            advance()
            advance()
            dimensions += 1
        }
        return XtendTypeReference(name: name, arguments: arguments, arrayDimensions: dimensions, range: range(from: start))
    }

    /// Whether a type reference followed by a name starts at the current position.
    private mutating func startsTypedDeclaration() -> Bool {
        let saved = position
        let savedDiagnostics = diagnostics
        defer {
            position = saved
            diagnostics = savedDiagnostics
        }
        guard (try? parseTypeReference()) != nil else { return false }
        return current.kind == .identifier
    }

    // MARK: - Expressions

    /// Parses expressions up to the end of the text as a block.
    mutating func parseStandaloneExpression() -> XtendExpression? {
        let start = current.start
        var expressions: [XtendExpression] = []
        do {
            while !atEnd {
                if accept(";") { continue }
                expressions.append(try parseExpressionOrDeclaration())
            }
        } catch {
            return nil
        }
        if expressions.count == 1, case .variableDeclaration = expressions[0].kind {
        } else if expressions.count == 1 {
            return expressions[0]
        }
        return XtendExpression(.block(expressions), range: range(from: start))
    }

    /// Parses an expression.
    mutating func parseExpression() throws -> XtendExpression {
        try parseAssignment()
    }

    /// Parses a variable declaration or, failing that, an ordinary expression.
    ///
    /// - Returns: The declaration or expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseExpressionOrDeclaration() throws -> XtendExpression {
        guard current.isKeyword(.val) || current.isKeyword(.var) else { return try parseExpression() }
        let start = current.start
        let isMutable = advance().text == XtendLanguage.Keyword.var.rawValue
        let isExtension = accept(.extension)
        var type: XtendTypeReference?
        if startsTypedDeclaration() { type = try parseTypeReference() }
        let name = try expectIdentifier().text
        var initialiser: XtendExpression?
        if accept("=") { initialiser = try parseExpression() }
        return XtendExpression(
            .variableDeclaration(name: name, type: type, isMutable: isMutable, isExtension: isExtension, initialiser: initialiser),
            range: range(from: start))
    }

    /// Whether an expression can be the target of an assignment.
    ///
    /// - Parameter expression: The expression to check.
    /// - Returns: `true` if it is a plain variable or feature reference.
    private static func isAssignable(_ expression: XtendExpression) -> Bool {
        switch expression.kind {
        case .featureCall(_, let arguments, let explicitCall): return arguments.isEmpty && !explicitCall
        case .memberCall(_, _, let arguments, let explicitCall, _): return arguments.isEmpty && !explicitCall
        case .staticCall(_, _, let arguments, let explicitCall): return arguments.isEmpty && !explicitCall
        default: return false
        }
    }

    /// Parses an assignment, a compound assignment or the lower-precedence expression it wraps.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseAssignment() throws -> XtendExpression {
        let start = current.start
        let target = try parseOr()
        if current.isSymbol("=") {
            let operatorToken = advance()
            guard Self.isAssignable(target) else {
                report(.unexpectedToken, "The left-hand side of an assignment must be a variable or feature", range: range(of: operatorToken))
                throw XtendParseFailure()
            }
            let value = try parseAssignment()
            return XtendExpression(.assignment(target: target, value: value), range: range(from: start))
        }
        if current.kind == .symbol, ["+=", "-=", "*=", "/=", "%="].contains(current.text) {
            let operatorText = advance().text
            let value = try parseAssignment()
            return XtendExpression(
                .compoundAssignment(operator: operatorText, target: target, value: value), range: range(from: start))
        }
        return target
    }

    /// Parses a left-associative chain of binary operators.
    ///
    /// - Parameters:
    ///   - operators: The operator symbols handled at this precedence level.
    ///   - next: The parser for the next higher precedence level, which parses each operand.
    /// - Returns: The expression, nested to the left.
    /// - Throws: ``XtendParseFailure`` if an operand is malformed.
    private mutating func parseBinary(
        _ operators: Set<String>, next: (inout XtendParserState) throws -> XtendExpression
    ) throws -> XtendExpression {
        let start = current.start
        var left = try next(&self)
        while current.kind == .symbol, operators.contains(current.text) {
            let operatorText = advance().text
            let right = try next(&self)
            left = XtendExpression(.binary(operator: operatorText, left: left, right: right), range: range(from: start))
        }
        return left
    }

    /// Parses a logical `||` expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseOr() throws -> XtendExpression {
        try parseBinary(["||"]) { try $0.parseAnd() }
    }

    /// Parses a logical `&&` expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseAnd() throws -> XtendExpression {
        try parseBinary(["&&"]) { try $0.parseEquality() }
    }

    /// Parses an equality expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseEquality() throws -> XtendExpression {
        try parseBinary(["==", "!=", "===", "!=="]) { try $0.parseRelational() }
    }

    /// Parses a relational or `instanceof` expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseRelational() throws -> XtendExpression {
        let start = current.start
        var left = try parseOther()
        while true {
            if accept(.instanceof) {
                let type = try parseTypeReference()
                left = XtendExpression(.instanceOf(left, type), range: range(from: start))
            } else if current.kind == .symbol, ["<", "<=", ">", ">="].contains(current.text) {
                let operatorText = advance().text
                let right = try parseOther()
                left = XtendExpression(.binary(operator: operatorText, left: left, right: right), range: range(from: start))
            } else {
                return left
            }
        }
    }

    /// Parses a range, pair, elvis or other infix operator expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseOther() throws -> XtendExpression {
        let start = current.start
        var left = try parseAdditive()
        while true {
            var operatorText: String?
            if current.isSymbol(">"), peek(1).isSymbol(".."), peek(1).start == current.end {
                advance()
                advance()
                operatorText = ">.."
            } else if current.kind == .symbol, ["->", "..<", "..", "=>", "?:"].contains(current.text) {
                operatorText = advance().text
            }
            guard let operatorText else { return left }
            let right = try parseAdditive()
            left = XtendExpression(.binary(operator: operatorText, left: left, right: right), range: range(from: start))
        }
    }

    /// Parses an additive expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseAdditive() throws -> XtendExpression {
        try parseBinary(["+", "-"]) { try $0.parseMultiplicative() }
    }

    /// Parses a multiplicative expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseMultiplicative() throws -> XtendExpression {
        try parseBinary(["*", "**", "/", "%"]) { try $0.parseUnary() }
    }

    /// Parses a prefix unary expression.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseUnary() throws -> XtendExpression {
        let start = current.start
        if current.kind == .symbol, ["!", "-", "+"].contains(current.text) {
            let operatorText = advance().text
            let operand = try parseUnary()
            return XtendExpression(.unary(operator: operatorText, operand: operand), range: range(from: start))
        }
        return try parseCast()
    }

    /// Parses an expression followed by any `as` casts.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseCast() throws -> XtendExpression {
        let start = current.start
        var expression = try parsePostfix()
        while accept(.as) {
            let type = try parseTypeReference()
            expression = XtendExpression(.cast(expression, type), range: range(from: start))
        }
        return expression
    }

    /// Parses an expression with an optional postfix increment or decrement.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parsePostfix() throws -> XtendExpression {
        let start = current.start
        let expression = try parseMemberCalls()
        if current.isSymbol("++") || current.isSymbol("--") {
            let operatorText = advance().text
            return XtendExpression(.postfix(operator: operatorText, operand: expression), range: range(from: start))
        }
        return expression
    }

    /// The qualified type name that a chain of plain names spells, if it is one.
    private static func typeName(of expression: XtendExpression) -> String? {
        switch expression.kind {
        case .featureCall(let name, let arguments, let explicitCall) where arguments.isEmpty && !explicitCall:
            return name
        case .memberCall(let receiver, let name, let arguments, let explicitCall, false)
        where arguments.isEmpty && !explicitCall:
            return typeName(of: receiver).map { "\($0).\(name)" }
        default: return nil
        }
    }

    /// Parses a primary expression followed by any member and static feature calls.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if it is malformed.
    private mutating func parseMemberCalls() throws -> XtendExpression {
        let start = current.start
        var expression = try parsePrimary()
        while true {
            if current.isSymbol(".") || current.isSymbol("?.") {
                let nullSafe = advance().text == "?."
                let nameToken = current
                guard current.kind == .identifier || current.kind == .keyword else { throw unexpected("a member name") }
                advance()
                let (arguments, explicitCall) = try parseCallArguments()
                expression = XtendExpression(
                    .memberCall(
                        receiver: expression, name: nameToken.text, arguments: arguments, explicitCall: explicitCall,
                        nullSafe: nullSafe), range: range(from: start))
            } else if current.isSymbol("::") {
                let operatorToken = advance()
                guard let typeName = Self.typeName(of: expression) else {
                    report(.unexpectedToken, "'::' must follow a type name", range: range(of: operatorToken))
                    throw XtendParseFailure()
                }
                let nameToken = try expectIdentifier()
                let (arguments, explicitCall) = try parseCallArguments()
                let type = XtendTypeReference(name: typeName, range: expression.range)
                expression = XtendExpression(
                    .staticCall(type: type, name: nameToken.text, arguments: arguments, explicitCall: explicitCall),
                    range: range(from: start))
            } else {
                return expression
            }
        }
    }

    /// Parses the arguments of a call: optional parenthesised arguments and an optional trailing lambda.
    private mutating func parseCallArguments() throws -> ([XtendExpression], Bool) {
        var arguments: [XtendExpression] = []
        var explicitCall = false
        if current.isSymbol("(") {
            advance()
            explicitCall = true
            if !current.isSymbol(")") {
                repeat { arguments.append(try parseExpression()) } while accept(",")
            }
            try expect(")")
        }
        if current.isSymbol("[") {
            arguments.append(try parseLambda())
            explicitCall = true
        }
        return (arguments, explicitCall)
    }

    /// Parses a literal, a feature call, a parenthesised expression, a lambda, a block or a collection literal.
    ///
    /// - Returns: The expression.
    /// - Throws: ``XtendParseFailure`` if no expression starts at the current position.
    private mutating func parsePrimary() throws -> XtendExpression {
        let start = current.start
        let token = current
        switch token.kind {
        case .integer:
            advance()
            guard let value = Self.integerValue(token.text) else {
                report(.invalidNumber, "Invalid number '\(token.text)'", range: range(of: token))
                return XtendExpression(.integerLiteral(0), range: range(of: token))
            }
            return XtendExpression(.integerLiteral(value), range: range(of: token))
        case .double:
            advance()
            let digits = token.text.filter { $0 != "_" && !"dDfF".contains($0) }
            guard let value = Double(digits) else {
                report(.invalidNumber, "Invalid number '\(token.text)'", range: range(of: token))
                return XtendExpression(.doubleLiteral(0), range: range(of: token))
            }
            return XtendExpression(.doubleLiteral(value), range: range(of: token))
        case .string:
            advance()
            return XtendExpression(.stringLiteral(token.text), range: range(of: token))
        case .richStart:
            return try parseRichString()
        case .identifier:
            advance()
            let (arguments, explicitCall) = try parseCallArguments()
            return XtendExpression(
                .featureCall(name: token.text, arguments: arguments, explicitCall: explicitCall), range: range(from: start))
        case .keyword:
            return try parseKeywordExpression(token)
        case .symbol:
            switch token.text {
            case "(":
                advance()
                let inner = try parseExpression()
                try expect(")")
                return XtendExpression(inner.kind, range: range(from: start))
            case "[":
                return try parseLambda()
            case "{":
                return try parseBlock()
            case "#":
                advance()
                if accept("[") {
                    let elements = try parseElements(until: "]")
                    return XtendExpression(.listLiteral(elements), range: range(from: start))
                }
                try expect("{")
                let elements = try parseElements(until: "}")
                return XtendExpression(.setLiteral(elements), range: range(from: start))
            default:
                throw unexpected("an expression")
            }
        default:
            throw unexpected("an expression")
        }
    }

    /// Parses a comma-separated list of expressions and the closing symbol.
    ///
    /// - Parameter close: The symbol that ends the list, which is consumed.
    /// - Returns: The expressions.
    /// - Throws: ``XtendParseFailure`` if an element is malformed or the closing symbol is missing.
    private mutating func parseElements(until close: String) throws -> [XtendExpression] {
        var elements: [XtendExpression] = []
        if !current.isSymbol(close) {
            repeat { elements.append(try parseExpression()) } while accept(",")
        }
        try expect(close)
        return elements
    }

    /// Reads the value of a whole-number literal.
    static func integerValue(_ text: String) -> Int? {
        var digits = text.filter { $0 != "_" }
        if digits.hasSuffix("L") || digits.hasSuffix("l") { digits.removeLast() }
        if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
            return Int(digits.dropFirst(2), radix: 16)
        }
        return Int(digits)
    }

    /// Parses an expression that starts with a keyword.
    ///
    /// - Parameter token: The keyword token at the current position.
    /// - Returns: The expression; unsupported constructs yield an unsupported placeholder.
    /// - Throws: ``XtendParseFailure`` if the expression is malformed.
    private mutating func parseKeywordExpression(_ token: XtendToken) throws -> XtendExpression {
        let start = token.start
        switch XtendLanguage.Keyword(rawValue: token.text) {
        case .null:
            advance()
            return XtendExpression(.nullLiteral, range: range(of: token))
        case .true, .false:
            advance()
            return XtendExpression(.booleanLiteral(token.text == "true"), range: range(of: token))
        case .this, .super:
            advance()
            if current.isSymbol("(") {
                advance()
                let arguments = try parseElements(until: ")")
                return XtendExpression(
                    .featureCall(name: token.text, arguments: arguments, explicitCall: true), range: range(from: start))
            }
            return XtendExpression(token.text == "this" ? .this : .superReference, range: range(of: token))
        case .new:
            advance()
            let type = try parseTypeReference()
            var arguments: [XtendExpression] = []
            if accept("(") {
                arguments = try parseElements(until: ")")
            }
            return XtendExpression(.constructorCall(type: type, arguments: arguments), range: range(from: start))
        case .typeof:
            advance()
            try expect("(")
            let type = try parseTypeReference()
            try expect(")")
            return XtendExpression(.typeLiteral(type), range: range(from: start))
        case .if:
            advance()
            try expect("(")
            let condition = try parseExpression()
            try expect(")")
            let then = try parseExpressionOrDeclaration()
            var otherwise: XtendExpression?
            if accept(.else) { otherwise = try parseExpressionOrDeclaration() }
            return XtendExpression(.ifExpression(condition: condition, then: then, otherwise: otherwise), range: range(from: start))
        case .switch:
            return try parseSwitch()
        case .for:
            return try parseFor()
        case .while:
            advance()
            try expect("(")
            let condition = try parseExpression()
            try expect(")")
            let body = try parseExpressionOrDeclaration()
            return XtendExpression(.whileLoop(condition: condition, body: body), range: range(from: start))
        case .do:
            advance()
            let body = try parseExpressionOrDeclaration()
            try expect(.while)
            try expect("(")
            let condition = try parseExpression()
            try expect(")")
            return XtendExpression(.doWhileLoop(body: body, condition: condition), range: range(from: start))
        case .return:
            advance()
            var value: XtendExpression?
            if !(current.isSymbol("}") || current.isSymbol(";") || current.isSymbol(")") || current.isSymbol("]")
                || current.kind == .richClose || atEnd || current.isKeyword(.val) || current.isKeyword(.var)
                || current.isKeyword(.case) || current.isKeyword(.default))
            {
                value = try parseExpression()
            }
            return XtendExpression(.returnExpression(value), range: range(from: start))
        case .throw:
            advance()
            let value = try parseExpression()
            return XtendExpression(.throwExpression(value), range: range(from: start))
        case .try:
            advance()
            _ = try parseExpression()
            while accept(.catch) {
                try expect("(")
                _ = try parseTypeReference()
                while accept("|") { _ = try parseTypeReference() }
                _ = try expectIdentifier()
                try expect(")")
                _ = try parseExpression()
            }
            if accept(.finally) { _ = try parseExpression() }
            let extent = range(from: start)
            report(.unsupportedConstruct, "Exception handling with 'try' is not supported", range: extent)
            return XtendExpression(.unsupported("try"), range: extent)
        case .synchronized:
            advance()
            try expect("(")
            _ = try parseExpression()
            try expect(")")
            _ = try parseExpression()
            let extent = range(from: start)
            report(.unsupportedConstruct, "Synchronised blocks are not supported", range: extent)
            return XtendExpression(.unsupported("synchronized"), range: extent)
        default:
            throw unexpected("an expression")
        }
    }

    /// Parses a brace-delimited block of expressions.
    ///
    /// - Returns: The block expression.
    /// - Throws: ``XtendParseFailure`` if the block is malformed or unterminated.
    private mutating func parseBlock() throws -> XtendExpression {
        let start = current.start
        try expect("{")
        var expressions: [XtendExpression] = []
        while !current.isSymbol("}") {
            if atEnd { throw unexpected("'}'") }
            if accept(";") { continue }
            expressions.append(try parseExpressionOrDeclaration())
        }
        advance()
        return XtendExpression(.block(expressions), range: range(from: start))
    }

    /// Parses a lambda expression in square brackets, with optional explicit parameters.
    ///
    /// - Returns: The lambda expression.
    /// - Throws: ``XtendParseFailure`` if the lambda is malformed or unterminated.
    private mutating func parseLambda() throws -> XtendExpression {
        let start = current.start
        try expect("[")
        var parameters: [XtendParameter] = []
        var explicit = false
        if accept("|") {
            explicit = true
        } else {
            let saved = position
            let savedDiagnostics = diagnostics
            if let candidate = try? parseLambdaParameters(), accept("|") {
                parameters = candidate
                explicit = true
            } else {
                position = saved
                diagnostics = savedDiagnostics
            }
        }
        let bodyStart = current.start
        var expressions: [XtendExpression] = []
        while !current.isSymbol("]") {
            if atEnd { throw unexpected("']'") }
            if accept(";") { continue }
            expressions.append(try parseExpressionOrDeclaration())
        }
        advance()
        let body = XtendExpression(.block(expressions), range: range(from: bodyStart))
        return XtendExpression(.lambda(parameters: parameters, explicitParameters: explicit, body: body), range: range(from: start))
    }

    /// Parses the comma-separated parameters at the start of a lambda.
    ///
    /// - Returns: The parameters.
    /// - Throws: ``XtendParseFailure`` if a parameter is malformed.
    private mutating func parseLambdaParameters() throws -> [XtendParameter] {
        var parameters: [XtendParameter] = []
        repeat {
            let start = current.start
            var type: XtendTypeReference?
            if startsTypedDeclaration() { type = try parseTypeReference() }
            let name = try expectIdentifier()
            parameters.append(XtendParameter(name: name.text, type: type, range: range(from: start)))
        } while accept(",")
        return parameters
    }

    /// Parses a `switch` expression with its cases and default branch.
    ///
    /// - Returns: The switch expression.
    /// - Throws: ``XtendParseFailure`` if the switch is malformed.
    private mutating func parseSwitch() throws -> XtendExpression {
        let start = advance().start
        var declaredName: String?
        var parenthesised = false
        if current.isSymbol("("), peek(1).kind == .identifier, peek(2).isSymbol(":") {
            advance()
            parenthesised = true
        }
        if current.kind == .identifier, peek(1).isSymbol(":") {
            declaredName = advance().text
            advance()
        }
        let subject = try parseExpression()
        if parenthesised { try expect(")") }
        try expect("{")
        var cases: [XtendSwitchCase] = []
        var defaultBranch: XtendExpression?
        while !current.isSymbol("}") {
            if atEnd { throw unexpected("'}'") }
            let caseStart = current.start
            if accept(.default) {
                try expect(":")
                defaultBranch = try parseExpressionOrDeclaration()
                _ = accept(";")
                continue
            }
            var typeGuard: XtendTypeReference?
            if !current.isKeyword(.case) { typeGuard = try parseTypeReference() }
            var condition: XtendExpression?
            if accept(.case) { condition = try parseExpression() }
            var body: XtendExpression?
            if accept(":") {
                body = try parseExpressionOrDeclaration()
            } else if !accept(",") {
                throw unexpected("':' or ','")
            }
            _ = accept(";")
            cases.append(XtendSwitchCase(typeGuard: typeGuard, condition: condition, body: body, range: range(from: caseStart)))
        }
        advance()
        let switchExpression = XtendSwitch(
            declaredName: declaredName, subject: subject, cases: cases, defaultBranch: defaultBranch)
        return XtendExpression(.switchExpression(switchExpression), range: range(from: start))
    }

    /// Parses a `for` loop, either enhanced (iterating over a collection) or basic.
    ///
    /// - Returns: The loop expression.
    /// - Throws: ``XtendParseFailure`` if the loop is malformed.
    private mutating func parseFor() throws -> XtendExpression {
        let start = advance().start
        try expect("(")
        if !(current.isKeyword(.val) || current.isKeyword(.var)) {
            let saved = position
            let savedDiagnostics = diagnostics
            let parameterStart = current.start
            var type: XtendTypeReference?
            if startsTypedDeclaration() { type = try? parseTypeReference() }
            if current.kind == .identifier, peek(1).isSymbol(":") {
                let name = advance().text
                advance()
                let parameter = XtendParameter(name: name, type: type, range: range(from: parameterStart))
                let iterable = try parseExpression()
                try expect(")")
                let body = try parseExpressionOrDeclaration()
                return XtendExpression(.forEach(parameter: parameter, iterable: iterable, body: body), range: range(from: start))
            }
            position = saved
            diagnostics = savedDiagnostics
        }
        var initialisers: [XtendExpression] = []
        if !current.isSymbol(";") {
            repeat { initialisers.append(try parseExpressionOrDeclaration()) } while accept(",")
        }
        try expect(";")
        var condition: XtendExpression?
        if !current.isSymbol(";") { condition = try parseExpression() }
        try expect(";")
        var updates: [XtendExpression] = []
        if !current.isSymbol(")") {
            repeat { updates.append(try parseExpression()) } while accept(",")
        }
        try expect(")")
        let body = try parseExpressionOrDeclaration()
        return XtendExpression(
            .basicFor(initialisers: initialisers, condition: condition, updates: updates, body: body), range: range(from: start))
    }

    // MARK: - Rich strings

    /// Parses a rich string template into its parts and compiles them.
    ///
    /// - Returns: The rich string expression.
    /// - Throws: ``XtendParseFailure`` if the template is malformed.
    private mutating func parseRichString() throws -> XtendExpression {
        let start = current.start
        guard current.kind == .richStart else { throw unexpected("a rich string") }
        advance()
        var parts: [XtendTemplatePart] = []
        while current.kind != .richEnd {
            if atEnd {
                return finishRichString(parts, start: start)
            }
            if current.kind == .richText {
                parts.append(.text(advance().text))
                continue
            }
            if current.kind == .richComment {
                advance()
                parts.append(.comment)
                continue
            }
            guard current.kind == .richOpen else { throw unexpected("rich string text") }
            advance()
            let controlStart = current.start
            let keyword = current.kind == .identifier ? XtendLanguage.TemplateKeyword(rawValue: current.text) : nil
            switch keyword {
            case .FOR:
                advance()
                let parameterStart = current.start
                var type: XtendTypeReference?
                if !(current.kind == .identifier && peek(1).isSymbol(":")) { type = try parseTypeReference() }
                let name = try expectIdentifier().text
                let parameter = XtendParameter(name: name, type: type, range: range(from: parameterStart))
                try expect(":")
                let iterable = try parseExpression()
                var before: XtendExpression?
                var separator: XtendExpression?
                var after: XtendExpression?
                while current.kind == .identifier, let clause = XtendLanguage.TemplateKeyword(rawValue: current.text) {
                    switch clause {
                    case .BEFORE:
                        advance()
                        before = try parseExpression()
                    case .SEPARATOR:
                        advance()
                        separator = try parseExpression()
                    case .AFTER:
                        advance()
                        after = try parseExpression()
                    default: throw unexpected("BEFORE, SEPARATOR, AFTER or '»'")
                    }
                }
                let extent = range(from: controlStart)
                try expectGuillemet()
                parts.append(
                    .forStart(
                        parameter: parameter, iterable: iterable, before: before, separator: separator, after: after,
                        range: extent))
            case .ENDFOR:
                advance()
                let extent = range(from: controlStart)
                try expectGuillemet()
                parts.append(.endFor(extent))
            case .IF, .ELSEIF:
                advance()
                let condition = try parseExpression()
                let extent = range(from: controlStart)
                try expectGuillemet()
                parts.append(keyword == .IF ? .ifStart(condition, extent) : .elseIf(condition, extent))
            case .ELSE:
                advance()
                let extent = range(from: controlStart)
                try expectGuillemet()
                parts.append(.elseBranch(extent))
            case .ENDIF:
                advance()
                let extent = range(from: controlStart)
                try expectGuillemet()
                parts.append(.endIf(extent))
            default:
                if current.kind == .richClose {
                    advance()
                    continue
                }
                let expression = try parseExpression()
                try expectGuillemet()
                parts.append(.expression(expression))
            }
        }
        advance()
        return finishRichString(parts, start: start)
    }

    /// Consumes the closing guillemet of a template control or expression.
    ///
    /// - Throws: ``XtendParseFailure`` after reporting a diagnostic if the closing guillemet is missing.
    private mutating func expectGuillemet() throws {
        guard current.kind == .richClose else { throw unexpected("'»'") }
        advance()
    }

    /// Compiles the parts of a rich string and records any problems found.
    ///
    /// - Parameters:
    ///   - parts: The parsed template parts.
    ///   - start: The offset where the rich string starts.
    /// - Returns: The rich string expression.
    private mutating func finishRichString(_ parts: [XtendTemplatePart], start: Int) -> XtendExpression {
        let extent = range(from: start)
        let (template, problems) = XtendTemplateCompiler.compile(parts, range: extent, document: document)
        diagnostics.append(contentsOf: problems)
        return XtendExpression(.richString(template), range: extent)
    }
}

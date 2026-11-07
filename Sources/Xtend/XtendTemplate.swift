//
//  XtendTemplate.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A rich string compiled into the instructions that build its text.
///
/// Rich strings (template expressions) are compiled when they are parsed. The compilation
/// applies Xtend's whitespace rules, so the instructions already know which whitespace
/// belongs to the template and which belongs to the output:
///
/// 1. Indentation relative to a control structure (a `FOR`, an `IF` or the opening and
///    closing delimiters) is not copied to the output.
/// 2. Lines that hold only control structures and whitespace produce no output, and lines
///    whose interpolations evaluate to nothing but whitespace are dropped.
/// 3. Line breaks inside interpolated values receive the indentation of the line that
///    holds the interpolation.
public struct XtendTemplate: Sendable {
    /// The instructions in order.
    public var instructions: [XtendTemplateInstruction]

    /// Creates a template from instructions.
    ///
    /// - Parameter instructions: The instructions in order.
    public init(instructions: [XtendTemplateInstruction]) {
        self.instructions = instructions
    }
}

/// One step in building the text of a rich string.
public indirect enum XtendTemplateInstruction: Sendable {
    /// Appends static text that contains no line break.
    case literal(String)
    /// Appends a line break.
    case newLine
    /// Appends a line break unless the current line holds only whitespace, which is removed.
    case newLineIfNotEmpty
    /// Appends the value of an expression, indenting its line breaks.
    case expression(XtendExpression, indentation: String)
    /// Repeats instructions for each element of a collection.
    case loop(XtendTemplateLoop)
    /// Chooses instructions by conditions.
    case conditional(XtendTemplateConditional)
}

/// A `FOR` loop inside a rich string.
public struct XtendTemplateLoop: Sendable {
    /// The loop variable.
    public var parameter: XtendParameter

    /// The collection to iterate over.
    public var iterable: XtendExpression

    /// The text written before the first iteration, if any iteration happens.
    public var before: XtendExpression?

    /// The text written between iterations, directly after the last non-whitespace text.
    public var separator: XtendExpression?

    /// The text written after the last iteration, if any iteration happened.
    public var after: XtendExpression?

    /// The instructions of one iteration.
    public var body: [XtendTemplateInstruction]

    /// The indentation of the line that holds the loop.
    public var indentation: String

    /// The extent of the `FOR` control structure.
    public var range: SourceRange

    /// Creates a loop.
    ///
    /// - Parameters:
    ///   - parameter: The loop variable.
    ///   - iterable: The collection to iterate over.
    ///   - before: The text written before the first iteration.
    ///   - separator: The text written between iterations.
    ///   - after: The text written after the last iteration.
    ///   - body: The instructions of one iteration.
    ///   - indentation: The indentation of the line that holds the loop.
    ///   - range: The extent of the control structure.
    public init(
        parameter: XtendParameter, iterable: XtendExpression, before: XtendExpression?,
        separator: XtendExpression?, after: XtendExpression?, body: [XtendTemplateInstruction],
        indentation: String, range: SourceRange
    ) {
        self.parameter = parameter
        self.iterable = iterable
        self.before = before
        self.separator = separator
        self.after = after
        self.body = body
        self.indentation = indentation
        self.range = range
    }
}

/// An `IF` conditional inside a rich string.
public struct XtendTemplateConditional: Sendable {
    /// The `IF` and `ELSEIF` branches in order.
    public var branches: [XtendTemplateBranch]

    /// The `ELSE` instructions, if any.
    public var otherwise: [XtendTemplateInstruction]?

    /// Creates a conditional.
    ///
    /// - Parameters:
    ///   - branches: The conditional branches in order.
    ///   - otherwise: The `ELSE` instructions, if any.
    public init(branches: [XtendTemplateBranch], otherwise: [XtendTemplateInstruction]?) {
        self.branches = branches
        self.otherwise = otherwise
    }
}

/// A branch of a conditional inside a rich string.
public struct XtendTemplateBranch: Sendable {
    /// The condition that selects the branch.
    public var condition: XtendExpression

    /// The instructions of the branch.
    public var body: [XtendTemplateInstruction]

    /// Creates a branch.
    ///
    /// - Parameters:
    ///   - condition: The condition that selects the branch.
    ///   - body: The instructions of the branch.
    public init(condition: XtendExpression, body: [XtendTemplateInstruction]) {
        self.condition = condition
        self.body = body
    }
}

/// A piece of a rich string as the parser reads it, before whitespace analysis.
enum XtendTemplatePart: Sendable {
    /// Static text, which may contain line breaks.
    case text(String)
    /// An interpolated expression.
    case expression(XtendExpression)
    /// The start of a loop.
    case forStart(
        parameter: XtendParameter, iterable: XtendExpression, before: XtendExpression?,
        separator: XtendExpression?, after: XtendExpression?, range: SourceRange)
    /// The end of a loop.
    case endFor(SourceRange)
    /// The start of a conditional.
    case ifStart(XtendExpression, SourceRange)
    /// An alternative condition.
    case elseIf(XtendExpression, SourceRange)
    /// The final alternative.
    case elseBranch(SourceRange)
    /// The end of a conditional.
    case endIf(SourceRange)
    /// A comment, which produces no output.
    case comment
}

/// Applies Xtend's whitespace rules to the parts of a rich string.
///
/// The compiler splits the template into lines, decides for each line which whitespace is
/// template indentation and which is output, drops lines that hold only control
/// structures, and nests the instructions of loops and conditionals.
struct XtendTemplateCompiler {
    /// A control structure, as it appears within a line.
    private enum Control {
        /// The start of a `FOR` loop.
        case forStart(XtendTemplateLoop)
        /// The end of a `FOR` loop.
        case endFor(SourceRange)
        /// The start of an `IF` conditional.
        case ifStart(XtendExpression, SourceRange)
        /// An `ELSEIF` branch.
        case elseIf(XtendExpression, SourceRange)
        /// An `ELSE` branch.
        case elseBranch(SourceRange)
        /// The end of an `IF` conditional.
        case endIf(SourceRange)
        /// A `«««` comment, which produces no output.
        case comment

        /// Whether the control structure ends or switches a block rather than opening one.
        var continuesEnclosingBlock: Bool {
            switch self {
            case .forStart, .ifStart, .comment: return false
            case .endFor, .elseIf, .elseBranch, .endIf: return true
            }
        }
    }

    /// An element of a line.
    private enum Element {
        /// Literal text.
        case text(String)
        /// An embedded expression.
        case expression(XtendExpression)
        /// A control structure.
        case control(Control)

        /// Whether the element is text made of whitespace only.
        var isWhitespaceText: Bool {
            if case .text(let text) = self { return XtendTemplateCompiler.isWhitespace(text) }
            return false
        }
    }

    /// A line of the template.
    private struct Line {
        /// The elements of the line in source order.
        var elements: [Element] = []
        /// Whether a line break ends the line.
        var hasLineBreak = false

        /// Whether the line holds nothing but whitespace text.
        var isBlank: Bool { elements.allSatisfy(\.isWhitespaceText) }

        /// Whether the line holds control structures and otherwise only whitespace.
        var isControlOnly: Bool {
            var sawControl = false
            for element in elements {
                switch element {
                case .control: sawControl = true
                case .expression: return false
                case .text(let text): if !XtendTemplateCompiler.isWhitespace(text) { return false }
                }
            }
            return sawControl
        }
    }

    /// The kind of block that a frame collects instructions for.
    private enum FrameKind {
        /// The outermost block of the template.
        case root
        /// The body of a `FOR` loop.
        case loop(XtendTemplateLoop)
        /// The branches of an `IF` conditional.
        case conditional(branches: [XtendTemplateBranch], condition: XtendExpression?, range: SourceRange)
    }

    /// A block under construction with its indentation context.
    private struct Frame {
        /// The kind of block that the frame collects.
        var kind: FrameKind
        /// The instructions collected so far.
        var instructions: [XtendTemplateInstruction] = []
        /// The indentation that belongs to the template, or `nil` until the first line decides it.
        var template: String?
        /// The indentation that the block's lines receive in the output.
        var semantic: String
    }

    /// The stack of open blocks, with the root block at the bottom.
    private var frames: [Frame] = []
    /// The diagnostics about unbalanced control structures.
    private var diagnostics: [SourceDiagnostic] = []
    /// The document that the template belongs to, for diagnostics.
    private let document: String?

    /// Creates a compiler.
    ///
    /// - Parameter document: The document that the template belongs to, for diagnostics.
    private init(document: String?) {
        self.document = document
    }

    /// Compiles the parts of a rich string.
    ///
    /// - Parameters:
    ///   - parts: The parts in source order.
    ///   - range: The extent of the rich string, for diagnostics about unclosed structures.
    ///   - document: The document that the template belongs to.
    /// - Returns: The template and any diagnostics about unbalanced control structures.
    static func compile(
        _ parts: [XtendTemplatePart], range: SourceRange, document: String?
    ) -> (XtendTemplate, [SourceDiagnostic]) {
        var compiler = XtendTemplateCompiler(document: document)
        let lines = Self.lines(of: parts)
        let skipsFirst = lines.count > 1 && lines[0].isBlank
        let skipsLast = lines.count > 1 && lines[lines.count - 1].isBlank
        compiler.frames = [Frame(kind: .root, template: skipsFirst ? nil : "", semantic: "")]
        if lines.count == 1, lines[0].isBlank {
            let text = lines[0].elements.compactMap { element -> String? in
                if case .text(let text) = element { return text }
                return nil
            }.joined()
            if !text.isEmpty { compiler.frames[0].instructions.append(.literal(text)) }
        } else {
            for (index, line) in lines.enumerated() {
                if index == 0 && skipsFirst { continue }
                if index == lines.count - 1 && skipsLast { continue }
                compiler.process(line)
            }
        }
        while compiler.frames.count > 1 {
            let frame = compiler.frames[compiler.frames.count - 1]
            switch frame.kind {
            case .loop(let loop):
                compiler.report("FOR without ENDFOR", range: loop.range)
                compiler.close()
            case .conditional(_, _, let conditionRange):
                compiler.report("IF without ENDIF", range: conditionRange)
                compiler.close()
            case .root:
                compiler.frames.removeLast()
            }
        }
        _ = range
        return (XtendTemplate(instructions: compiler.frames[0].instructions), compiler.diagnostics)
    }

    // MARK: - Lines

    /// Splits the parts into lines of elements.
    private static func lines(of parts: [XtendTemplatePart]) -> [Line] {
        var lines = [Line()]
        /// Appends an element to the current line, merging adjacent text.
        ///
        /// - Parameter element: The element to append.
        func append(_ element: Element) {
            if case .text(let text) = element, case .text(let previous)? = lines[lines.count - 1].elements.last {
                lines[lines.count - 1].elements[lines[lines.count - 1].elements.count - 1] = .text(previous + text)
            } else {
                lines[lines.count - 1].elements.append(element)
            }
        }
        for part in parts {
            switch part {
            case .text(let text):
                var current = ""
                var scalars = text.unicodeScalars.makeIterator()
                var pending = scalars.next()
                while let scalar = pending {
                    pending = scalars.next()
                    if scalar == "\n" || scalar == "\r" {
                        if scalar == "\r", pending == "\n" { pending = scalars.next() }
                        if !current.isEmpty { append(.text(current)) }
                        current = ""
                        lines[lines.count - 1].hasLineBreak = true
                        lines.append(Line())
                    } else {
                        current.unicodeScalars.append(scalar)
                    }
                }
                if !current.isEmpty { append(.text(current)) }
            case .expression(let expression):
                append(.expression(expression))
            case .forStart(let parameter, let iterable, let before, let separator, let after, let range):
                let loop = XtendTemplateLoop(
                    parameter: parameter, iterable: iterable, before: before, separator: separator, after: after,
                    body: [], indentation: "", range: range)
                append(.control(.forStart(loop)))
            case .endFor(let range): append(.control(.endFor(range)))
            case .ifStart(let condition, let range): append(.control(.ifStart(condition, range)))
            case .elseIf(let condition, let range): append(.control(.elseIf(condition, range)))
            case .elseBranch(let range): append(.control(.elseBranch(range)))
            case .endIf(let range): append(.control(.endIf(range)))
            case .comment: append(.control(.comment))
            }
        }
        return lines
    }

    /// Whether text holds whitespace other than line breaks only.
    static func isWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\u{0C}" }
    }

    /// Splits a line into its leading whitespace and the remaining elements.
    private static func splitLeadingWhitespace(_ elements: [Element]) -> (String, [Element]) {
        guard case .text(let text)? = elements.first else { return ("", elements) }
        let leading = String(text.unicodeScalars.prefix { $0 == " " || $0 == "\t" || $0 == "\u{0C}" })
        let remainder = String(text.unicodeScalars.dropFirst(leading.unicodeScalars.count))
        var rest = Array(elements.dropFirst())
        if !remainder.isEmpty { rest.insert(.text(remainder), at: 0) }
        return (leading, rest)
    }

    /// Removes the template indentation from the leading whitespace of a line.
    private static func strip(_ leading: String, template: String?) -> String {
        guard let template else { return "" }
        if leading.hasPrefix(template) { return String(leading.dropFirst(template.count)) }
        let common = zip(leading, template).prefix { $0 == $1 }.count
        return String(leading.dropFirst(common))
    }

    // MARK: - Processing

    /// Compiles one line into the current frames.
    private mutating func process(_ line: Line) {
        let (leading, rest) = Self.splitLeadingWhitespace(line.elements)
        if line.isBlank {
            if line.hasLineBreak { emit(.newLine) }
            return
        }
        if line.isControlOnly {
            let controlIndices = rest.indices.filter {
                if case .control = rest[$0] { return true }
                return false
            }
            for (position, index) in controlIndices.enumerated() {
                guard case .control(let control) = rest[index] else { continue }
                let atLineEnd = position == controlIndices.count - 1
                apply(control, leading: leading, lineIndentation: nil, atLineEnd: atLineEnd, isFirst: position == 0)
            }
            return
        }
        var index = 0
        var isDynamic = false
        while index < rest.count, case .control(let control) = rest[index], control.continuesEnclosingBlock {
            apply(control, leading: leading, lineIndentation: nil, atLineEnd: false, isFirst: index == 0)
            isDynamic = true
            index += 1
        }
        establishTemplate(leading)
        let indentation = indentation(of: leading, in: frames.count - 1)
        if !indentation.isEmpty { emit(.literal(indentation)) }
        var afterOpenerAtLineEnd = false
        while index < rest.count {
            let remainderIsWhitespace = rest[(index + 1)...].allSatisfy(\.isWhitespaceText)
            switch rest[index] {
            case .text(let text):
                if !(afterOpenerAtLineEnd && Self.isWhitespace(text)) { emit(.literal(text)) }
            case .expression(let expression):
                emit(.expression(expression, indentation: indentation))
                isDynamic = true
            case .control(let control):
                isDynamic = true
                apply(control, leading: leading, lineIndentation: indentation, atLineEnd: remainderIsWhitespace, isFirst: false)
                if case .comment = control { break }
                afterOpenerAtLineEnd = remainderIsWhitespace && !control.continuesEnclosingBlock
            }
            index += 1
        }
        if line.hasLineBreak { emit(isDynamic ? .newLineIfNotEmpty : .newLine) }
    }

    /// Decides the template indentation of the innermost block from its first line.
    private mutating func establishTemplate(_ leading: String) {
        if frames[frames.count - 1].template == nil { frames[frames.count - 1].template = leading }
    }

    /// The output indentation of a line relative to a frame.
    private func indentation(of leading: String, in frameIndex: Int) -> String {
        let frame = frames[frameIndex]
        return frame.semantic + Self.strip(leading, template: frame.template ?? leading)
    }

    /// Appends an instruction to the innermost block.
    private mutating func emit(_ instruction: XtendTemplateInstruction) {
        frames[frames.count - 1].instructions.append(instruction)
    }

    /// Applies a control structure.
    ///
    /// - Parameters:
    ///   - control: The control structure.
    ///   - leading: The leading whitespace of its line.
    ///   - lineIndentation: The output indentation of its line, or `nil` to compute it.
    ///   - atLineEnd: Whether only whitespace follows the control structure on its line.
    ///   - isFirst: Whether the control structure is the first element of its line.
    private mutating func apply(
        _ control: Control, leading: String, lineIndentation: String?, atLineEnd: Bool, isFirst: Bool
    ) {
        switch control {
        case .forStart(var loop):
            if isFirst { establishTemplate(leading) }
            let indentation = lineIndentation ?? self.indentation(of: leading, in: frames.count - 1)
            loop.indentation = indentation
            open(.loop(loop), indentation: indentation, atLineEnd: atLineEnd)
        case .ifStart(let condition, let range):
            if isFirst { establishTemplate(leading) }
            let indentation = lineIndentation ?? self.indentation(of: leading, in: frames.count - 1)
            open(.conditional(branches: [], condition: condition, range: range), indentation: indentation, atLineEnd: atLineEnd)
        case .elseIf(let condition, let range):
            switchBranch(to: condition, range: range, leading: leading, lineIndentation: lineIndentation, atLineEnd: atLineEnd)
        case .elseBranch(let range):
            switchBranch(to: nil, range: range, leading: leading, lineIndentation: lineIndentation, atLineEnd: atLineEnd)
        case .endFor(let range):
            guard case .loop = frames[frames.count - 1].kind else {
                report("ENDFOR without a matching FOR", range: range)
                return
            }
            close()
        case .comment:
            return
        case .endIf(let range):
            guard case .conditional = frames[frames.count - 1].kind else {
                report("ENDIF without a matching IF", range: range)
                return
            }
            close()
        }
    }

    /// Opens a block.
    private mutating func open(_ kind: FrameKind, indentation: String, atLineEnd: Bool) {
        let enclosing = frames[frames.count - 1]
        frames.append(
            Frame(
                kind: kind, template: atLineEnd ? nil : enclosing.template,
                semantic: atLineEnd ? indentation : enclosing.semantic))
    }

    /// Ends the current branch of a conditional and starts the next one.
    private mutating func switchBranch(
        to condition: XtendExpression?, range: SourceRange, leading: String, lineIndentation: String?, atLineEnd: Bool
    ) {
        let top = frames.count - 1
        guard top > 0, case .conditional(var branches, let current, let ifRange) = frames[top].kind else {
            report(condition == nil ? "ELSE without a matching IF" : "ELSEIF without a matching IF", range: range)
            return
        }
        guard let current else {
            report("ELSEIF or ELSE after ELSE", range: range)
            return
        }
        branches.append(XtendTemplateBranch(condition: current, body: frames[top].instructions))
        let indentation = lineIndentation ?? self.indentation(of: leading, in: top - 1)
        let enclosing = frames[top - 1]
        frames[top].kind = .conditional(branches: branches, condition: condition, range: ifRange)
        frames[top].instructions = []
        frames[top].template = atLineEnd ? nil : enclosing.template
        frames[top].semantic = atLineEnd ? indentation : enclosing.semantic
    }

    /// Closes the innermost block and appends its instruction to the enclosing block.
    private mutating func close() {
        let frame = frames.removeLast()
        switch frame.kind {
        case .root:
            frames.append(frame)
        case .loop(var loop):
            loop.body = frame.instructions
            emit(.loop(loop))
        case .conditional(var branches, let condition, _):
            if let condition {
                branches.append(XtendTemplateBranch(condition: condition, body: frame.instructions))
                emit(.conditional(XtendTemplateConditional(branches: branches, otherwise: nil)))
            } else {
                emit(.conditional(XtendTemplateConditional(branches: branches, otherwise: frame.instructions)))
            }
        }
    }

    /// Records an unbalanced control structure.
    private mutating func report(_ message: String, range: SourceRange) {
        diagnostics.append(.xtend(.unbalancedTemplate, message, range: range, document: document))
    }
}

/// Builds text the way Xtend's `StringConcatenation` does.
///
/// The text is kept as segments, where every line delimiter is a segment of its own. This
/// lets a line that holds only whitespace be removed, lets separators be placed directly
/// after the last non-whitespace text, and lets inserted text be indented line by line.
struct XtendStringConcatenation {
    /// The segments of the text; each line delimiter is a separate segment.
    private(set) var segments: [String] = []

    /// The line delimiter.
    let lineDelimiter = XtendLanguage.lineDelimiter

    /// Creates an empty concatenation.
    init() {}

    /// The text built so far.
    var text: String { segments.joined() }

    /// Appends text, turning its line breaks into delimiter segments.
    ///
    /// - Parameters:
    ///   - text: The text to append.
    ///   - indentation: The indentation inserted after each line break of the text.
    mutating func append(_ text: String, indentation: String = "") {
        insert(text, indentation: indentation, at: segments.count)
    }

    /// Appends text directly after the last segment that holds more than whitespace.
    ///
    /// - Parameters:
    ///   - text: The text to append.
    ///   - indentation: The indentation inserted after each line break of the text.
    mutating func appendImmediate(_ text: String, indentation: String = "") {
        var index = segments.count - 1
        while index >= 0 {
            if !segments[index].unicodeScalars.allSatisfy(Self.isJavaWhitespace) {
                insert(text, indentation: indentation, at: index + 1)
                return
            }
            index -= 1
        }
        insert(text, indentation: indentation, at: 0)
    }

    /// Appends a line delimiter.
    mutating func newLine() {
        segments.append(lineDelimiter)
    }

    /// Appends a line delimiter if the current line holds more than whitespace.
    ///
    /// If the current line holds only whitespace, that whitespace is removed instead.
    mutating func newLineIfNotEmpty() {
        var index = segments.count - 1
        while index >= 0 {
            let segment = segments[index]
            if segment == lineDelimiter {
                segments.removeSubrange((index + 1)...)
                return
            }
            if !segment.unicodeScalars.allSatisfy(Self.isJavaWhitespace) {
                newLine()
                return
            }
            index -= 1
        }
        segments.removeAll()
    }

    /// Inserts text at a segment index.
    private mutating func insert(_ text: String, indentation: String, at index: Int) {
        var pieces: [String] = []
        var current = ""
        var scalars = text.unicodeScalars.makeIterator()
        var pending = scalars.next()
        while let scalar = pending {
            pending = scalars.next()
            if scalar == "\n" || scalar == "\r" {
                if scalar == "\r", pending == "\n" { pending = scalars.next() }
                if !current.isEmpty { pieces.append(current) }
                current = ""
                pieces.append(lineDelimiter)
                if !indentation.isEmpty { pieces.append(indentation) }
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        segments.insert(contentsOf: pieces, at: index)
    }

    /// Whether a scalar is whitespace in the sense of Java's `Character.isWhitespace`.
    private static func isJavaWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{1C}", "\u{1D}", "\u{1E}", "\u{1F}": return true
        default: return false
        }
    }
}

//
//  XtendFileSystemAccess.swift
//  Xtend
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
public import Foundation

/// Receives the files that a generator writes.
///
/// This is the interpreter's counterpart of Xtext's `IFileSystemAccess`. A generator calls
/// `fsa.generateFile(name, contents)` or `fsa.generateFile(name, outputConfiguration,
/// contents)`; the interpreter validates the path and forwards the call to this protocol.
public protocol XtendFileSystemAccess: Sendable {
    /// Writes a generated file.
    ///
    /// - Parameters:
    ///   - path: The relative path of the file, with `/` separators; it has been validated
    ///     with ``XtendFilePath/components(of:)``.
    ///   - outputConfiguration: The name of the output configuration, by default
    ///     ``XtendLanguage/defaultOutputConfiguration``.
    ///   - contents: The text of the file.
    /// - Throws: An error if the file cannot be written.
    func generateFile(_ path: String, outputConfiguration: String, contents: String) async throws
}

/// The validation of generated file paths.
///
/// Generated paths must stay inside the output location: absolute paths, empty paths and
/// paths whose `..` segments leave the output location are rejected.
public enum XtendFilePath {
    /// Splits a generated file path into its segments after validating it.
    ///
    /// - Parameter path: The path as the generator gave it.
    /// - Returns: The normalised segments, without `.` and resolved `..` segments.
    /// - Throws: ``XtendError`` with ``XtendDiagnosticCode/fileAccess`` if the path is
    ///   empty, absolute, or leaves the output location.
    public static func components(of path: String) throws -> [String] {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains("\0"),
            !(path.count >= 2 && path.dropFirst().first == ":")
        else {
            throw XtendError(.fileAccess, "The generated file path '\(path)' must be a non-empty relative path")
        }
        var segments: [String] = []
        for segment in path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init) {
            switch segment {
            case ".": continue
            case "..":
                guard !segments.isEmpty else {
                    throw XtendError(.fileAccess, "The generated file path '\(path)' leaves the output location")
                }
                segments.removeLast()
            default: segments.append(segment)
            }
        }
        guard !segments.isEmpty else {
            throw XtendError(.fileAccess, "The generated file path '\(path)' does not name a file")
        }
        return segments
    }
}

/// A file written by a generator.
public struct XtendGeneratedFile: Sendable, Hashable {
    /// The normalised relative path.
    public var path: String
    /// The output configuration the file was written to.
    public var outputConfiguration: String
    /// The text of the file.
    public var contents: String

    /// Creates a generated file.
    ///
    /// - Parameters:
    ///   - path: The normalised relative path.
    ///   - outputConfiguration: The output configuration.
    ///   - contents: The text of the file.
    public init(path: String, outputConfiguration: String, contents: String) {
        self.path = path
        self.outputConfiguration = outputConfiguration
        self.contents = contents
    }
}

/// A file system access that keeps generated files in memory.
///
/// Writing the same path of the same output configuration again replaces the earlier
/// contents, as writing a file on disk would.
public actor XtendInMemoryFileSystemAccess: XtendFileSystemAccess {
    /// The generated files in the order they were first written.
    public private(set) var files: [XtendGeneratedFile] = []

    /// Creates an empty file system access.
    public init() {}

    /// Records a generated file.
    ///
    /// - Parameters:
    ///   - path: The relative path of the file.
    ///   - outputConfiguration: The name of the output configuration.
    ///   - contents: The text of the file.
    /// - Throws: ``XtendError`` if the path is invalid.
    public func generateFile(_ path: String, outputConfiguration: String, contents: String) async throws {
        let normalised = try XtendFilePath.components(of: path).joined(separator: "/")
        let file = XtendGeneratedFile(path: normalised, outputConfiguration: outputConfiguration, contents: contents)
        if let index = files.firstIndex(where: { $0.path == normalised && $0.outputConfiguration == outputConfiguration }) {
            files[index] = file
        } else {
            files.append(file)
        }
    }

    /// The contents of a generated file.
    ///
    /// - Parameters:
    ///   - path: The relative path of the file.
    ///   - outputConfiguration: The output configuration (default
    ///     ``XtendLanguage/defaultOutputConfiguration``).
    /// - Returns: The contents, or `nil` if no such file was generated.
    public func contents(of path: String, outputConfiguration: String = XtendLanguage.defaultOutputConfiguration) -> String? {
        files.first { $0.path == path && $0.outputConfiguration == outputConfiguration }?.contents
    }

    /// The generated files of the default output configuration by path.
    public var generatedFiles: [String: String] {
        Dictionary(
            files.filter { $0.outputConfiguration == XtendLanguage.defaultOutputConfiguration }.map { ($0.path, $0.contents) },
            uniquingKeysWith: { _, last in last })
    }
}

/// A file system access that writes generated files below output directories.
///
/// The default output configuration writes to ``outputDirectory``; further output
/// configurations can be mapped to their own directories. Missing directories are created.
public struct XtendDirectoryFileSystemAccess: XtendFileSystemAccess {
    /// The directory of the default output configuration.
    public let outputDirectory: URL

    /// The directories of further output configurations by name.
    public let outputConfigurations: [String: URL]

    /// The character encoding of the files written (UTF-8 unless another is given).
    public let encoding: TextEncoding

    /// Creates a file system access that writes UTF-8.
    ///
    /// - Parameters:
    ///   - outputDirectory: The directory of the default output configuration.
    ///   - outputConfigurations: The directories of further output configurations.
    public init(outputDirectory: URL, outputConfigurations: [String: URL] = [:]) {
        self.outputDirectory = outputDirectory
        self.outputConfigurations = outputConfigurations
        self.encoding = .utf8
    }

    /// Creates a file system access that writes files in a character encoding.
    ///
    /// A character that the encoding cannot hold makes ``generateFile(_:outputConfiguration:contents:)``
    /// throw an error that names the file, the line and the column; the file is then not written.
    ///
    /// - Parameters:
    ///   - outputDirectory: The directory of the default output configuration.
    ///   - outputConfigurations: The directories of further output configurations.
    ///   - encoding: The character encoding of the files.
    public init(outputDirectory: URL, outputConfigurations: [String: URL], encoding: TextEncoding) {
        self.outputDirectory = outputDirectory
        self.outputConfigurations = outputConfigurations
        self.encoding = encoding
    }

    /// Writes a generated file below the directory of its output configuration.
    ///
    /// - Parameters:
    ///   - path: The relative path of the file.
    ///   - outputConfiguration: The name of the output configuration.
    ///   - contents: The text of the file, written in ``encoding`` (UTF-8 by default).
    /// - Throws: ``XtendError`` if the path is invalid, the configuration is unknown, or the
    ///   encoding cannot hold a character of the text (in which case no file is written), or
    ///   the error of the file system.
    public func generateFile(_ path: String, outputConfiguration: String, contents: String) async throws {
        let segments = try XtendFilePath.components(of: path)
        let base: URL
        if outputConfiguration == XtendLanguage.defaultOutputConfiguration {
            base = outputDirectory
        } else if let configured = outputConfigurations[outputConfiguration] {
            base = configured
        } else {
            throw XtendError(.fileAccess, "Unknown output configuration '\(outputConfiguration)'")
        }
        var url = base
        for segment in segments { url.appendPathComponent(segment) }
        let data: Data
        do {
            data = try encoding.encode(contents)
        } catch {
            throw XtendError(.fileAccess, "Cannot write \(url.path): \(error)")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

//
//  FileSystemTests.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import Xtend

/// Tests of generated file paths and file system access.
@Suite("File system access")
struct FileSystemTests {
    /// Paths are normalised and must stay inside the output location.
    @Test("Path validation")
    func pathValidation() throws {
        #expect(try XtendFilePath.components(of: "a/./b/../c.txt") == ["a", "c.txt"])
        #expect(try XtendFilePath.components(of: "dir\\file.txt") == ["dir", "file.txt"])
        for invalid in ["", "/etc/passwd", "../outside.txt", "a/../../b", "C:/x", ".", "a\0b"] {
            #expect(throws: XtendError.self) { _ = try XtendFilePath.components(of: invalid) }
        }
    }

    /// Writing the same file again replaces its contents.
    @Test("In-memory file system access")
    func inMemory() async throws {
        let files = XtendInMemoryFileSystemAccess()
        try await files.generateFile("a.txt", outputConfiguration: XtendLanguage.defaultOutputConfiguration, contents: "1")
        try await files.generateFile("./a.txt", outputConfiguration: XtendLanguage.defaultOutputConfiguration, contents: "2")
        try await files.generateFile("a.txt", outputConfiguration: "other", contents: "3")
        #expect(await files.files.count == 2)
        #expect(await files.generatedFiles == ["a.txt": "2"])
        #expect(await files.contents(of: "a.txt", outputConfiguration: "other") == "3")
        await #expect(throws: XtendError.self) {
            try await files.generateFile("../x", outputConfiguration: XtendLanguage.defaultOutputConfiguration, contents: "")
        }
    }

    /// A generator writes files below the output directories and cannot escape them.
    @Test("Directory file system access")
    func directory() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("xtend-fsa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let docs = base.appendingPathComponent("docs")
        let files = XtendDirectoryFileSystemAccess(outputDirectory: base.appendingPathComponent("out"), outputConfigurations: ["docs": docs])
        let source = """
            import org.eclipse.emf.ecore.resource.Resource
            import org.eclipse.xtext.generator.IFileSystemAccess
            class G {
              def generate(Resource r, IFileSystemAccess fsa) {
                fsa.generateFile('nested/dir/File.txt', '''
                  hello «r.URI»
                ''')
                fsa.generateFile('readme.md', 'docs', 'documentation')
              }
            }
            """
        let interpreter = try XtendInterpreter(program: try XtendTestSupport.program(["G.xtend": source]))
        try await interpreter.generate(resource: interpreter.targetResource, fileSystem: files)
        let written = try String(contentsOf: base.appendingPathComponent("out/nested/dir/File.txt"), encoding: .utf8)
        #expect(written == "hello \(XtendInterpreter.defaultTargetURI)\n")
        #expect(try String(contentsOf: docs.appendingPathComponent("readme.md"), encoding: .utf8) == "documentation")
        await #expect(throws: XtendError.self) {
            try await files.generateFile("x.txt", outputConfiguration: "unknown", contents: "")
        }
        let escaping = """
            import org.eclipse.emf.ecore.resource.Resource
            import org.eclipse.xtext.generator.IFileSystemAccess
            class G { def generate(Resource r, IFileSystemAccess fsa) { fsa.generateFile('../escape.txt', 'x') } }
            """
        let escaper = try XtendInterpreter(program: try XtendTestSupport.program(["G.xtend": escaping]))
        await #expect {
            try await escaper.generate(resource: escaper.targetResource, fileSystem: files)
        } throws: { error in
            (error as? XtendError)?.code == .fileAccess && (error as? XtendError)?.diagnostics.first?.range?.start.line == 3
        }
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("escape.txt").path))
    }

    /// A program without a generator method cannot generate.
    @Test("Missing generator")
    func missingGenerator() async throws {
        let interpreter = try XtendInterpreter(program: try XtendTestSupport.program(["G.xtend": "class G {}"]))
        await #expect(throws: XtendError.self) {
            try await interpreter.generate(resource: interpreter.targetResource, fileSystem: XtendInMemoryFileSystemAccess())
        }
    }
}

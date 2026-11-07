# Getting Started with Xtend

Add Xtend to your project, run a generator over a model and handle diagnostics.

## Overview

This guide shows how to add the package, build an ``XtendProgram`` from Xtend sources and
metamodels, run a generator into a file system access, call methods and build models from
models.

## Adding Xtend to Your Project

Add swift-xtend as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-xtend.git", branch: "main"),
]
```

Then add the product dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Xtend", package: "swift-xtend"),
    ]
)
```

## Loading Metamodels and Models

Models are held by `Resource`s of swift-ecore. Load the metamodel and the model into one
`ResourceSet`, so that the model can resolve the types of its metamodel:

```swift
import ECore
import Foundation
import Xtend

let resourceSet = ResourceSet()
let metamodel = try await ModelIO.load(
    url: URL(fileURLWithPath: "entities.ecore"), resourceSet: resourceSet)
let model = try await ModelIO.load(
    url: URL(fileURLWithPath: "shop.xmi"), resourceSet: resourceSet)
guard let package = metamodel.packages.first else { return }
```

## Building a Program

An ``XtendProgram`` parses and validates its sources. Pass a single source text, or several
documents as ``XtendSource`` values, together with the metamodels the sources refer to:

```swift
let generator = """
    import entities.Entity
    import entities.Model
    import org.eclipse.emf.ecore.resource.Resource
    import org.eclipse.xtext.generator.IFileSystemAccess

    class SwiftGenerator {
        def generate(Resource resource, IFileSystemAccess fsa) {
            for (entity : resource.allContents.toIterable.filter(Entity)) {
                fsa.generateFile(entity.name + '.swift', entity.compile)
            }
        }

        def describe(Model m) { m.name }

        def compile(Entity e) '''
            public final class «e.name» {
            }
        '''
    }
    """

let program = XtendProgram(generator, metamodels: [package])

// Several documents
let helpers = "class Helpers { }"
let combined = XtendProgram(
    sources: [
        XtendSource(document: "Generator.xtend", text: generator),
        XtendSource(document: "Helpers.xtend", text: helpers),
    ],
    metamodels: [package])
```

Parsing never throws. Problems are collected in ``XtendProgram/diagnostics``, and
``XtendProgram/hasErrors`` tells whether the program can be run.

## Running a Generator

Create an ``XtendInterpreter`` with the resources the program can reach. Then run the
generator over the input resource. ``XtendInMemoryFileSystemAccess`` collects the generated
files in memory:

```swift
let interpreter = try XtendInterpreter(program: program, resources: [model.resource])
let files = XtendInMemoryFileSystemAccess()
try await interpreter.generate(resource: model.resource, fileSystem: files)

for (path, contents) in await files.generatedFiles {
    print("\(path): \(contents.count) characters")
}
```

To write the files to disk instead, use ``XtendDirectoryFileSystemAccess``. Further output
configurations of the generator map to their own directories:

```swift
let output = URL(fileURLWithPath: "generated")
let fileSystem = XtendDirectoryFileSystemAccess(
    outputDirectory: output,
    outputConfigurations: ["docs": output.appendingPathComponent("docs")])
try await interpreter.generate(resource: model.resource, fileSystem: fileSystem)
```

Generated paths must be relative and stay inside their output directory. Pass `className:`
to ``XtendInterpreter/generate(resource:fileSystem:className:)`` to choose a generator when
the program declares several. See <doc:Generators> for the conventions generators follow.

## Calling Methods and Evaluating Expressions

``XtendInterpreter/call(_:of:arguments:)`` creates an instance of a class and calls one of
its methods. Arguments and results are ``XtendHostValue``s, and model objects are passed as
``XtendHostValue/object(_:_:)``:

```swift
if let root = await model.resource.getRootObjects().first {
    let name = try await interpreter.call(
        "describe", of: "SwiftGenerator", arguments: [.object(root.id, model.resource)])
    print(name.stringValue ?? "")
}
```

``XtendInterpreter/evaluate(_:variables:)`` evaluates a standalone expression, and
``XtendInterpreter/standardOutput`` holds the text that `print` and `println` produced.

## Transforming Models

Objects created with `new` for classes of the registered metamodels are added to the
interpreter's ``XtendInterpreter/targetResource``. Pass your own resource to receive them,
and use it as the input of a second generator or save it with swift-ecore. Here,
`transformation` holds the Xtend source of a class `Entities2Tables`, and `entities` and
`relational` are the loaded metamodel packages:

```swift
let target = Resource(uri: "tables.xmi")
let interpreter = try XtendInterpreter(
    program: XtendProgram(transformation, metamodels: [entities, relational]),
    resources: [model.resource],
    targetResource: target)
guard let root = await model.resource.getRootObjects().first else { return }
_ = try await interpreter.call(
    "toSchema", of: "Entities2Tables", arguments: [.object(root.id, model.resource)])
```

<doc:Generators> shows a complete transformation using create and dispatch methods.

## Handling Diagnostics

``XtendInterpreter`` refuses to start with a program that has errors: its initialiser throws
an ``XtendError`` that carries the program's diagnostics. Evaluation failures are reported
the same way. Each diagnostic records its code, message and source position, and
``XtendError/code`` gives the first ``XtendDiagnosticCode``:

```swift
let program = XtendProgram(generator, metamodels: [package])
for diagnostic in program.errors {
    print(diagnostic.message)
}

do {
    let interpreter = try XtendInterpreter(program: program, resources: [model.resource])
    try await interpreter.generate(resource: model.resource, fileSystem: files)
} catch let error as XtendError {
    print(error)  // one line per diagnostic, with document and position
    if error.code == .unsupportedJavaType {
        // The program uses Java outside the documented subset
    }
}
```

Code outside the supported subset, including Java imports, types and members outside
``XtendJavaSubset``, is reported rather than ignored. <doc:SupportedSubset> lists what the
interpreter supports. <doc:RichStrings> describes the whitespace rules of templates.
``XtendOptions`` bounds the depth of calls and the number of evaluation steps.

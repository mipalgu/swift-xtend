# Swift Xtend - Xtend Interpreter Library

[![CI](https://github.com/mipalgu/swift-xtend/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-xtend/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-xtend/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-xtend/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-xtend%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-xtend)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-xtend%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-xtend)

A pure Swift interpreter for a documented subset of Eclipse Xtend, for running code
generators and model transformations over Ecore models without a Java virtual machine.

## Features

- **Pure Swift**: no Java or EMF runtime, with strict concurrency checking
- **Xtend language subset**: classes, dispatch, create and extension methods, and lambdas
- **Rich strings**: templates with Xtend's smart whitespace handling
- **Xbase library**: the commonly used collection and string extensions
- **[swift-ecore](https://github.com/mipalgu/swift-ecore) integration**: navigates and
  builds models held in ECore resources
- **Generators**: write files through in-memory or directory file system access
- **Diagnostics**: positioned reports for Java code outside the subset

## Requirements

- Swift 6.0 or later
- macOS 15.0 or later, Linux or Windows

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-xtend.git", branch: "main")
]
```

And add `"Xtend"` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Xtend", package: "swift-xtend"),
    ]
)
```

## Building

```bash
# Build the library
swift build

# Run tests
swift test
```

## Usage

Build a program from Xtend source and a metamodel, then run its generator over a model:

```swift
import ECore
import Xtend

let program = XtendProgram(generatorSource, metamodels: [package])
let interpreter = try XtendInterpreter(program: program, resources: [model])
let files = XtendInMemoryFileSystemAccess()
try await interpreter.generate(resource: model, fileSystem: files)
let generated = await files.generatedFiles
```

## Documentation

The [Xtend documentation](https://mipalgu.github.io/swift-xtend/documentation/xtend/)
covers the API and the supported language, including:

- [Getting Started](https://mipalgu.github.io/swift-xtend/documentation/xtend/gettingstarted):
  adding the package, running generators and handling diagnostics
- [The Supported Subset](https://mipalgu.github.io/swift-xtend/documentation/xtend/supportedsubset):
  which parts of Xtend are supported
- [Rich Strings](https://mipalgu.github.io/swift-xtend/documentation/xtend/richstrings):
  templates and their whitespace rules
- [Generators and Transformations](https://mipalgu.github.io/swift-xtend/documentation/xtend/generators):
  writing files and building models from models

## Licence

See the details in the LICENCE file.

This is an independent implementation based on the public
[Xtend documentation](https://eclipse.dev/Xtext/xtend/documentation/).

## References

- [Xtend documentation](https://eclipse.dev/Xtext/xtend/documentation/) - The language this package interprets a subset of
- [Xtext and Xbase](https://eclipse.dev/Xtext/) - The framework and expression language that Xtend builds on
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
- [swift-ecore](https://github.com/mipalgu/swift-ecore) - The Swift Ecore metamodelling framework

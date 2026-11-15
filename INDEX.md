# Swift Xtend

The [swift-xtend](https://github.com/mipalgu/swift-xtend) package provides
a pure Swift interpreter for a documented subset of
[Eclipse Xtend](https://eclipse.dev/Xtext/xtend/documentation/)
for code generation and model transformation.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-xtend.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+, Linux or Windows

## References

- [Xtend documentation](https://eclipse.dev/Xtext/xtend/documentation/)
- [Eclipse Xtext](https://eclipse.dev/Xtext/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Documentation

The package runs Xtend generators and transformations over Ecore models.
For details, see [Getting Started](https://mipalgu.github.io/swift-xtend/documentation/xtend/gettingstarted) and [The Supported Subset](https://mipalgu.github.io/swift-xtend/documentation/xtend/supportedsubset).

The `swift-xtend` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/)
is described in [swift-xtend](https://mipalgu.github.io/swift-modelling/documentation/swift_xtend/index.html),
and the [Xtend tutorial](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/xtend-01-code-generation/index.html)
introduces it step by step (see all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)).

- [Xtend module documentation](documentation/xtend/)
- [Getting Started](documentation/xtend/gettingstarted/)
- [The Supported Subset](documentation/xtend/supportedsubset/)
- [Rich Strings](documentation/xtend/richstrings/)
- [Generators and Transformations](documentation/xtend/generators/)
- [Code Generation with Xtend](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/xtend-01-code-generation/index.html)

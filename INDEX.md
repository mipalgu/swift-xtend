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

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit

## Documentation

The package runs Xtend generators and transformations over Ecore models.
For details, see [Getting Started](https://mipalgu.github.io/swift-xtend/documentation/xtend/gettingstarted) and [The Supported Subset](https://mipalgu.github.io/swift-xtend/documentation/xtend/supportedsubset).

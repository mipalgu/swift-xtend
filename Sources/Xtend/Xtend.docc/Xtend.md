# ``Xtend``

Interpret a subset of Xtend for templates and transformations over Ecore models.

## Overview

Xtend is a statically typed language that compiles to Java and is widely used to write code
generators and model transformations for the Eclipse Modeling Framework. This module runs a
documented subset of Xtend directly, without a Java virtual machine: classes with ordinary,
dispatch and create methods, extension methods, lambda expressions, collection literals, the
commonly used library functions, and rich strings with Xtend's smart whitespace handling.

Programs work on models held by `Resource`s: features of model objects are read and written
with Xtend's property syntax, and generators write files through an ``XtendFileSystemAccess``.
See <doc:GettingStarted> to run a first generator.

Java code is not available to interpreted programs. Imports, types, constructors and members
outside the documented subset (see ``XtendJavaSubset``) are reported with a diagnostic that
records where they occur.

## Related Documentation

### Command-Line Tool and Tutorials

- [swift-xtend](https://mipalgu.github.io/swift-modelling/documentation/swift_xtend/index.html): the `swift-xtend` command-line tool of swift-modelling
- [Code Generation with Xtend](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/xtend-01-code-generation/index.html)
- [All tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)

### Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/documentation/ecore/) - Ecore metamodels and models that Xtend programs work on
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/documentation/egl/) - Epsilon Generation Language (EGL) for model-to-text generation
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:SupportedSubset>
- <doc:RichStrings>
- <doc:Generators>

### Parsing and validation

- ``XtendParser``
- ``XtendParseResult``
- ``XtendProgram``
- ``XtendSource``
- ``XtendLanguage``

### Interpretation

- ``XtendInterpreter``
- ``XtendOptions``
- ``XtendHostValue``
- ``XtendRuntimeType``

### Generated files

- ``XtendFileSystemAccess``
- ``XtendInMemoryFileSystemAccess``
- ``XtendDirectoryFileSystemAccess``
- ``XtendGeneratedFile``
- ``XtendFilePath``

### The Java subset and the library

- ``XtendJavaSubset``
- ``XtendBuiltinType``
- ``XtendLibrary``

### Diagnostics

- ``XtendError``
- ``XtendDiagnosticCode``

### Syntax tree

- ``XtendFile``
- ``XtendClass``
- ``XtendField``
- ``XtendMethod``
- ``XtendParameter``
- ``XtendCreateClause``
- ``XtendModifiers``
- ``XtendAnnotation``
- ``XtendImport``
- ``XtendTypeReference``
- ``XtendExpression``
- ``XtendSwitch``
- ``XtendSwitchCase``

### Templates

- ``XtendTemplate``
- ``XtendTemplateInstruction``
- ``XtendTemplateLoop``
- ``XtendTemplateConditional``
- ``XtendTemplateBranch``

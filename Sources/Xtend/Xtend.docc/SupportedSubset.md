# The Supported Subset

Which parts of Xtend the interpreter supports fully, partially or not at all.

## Overview

The interpreter targets the Xtend that code generators and model transformations commonly
use. Everything outside the subset is reported: constructs the parser recognises but does not
run produce ``XtendDiagnosticCode/unsupportedConstruct``, and Java code outside the documented
allow-list produces one of the `xtend.java` codes.

Interpretation is dynamic. Type references must resolve, and they decide type guards,
`instanceof`, casts, `filter(Type)` and the choice of dispatch cases, but there is no static
type checking: a type error that the Xtend compiler would reject is reported when the
offending expression runs.

## Coverage

| Area | Status | Notes |
| :-- | :-- | :-- |
| Classes, fields, methods, constructors | Supported | `val`/`var` fields with or without types and initialisers; `def` and `override`; `new(...)` with `this(...)` and `super(...)` delegation; `static` methods and fields; abstract classes; single inheritance within the compilation set; `super.method(...)`. |
| Dispatch methods | Supported | `def dispatch` cases are chosen at run time by the types of all arguments: metamodel classes (including their supertypes), classes of the compilation set and built-in types, with `Void` matching `null`. Subclasses override individual cases. As in Xtend, the dispatcher takes the common supertypes of the parameter types of its cases, which ``XtendProgram/dispatcherParameters(of:arity:in:)`` gives. |
| Create methods | Supported | `def create new T() m(...)` and `def create name: expr m(...)` return the cached object for the same receiver and arguments; the cache is filled before the body runs, so cycles work. |
| Extension methods | Supported | Methods of the running class, `extension` fields (`@Inject extension` fields are instantiated automatically), `extension` parameters and local variables, and `import static extension` of classes of the compilation set. Implicit `it` receivers work, as in `list.map[compile]`. |
| Expressions | Supported | Blocks, `val`/`var`, `if`, `switch` with type guards, `case` predicates, value cases, fall-through and `default`, `for` over collections and counting `for`, `while`, `do`...`while`, `return`, `instanceof`, `as`, `typeof`. |
| Lambda expressions | Supported | `[x, y | ...]`, `[...]` with implicit `it`, `[| ...]`, and `apply`. |
| Literals | Supported | Whole numbers (decimal, hexadecimal, underscores, `L` suffix), floating point numbers, strings in either quote with escapes, `#[...]` lists, `#{...}` sets and maps (`#{k -> v}`), `null`, `true`, `false`. |
| Operators | Supported | `+ - * / % **`, `< <= > >=`, `== != === !==`, `&& || !`, `->`, `..`, `..<`, `>..`, `?:`, `?.`, `=>`, `+= -= *= /= %=` (`+=` and `-=` also on collections and maps), `++ --`, string concatenation with any value. |
| Rich strings | Supported | Interpolation with guillemets, `FOR` with `BEFORE`, `SEPARATOR` and `AFTER`, `IF`, `ELSEIF`, `ELSE`, `ENDIF`, `ENDFOR`, and the whitespace rules described in <doc:RichStrings>. |
| Library | Supported | See ``XtendLibrary``: `map`, `filter` (lambda or type), `filterNull`, `forEach` (with optional index), `exists`, `forall`, `findFirst`, `findLast`, `head`, `last`, `tail`, `take`, `drop`, `takeWhile`, `dropWhile`, `join` (all four forms), `sort`, `sortBy`, `sortWith`, `reverse`, `toList`, `toSet`, `toMap`, `toInvertedMap`, `groupBy`, `flatten`, `flatMap`, `size`, `isEmpty`, `isNullOrEmpty`, `reduce`, `fold`, `indexed`, `max`, `min`, `maxBy`, `minBy`, `toFirstUpper`, `toFirstLower`, map `forEach`, `filter` and `mapValues`, `upTo`, the `new...` collection literals, `println` and `print`. |
| Model navigation | Supported | Property syntax (`obj.name`, `obj.getName()`, `obj.isAbstract`, `obj.EAllAttributes`), setters and assignments, many-valued features changed with `+=`, `add`, `addAll`, `remove` or `set`, `eClass`, `eContainer`, `eContents`, `eAllContents`, `eResource`, `eContainingFeature`, `eGet`, `eSet`, `eIsSet`, enumeration literals as `Kind::LITERAL` or `Kind.LITERAL`, and objects created with `new` for metamodel classes. Metamodels can be the input: their elements expose the features of the Ecore metamodel reflectively. |
| Generators | Supported | A class with `doGenerate(resource, fsa[, context])` or `generate(resource, fsa)`, `resource.contents` and `resource.allContents`, and `fsa.generateFile(name[, outputConfiguration], contents)`. See <doc:Generators>. |
| Java types and members | Partial | Only the allow-list of ``XtendJavaSubset``: common members of `String`, `List`, `Set`, `Map`, numbers and pairs; a few static members of `String`, `Integer`, `Long`, `Double`, `Boolean` and `Math`; constructors of lists, sets, maps and the listed exceptions. Everything else is reported. |
| Typing | Partial | Type arguments are ignored; numbers are one 64-bit whole-number type and one floating point type; `char` is a one-character string; overloads are chosen by run-time types. |
| Collections | Partial | `map`, `filter` and similar functions return eager lists rather than lazy views; `reverse` returns a reversed copy; a list read from a many-valued feature is a copy that writes changes back to the feature. Whether `+=` adds one element or all elements of a collection is decided by the run-time value. |
| Visibility and finality | Partial | Visibility modifiers are accepted but not enforced; final fields may be assigned outside constructors. Final local variables are enforced. |
| Comments in rich strings | Partial | `«««` comments end at the line break: a line that holds only a comment produces no output, while text before a trailing comment is kept. |
| Text of model objects | Partial | Model objects print as their class name followed by their set attributes, not as EMF's Java object text. |
| `throw` | Partial | `throw new RuntimeException(...)` and the other listed exceptions stop evaluation with ``XtendDiagnosticCode/thrownException``. |
| Annotations | Partial | `@Inject`, `@Override` and `@SuppressWarnings` are understood; any other annotation, including active annotations such as `@Data` and `@Accessors`, is reported. |
| `try`, `catch`, `finally`, `synchronized` | Unsupported | Reported as unsupported constructs. |
| Interfaces, enumerations, annotation types | Unsupported | Only classes can be declared. |
| Java interop | Unsupported | Imports, type references, constructor calls and static members of Java types outside the allow-list are reported when the program is validated; Java members outside the allow-list are reported when they are called. |
| Generic methods and type parameters | Unsupported | Declarations such as `def <T> f(T t)` do not parse. |
| Model operations and derived features | Unsupported | Operations (`EOperation`) of metamodel classes cannot be called; derived features are read as stored. |

## Limits

``XtendOptions`` bounds the depth of calls and the number of evaluation steps, so that a
runaway program ends with ``XtendDiagnosticCode/recursionLimit`` or
``XtendDiagnosticCode/stepLimit``. Generated file paths must be relative and must not leave
the output location (see ``XtendFilePath``).

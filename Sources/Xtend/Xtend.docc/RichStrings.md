# Rich Strings and Whitespace

How templates produce their text, line by line.

## Overview

A rich string is delimited by `'''`. Inside it, guillemets (`«` and `»`) enclose
interpolated expressions and control structures. A rich string evaluates to a string, and
`null` values insert nothing.

Templates are indented to match the surrounding code, but that indentation is not meant for
the output. Xtend therefore applies three rules, and so does the interpreter:

1. Indentation that is relative to a control structure is not part of the output. Control
   structures are `FOR` loops, `IF` conditionals, and the opening and closing delimiters of the
   rich string. Indentation counts as relative to a control structure if the previous line ends
   with that structure followed only by whitespace. Only the difference to the indentation of
   that first line is kept.
2. A line that holds no static text other than whitespace, but holds control structures or
   interpolations that evaluate to nothing but whitespace, does not appear in the output.
3. Line breaks in inserted values are followed by the indentation of the line that holds the
   interpolation.

In addition, the line of the opening delimiter is dropped if nothing but whitespace follows the
delimiter, and the line of the closing delimiter is dropped if nothing but whitespace precedes
it. Text on the line of the opening delimiter is kept as written.

## Examples

The indentation before `node` is relative to the opening delimiter and is dropped:

```xtend
def print(String name) '''
    node «name» {}
'''
```

`print('NodeName')` returns `node NodeName {}` followed by a line break.

Nested control structures add only their own relative indentation. Lines with only control
structures vanish, and the indentation of a line propagates into the text of a nested
template call:

```xtend
def print(Node n) '''
    node «n.name» {
      «IF !n.children.empty»
        «FOR c : n.children»
          «print(c)»
        «ENDFOR»
      «ENDIF»
    }
'''
```

For a parent with the children `FirstChild` and `SecondChild`, where `SecondChild` has a
child `Leaf`, this produces:

```
node Parent {
  node FirstChild {
  }
  node SecondChild {
    node Leaf {
    }
  }
}
```

## Loops

`FOR` repeats its body for each element of a collection. `BEFORE` is written before the first
iteration and `AFTER` after the last one, both only if there is at least one element.
`SEPARATOR` is written between iterations, directly after the last non-whitespace text of the
previous iteration, so that it lands before a line break:

```xtend
def call(List<String> names) '''
    call(
      «FOR n : names SEPARATOR ','»
        «n»
      «ENDFOR»
    )
'''
```

For `#['a', 'b']` this produces `call(`, `  a,`, `  b` and `)` on separate lines.

## Inserted text

When an inserted value spans several lines, each line after the first receives the
indentation of the interpolating line. A nested template's final line break is not doubled,
because the indentation that follows it leaves a line of whitespace only, which rule 2 removes.
Blank lines inside an inserted value keep the indentation, exactly as Xtend's
`StringConcatenation` does.

## Comments

`«««` starts a comment that ends at the line break. A line that holds only a comment produces
no output.

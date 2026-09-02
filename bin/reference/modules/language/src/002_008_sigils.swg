#global private

/**
# Compiler Syntax: '#' and 'Swag'

Swag reserves '#' for compiler syntax. Runtime and compiler primitives use
ordinary qualified names in the reserved 'Swag' namespace:

- '#' introduces directives, compile-time queries, and modifiers.
- 'Swag.name' calls a primitive operation without reserving 'name' in user code.
- '.count' and '.buffer' expose the native shape of strings, arrays, slices,
  'any' values, and interfaces through ordinary member access.

This keeps the parser surface small: only '#' introduces special syntax, while
intrinsics look and compose like normal functions and members. An operation such
as 'Swag.min' works in compile-time code and runtime code; 'Swag.compiler()' is
available only at compile time.

# Modifier or Attribute

A modifier and an attribute both annotate code, so one rule decides which is
which:

> An attribute annotates something that has a **symbol**. A modifier annotates
> something that does not.

An attribute is a named, parameterized annotation attached to a declaration, so
it can be reflected ('TypeInfoStruct.attributes'), declared by user code with
'attr', and inherited by everything a block contains. A type, an operand, a
conversion, a literal, or a statement carries no symbol: reflection could never
report an annotation there, so those take a modifier instead.

The rule fixes the properties of each family:

| | Modifier | Attribute |
|---|---|---|
| Set | closed, compiler-defined | open, 'attr' declares more |
| Target | type, operand, cast, literal, statement | declaration, lexical scope |
| Parameters | never | yes |
| Reflection | never | yes |
| Inherited by a scope | never | yes |

'Swag.AttrUsage' names the declaration kinds an attribute accepts, and the
compiler rejects the attribute anywhere else. A block is the exception: it
broadcasts to the declarations it contains, and each of those is checked on its
own.

# Directives and Static Queries

Directives shape compilation or declare compiler-managed entry points:

```swag
#static if DEBUG
{
    // Included only when DEBUG is a compile-time true value.
}
#run { generateTables() }
#test { Swag.assert(parse("ok")) }
```

Static queries produce facts known by semantic analysis:
*/

#test
{
    const Answer = 42

    #assert(#sizeof(s32) == 4)
    #assert(#alignof(s32) == 4)
    #assert(#typeof(Answer) == s32)
    #assert(#stringof(Answer) == "42")
}

/**
'#assert' itself runs during compilation. If its condition is not a constant
'bool', compilation fails.

# Intrinsic Values and Operations

Intrinsics participate in expressions. Some expose context ('Swag.args()',
'Swag.getContext()'), some construct runtime-shaped values ('Swag.makeSlice', 'Swag.makeAny'), and some
perform primitive operations ('Swag.sqrt', 'Swag.memcpy', 'Swag.atomadd').
*/

#test
{
    var values: const [..] s32 = [10, 20, 30]

    Swag.assert(values.count == 3)
    let data = values.buffer
    Swag.assert(data[1] == 20)

    // The same intrinsic can be evaluated by the compiler in a constant context.
    const Minimum = Swag.min(7's32, 3's32)
    #assert(Minimum == 3)
}

/**
# Related Names with Different Semantics

Some concepts have both a directive and an intrinsic:

| Compile-time form | Intrinsic form |
|---|---|
| '#assert(condition)' rejects the build | 'Swag.assert(condition)' checks in its execution context |
| '#print(text)' writes while compiling | 'Swag.print(...)' writes when the containing code executes |
| '#init { ... }' declares a module hook | 'Swag.init(...)' initializes values or memory |
| '#drop { ... }' declares a module hook | 'Swag.drop(...)' drops values or memory |

The pairs are related, not symmetrical. The compile-time diagnostics '#print',
'#assert', '#error' and '#warning' each take exactly **one** compile-time
expression, so several parts are joined with the '++' concatenation operator.
Their intrinsic counterparts follow ordinary call rules, and 'Swag.print' is variadic:

```swag
#print("kind: " ++ #nameof(#typeof(value)))     // one expression, joined with '++'
Swag.print("kind: ", name, "\n")                    // variadic at runtime
```

Inside '#run', a 'Swag' intrinsic executes during compilation because the
containing code does. In an ordinary function, the same call becomes generated
runtime behavior.

# The Four Modifier Families

The modifiers are not one list. Each one belongs to exactly one of four
families, and the family says what it annotates.

# Type Qualifiers

'#null' is part of the type itself and takes part in conversions. The bare
'null' token is a value:
*/

#test
{
    let missing: #null *s32 = null
    Swag.assert(missing == null)
}

/**
'#simd' also builds a type: it turns a 16-byte array shape into a packed
vector whose lanes compute element-wise (see the simd chapter):
*/

#test
{
    var lanes: #simd [4] s32
    Swag.assert(#alignof(lanes) == 16)
}

/**
# Passing Modes

'#move' and '#fwd' in a parameter position are part of the signature: they
select how an argument reaches the callee. They belong to the type, so they
cannot be attributes.

```swag
func take(value: #move Buffer) { ... }
```

# Operation Modifiers

These change one operation rather than producing a value:
*/

#test
{
    var byte = 255'u8
    byte += #wrap 1'u8
    Swag.assert(byte == 0)

    #assert(#typeof(255'u8 + #prom 1'u8) == u32)

    let bits = cast #bit (u32) 1.0'f32
    Swag.assert(bits == 0x3F800000)
}

/**
'#bit' and '#unconst' select a variant of the 'cast' they sit in; neither is a
type qualifier, and neither can be written in a type position. '#unconst'
removes a const qualifier only where the language permits that explicit escape.

'#nodrop', '#move', and '#relocate' modify one assignment or one initializer.

'#raw' modifies how the compiler reads the string literal that follows: its
content is taken verbatim, with no escape sequence recognized.

```swag
let pattern = #raw "(\d+)x(\d+)"
let payload = #raw """{"key": "value"}"""
```

# Statement Modifiers

These refine the statement they follow. A statement has no symbol, and this
syntax does not define an extension point. Iteration strategies are ordinary views,
returned by methods such as '.pairs()' and '.reversed()'.
*/

#test
{
    enum Direction { Up, Down }
    let direction = Direction.Up

    switch #complete direction
    {
    case .Up:   Swag.assert(true)
    case .Down: Swag.assert(false)
    }
}

/**
'defer #fail' and 'defer #nofail' select which exit path runs the deferred
statement. They are opposite exit paths and cannot be combined.

# Where Modifiers Go

A modifier is always written **immediately after the keyword it modifies**, never
after the operand: 'switch #complete value', not 'switch value #complete'. The
same holds for 'cast', 'defer', and an assignment operator.

A directive is the opposite: it comes **first**, because it introduces the
construct instead of refining one. '#static switch' is not a 'switch' carrying a
flag; it is a distinct compile-time construct that happens to reuse the 'switch'
spelling. That is why '#static' leads and '#complete' follows:

```swag
#static switch #complete value
```

Several modifiers on the same construct form a **set**, so their order carries no
meaning and a repeat is rejected:

```swag
a = #nodrop #move b     // same as '#move #nodrop'
let bits = cast #bit #unconst (*s32) p
```

Custom traversal uses regular expression composition:

```swag
for left, right in values.pairs() {}
for value in values.reversed() {}
```
*/

#test
{
    var a = 250'u8

    // Order between modifiers carries no meaning.
    #assert(#typeof(a + #wrap #prom 1'u8) == u32)
    #assert(#typeof(a + #prom #wrap 1'u8) == u32)
}

/**
# Choosing the Narrowest Scope

'#wrap' opts one arithmetic operation into wrapping behavior. Broader runtime
guard policy uses 'Swag.Safety' on a scope, and module defaults live in 'BuildCfg':

Left shift is already truncating: bits shifted out of the left operand are
discarded without an overflow panic. '#wrap' remains accepted on '<<' and
'<<=' for compatibility, but it does not change their result or count rules.

```swag
#[Swag.Safety(.Overflow, false)]
{
    // Overflow guards are disabled only in this lexical scope.
}
```

Both spellings are legitimate, and the rule above says which is which: '#wrap'
annotates one operation, 'Swag.Safety' annotates a scope. Use the narrowest one
that expresses the intent. A local '#wrap' documents one deliberate wrap more
clearly than disabling overflow checks for a file.

# Contextual Keywords Are Different

Bare 'as' and 'is' are grammar keywords used by matching constructs. 'Swag.typeAs' and
'Swag.typeIs' are intrinsics and can appear in expressions. The spelling is related,
but the parser and type checker give the two forms distinct roles.
*/

#test
{
    let value: any = "text"

    switch value
    {
    case string as text: Swag.assert(text == "text")
    default:             Swag.assert(false)
    }
}

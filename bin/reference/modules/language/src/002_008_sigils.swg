#global private

/**
# Compiler Names: '#' and '@'

Swag gives two prefixed name families special syntactic roles. They cannot
collide with ordinary identifiers:

- '#' introduces directives, compile-time queries, and modifiers.
- '@' introduces intrinsic values and operations implemented by the compiler
  or runtime.

The prefix describes the facility's role, not necessarily when it executes.
An intrinsic such as '@min' works in compile-time code and runtime code;
'@compiler' is available only at compile time.

Some extension points also accept a user-defined sharp selector. For example,
'for #Pairs ...' resolves the custom iteration hook 'opVisitPairs'. Such a
selector is still part of '#'-syntax; it does not create an ordinary identifier
named '#Pairs'.

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
#test { @assert(parse("ok")) }
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

Intrinsics participate in expressions. Some expose context ('@index', '@args',
'@getcontext'), some construct runtime-shaped values ('@mkslice', '@mkany'), and some
perform primitive operations ('@sqrt', '@memcpy', '@atomadd').
*/

#test
{
    var values: const [..] s32 = [10, 20, 30]

    @assert(@countof(values) == 3)
    let data = @dataof(values)
    @assert(data[1] == 20)

    // The same intrinsic can be evaluated by the compiler in a constant context.
    const Minimum = @min(7's32, 3's32)
    #assert(Minimum == 3)
}

/**
# Related Names with Different Semantics

Some concepts have both a directive and an intrinsic:

| Compile-time form | Intrinsic form |
|---|---|
| '#assert(condition)' rejects the build | '@assert(condition)' checks in its execution context |
| '#print(text)' writes while compiling | '@print(...)' writes when the containing code executes |
| '#init { ... }' declares a module hook | '@init(...)' initializes values or memory |
| '#drop { ... }' declares a module hook | '@drop(...)' drops values or memory |

The pairs are related, not symmetrical. The compile-time diagnostics '#print',
'#assert', '#error' and '#warning' each take exactly **one** compile-time
expression, so several parts are joined with the '++' concatenation operator.
Their intrinsic counterparts follow ordinary call rules, and '@print' is variadic:

```swag
#print("kind: " ++ #nameof(#typeof(value)))     // one expression, joined with '++'
@print("kind: ", name, "\n")                    // variadic at runtime
```

Inside '#run', an '@' intrinsic executes during compilation because the
containing code does. In an ordinary function, the same intrinsic becomes
generated runtime behavior.

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
    @assert(missing == null)
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
    @assert(byte == 0)

    #assert(#typeof(255'u8 + #prom 1'u8) == u32)

    let bits = cast #bit (u32) 1.0'f32
    @assert(bits == 0x3F800000)
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

# Statement Selectors

These choose a variant of the statement they follow. A statement has no symbol,
so a selector is the only form available — and this is the family a user
extends with a custom sharp selector such as 'for #Pairs'.
*/

#test
{
    var expected = 2
    for #reverse 3
    {
        @assert(@index == expected)
        expected -= 1
    }

    enum Direction { Up, Down }
    let direction = Direction.Up

    switch #complete direction
    {
    case .Up:   @assert(true)
    case .Down: @assert(false)
    }
}

/**
'defer #fail' and 'defer #nofail' select which exit path runs the deferred
statement. They are opposite exit paths and cannot be combined.

# Where Modifiers Go

A modifier is always written **immediately after the keyword it modifies**, never
after the operand: 'switch #complete value', not 'switch value #complete'. The
same holds for 'cast', 'for', 'defer', and an assignment operator.

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

One ordering rule does exist: on 'for', a custom sharp selector comes **before**
the modifiers, because the selector names which iteration hook is resolved.

```swag
for #Pairs #reverse [right] in values     // accepted
for #reverse #Pairs [right] in values     // rejected
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

Bare 'as' and 'is' are grammar keywords used by matching constructs. '@as' and
'@is' are intrinsics and can appear in expressions. The spelling is related,
but the parser and type checker give the two forms distinct roles.
*/

#test
{
    let boxed: any = "text"

    switch boxed
    {
    case string as text: @assert(text == "text")
    default:             @assert(false)
    }
}

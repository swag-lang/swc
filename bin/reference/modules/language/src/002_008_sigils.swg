#global private

/**
# Compiler Names: '#' and '@'

Swag gives two prefixed name families special syntactic roles. They cannot
collide with ordinary identifiers:

- '#' introduces directives, compile-time queries, type qualifiers, and
  operation modifiers.
- '@' introduces intrinsic values and operations implemented by the compiler
  or runtime.

The prefix describes the facility's role, not necessarily when it executes.
An intrinsic such as '@min' works in compile-time code and runtime code;
'@compiler' is available only at compile time.

Some extension points also accept a user-defined sharp selector. For example,
'for #Pairs ...' resolves the custom iteration hook 'opVisitPairs'. Such a
selector is still part of '#'-syntax; it does not create an ordinary identifier
named '#Pairs'.

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
| '#print(...)' writes while compiling | '@print(...)' writes when the containing code executes |
| '#init { ... }' declares a module hook | '@init(...)' initializes values or memory |
| '#drop { ... }' declares a module hook | '@drop(...)' drops values or memory |

Inside '#run', an '@' intrinsic executes during compilation because the
containing code does. In an ordinary function, the same intrinsic becomes
generated runtime behavior.

# Type Qualifiers

'#null', '#late', and '#unconst' modify a type or declaration. The bare 'null'
token is a value:
*/

#test
{
    let missing: #null *s32 = null
    @assert(missing == null)
}

/**
'#null *T' admits the 'null' value. '#late' defers initialization of a
nullable-capable field while exposing it as non-null after a guarded write.
'#unconst' removes a const qualifier only where the language permits that
explicit escape.

# Operation Modifiers

Modifiers change one operation rather than producing a value:
*/

#test
{
    var byte = 255'u8
    byte += #wrap 1'u8
    @assert(byte == 0)

    #assert(#typeof(255'u8 + #prom 1'u8) == u32)

    let bits = cast #bit (u32) 1.0'f32
    @assert(bits == 0x3F800000)

    var expected = 2
    for #reverse 3
    {
        @assert(@index == expected)
        expected -= 1
    }
}

/**
'#wrap' opts one arithmetic operation into wrapping behavior. Broader runtime
guard policy uses 'Swag.Safety', and module defaults live in 'BuildCfg':

```swag
#[Swag.Safety(.Overflow, false)]
{
    // Overflow guards are disabled only in this lexical scope.
}
```

Use the narrowest scope that expresses the intent. A local '#wrap' documents
one deliberate wrap more clearly than disabling overflow checks for a file.

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

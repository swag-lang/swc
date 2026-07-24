#global private

/**
# The Two Sigils

Swag reserves two prefix sigils, '#' and '@', and gives everything else to you.
This is a deliberate contract, not decoration:

> Bare identifiers belong to the user. The language only ever takes a bare word
> for a **frozen, closed set** — the structural keywords ('if', 'func', 'struct',
> 'const', 'let'...) and the literals ('true', 'false', 'null', 'undefined').
> **Anything the language can still grow lives behind '#' or '@'.**

Because of this, a future release can add '#simd', '@prefetch', or '#pure' without
breaking a single existing program: the names it needs are already fenced off. You
never have to rename a variable because a new compiler shipped.
*/

/**
# The Law

The two sigils are not interchangeable. They mark **which plane** a name lives on:

> **'#X'** addresses the **compiler**. It is a directive, a conditional-compilation
> switch, a static query, or an annotation that tells the compiler *how to treat*
> a type or an operation. It leaves **no trace at runtime**: it either steers
> compilation, or reduces to a literal baked in before the program runs.
>
> **'@X'** addresses the **machine**. It is a value or an operation **present in the
> running program**, even when the optimizer can fold it at compile time.

To classify any name, ask a single question:

> *Does it still exist once the compiler is gone?*
> No -> '#'.  Yes -> '@'.
*/

/**
# The Compiler Plane: '#'

Everything under '#' is consumed by the compiler. Four shapes live here:

- **Directives** that steer compilation: '#run', '#test', '#main', '#import', '#load'.
- **Conditional compilation**: '#if', '#else', '#elif', '#global', '#scope'.
- **Static queries** that resolve to a compile-time fact: '#sizeof', '#alignof',
  '#offsetof', '#typeof', '#decltype', '#nameof', '#stringof', '#location'.
- **Annotations** on a type or an operation: the '#null' / '#late' type qualifiers
  and the '#wrap' / '#prom' / '#reverse' / '#bit' / '#move' modifiers.

A '#' query is answered before the program exists, so it can only ever see static
facts.
*/
#test
{
    const X = 42

    #assert(#sizeof(s32) == 4)      // the size of a type is a static fact
    #assert(#typeof(X) == s32)      // the type of an expression is a static fact
    #assert(#stringof(X) == "42")   // rendered by the compiler, not the machine
}

/**
# The Machine Plane: '@'

Everything under '@' is a value or an operation that exists while the program runs:

- **Values** carried by the running program: '@err', '@index', '@args'.
- **Operations** the machine performs: '@memcpy', '@sqrt', '@atomadd', '@alloc'.
- **Constructors** of runtime values: '@mkslice', '@mkstring', '@mkany'.
- **Runtime queries** on dynamic values: '@countof', '@dataof', '@kindof'.

A '@' name reads or acts on data that has an address and a lifetime.
*/
#test
{
    var data: const [..] s32 = [10, 20, 30]

    @assert(@countof(data) == 3)     // the length lives in the slice at runtime

    let addr = @dataof(data)
    @assert(addr[0] == 10)           // the data has a runtime address
}

/**
# One Question Decides It

The single test above already resolves the pairs that look inconsistent at first
glance. Size and count are the clearest example:

- '#sizeof' is **always** a compile-time constant — the size of a type never varies,
  so it lives on the compiler plane.
- '@countof' can read a **runtime** length — a slice carries its element count as
  data, so the same call gives different answers as the program runs.
*/
#test
{
    #assert(#sizeof(s32) == 4)       // fixed forever, at compile time

    var view: const [..] s32 = [1, 2, 3, 4]
    @assert(@countof(view) == 4)
    view = [1, 2]
    @assert(@countof(view) == 2)     // same call, a different runtime answer

    // '#typeof' is the static type; '@kindof' inspects the dynamic type of a value.
    let boxed: any = "text"
    #assert(#typeof(boxed) == any)
    @assert(@kindof(boxed) == string)
}

/**
# Same Concept, Both Planes, Same Name

When one concept has both a compile-time form and a runtime form, it keeps **the
same identifier** under each sigle. The sigil, not a different word, tells you which
plane you are on:

```swag
#assert   @assert     // check now, at compile time  /  check while running
#print    @print      // print during compilation    /  print at runtime
#init     @init       // register an init block       /  run the construction
#drop     @drop       // register / mark for drop     /  run the destruction
````

So the one-character difference between '#assert' and '@assert' is not a trap: it is
the whole meaning. Never give the two planes of one concept divergent names.
*/
#test
{
    #assert(1 + 1 == 2)     // the compiler proves it; the check is gone at runtime
    @assert(1 + 1 == 2)     // the machine proves it while running
}

/**
# Values Are Bare, Qualifiers Are '#'

'null' exists in two roles, and the sigil keeps them apart:

- The **value** is a bare literal, part of the frozen set: 'null', 'true', 'false',
  'undefined'. It is data the program manipulates.
- The **type qualifier** is a compiler instruction, so it takes '#': '#null' and
  '#late'. It does not manipulate data; it tells the compiler how to type storage.

'p = null' assigns a value. 'p: #null *T' annotates a type so that the bare value
'null' is allowed to inhabit it.
*/
#test
{
    let flag              = true          // a bare literal: a value
    let missing: #null *s32 = null        // '#null' qualifies the type; 'null' is the value

    @assert(flag == true)
    @assert(missing == null)
}

/**
# Modifiers Are Compiler Instructions

A modifier does not produce a runtime value; it changes the code the compiler emits
for a single operation (skip the overflow check, iterate backwards, reinterpret bits,
move instead of copy). That is a compiler instruction, so it wears '#'.

> A '#' modifier prefixes the **operation** whose behavior it changes: right after
> the operator when there is one, otherwise in front of the operand. Never elsewhere.
*/
#test
{
    var x = 255'u8
    x += #wrap 1                                    // on the '+=' operation
    @assert(x == 0)

    #assert(#typeof(255'u8 + #prom 1'u8) == u32)    // widen the operands first

    let bits = cast #bit (u32) 1.0'f32              // reinterpret, do not convert
    @assert(bits == 0x3F800000)

    var seen = 0
    for #reverse 3                                  // on the loop
    {
        @assert(@index == 2 - seen)
        seen += 1
    }
}

/**
# One Setting, Three Scopes, One Vocabulary

A behavior toggle appears at three scopes, and they share **one vocabulary** and
nest as a clean override cascade — global default, overridden per block, overridden
per operation:

- **'#name'** affects a single operation — '#wrap' on one '+='.
- **'#[Swag.Safety(.Overflow, false)]'** affects a declaration or a lexical block.
- **'buildCfg.safetyGuards'** affects a whole module or workspace.

The scope form is uniform: 'Swag.Safety(.Check, enabled)' covers every check
('.Overflow', '.BoundCheck', '.DynCast', '.Math', ...) with the same shape. Do not
invent a differently named alias for the same toggle at a different scope.
*/
#[Swag.Safety(.Overflow, false)]
#test
{
    var x = 255'u8
    x += 1                    // the block opts out of the overflow check
    @assert(x == 0)
}

/**
# Contextual Keywords Versus Intrinsics

A few names appear both as a bare contextual keyword and as an '@' intrinsic:
'as' / 'is' versus '@as' / '@is'. They do not collide because they live in different
positions:

- The bare 'as' / 'is' are **contextual keywords**, meaningful only inside a
  'switch' / pattern position — 'case string as text'. They bind or match as the
  grammar directs.
- '@as' / '@is' are the **general runtime primitives** for converting or testing a
  dynamic value anywhere in an expression.

The bare form reads as part of a statement's shape; the '@' form reads as an
operation you can place in any expression.
*/
#test
{
    let boxed: any = "text"
    switch boxed
    {
    case string as text:                 // 'as' binds inside the case
        @assert(text == "text")
    default:
        @assert(false)
    }
}

/**
# Forward Compatibility

This is why the two sigils are worth their weight. The frozen bare set never grows,
so your identifiers are safe forever. Everything the language may still add — new
queries, new intrinsics, new modifiers — arrives under '#' or '@', already fenced
off from your names.

> If a feature is extensible, it takes a sigil.
> If it is a frozen structural keyword or a literal, it stays bare.
> Nothing else is ever bare.
*/

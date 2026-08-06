#global private

/**
# Single-Value Pointers

A pointer to a **single element** is declared using the `*` symbol.
It represents the memory address of one instance of a given type.

Pointers can reference any type of data and are fundamental for efficient memory access and manipulation.
*/
#test
{
    var ptr1: #null *u8            // Pointer to a single 'u8' value
    var ptr2: #null *#null *u8     // Pointer to another pointer to 'u8'
}

/**
# Null Pointers

In Swag, a pointer can be `null`, meaning it does not refer to any valid memory location.
Null pointers are often used to indicate uninitialized or intentionally empty references.

It is good practice to check for null pointers before dereferencing them to avoid runtime errors.
*/
#test
{
    var ptr1: #null *u8
    @assert(ptr1 == null)     // Uninitialized pointers are null by default
}

/**
# Non-Null by Default

Nullable-capable types — single-value and block pointers, slices, `string`, `cstring`,
`any`, and `typeinfo` — are non-null by default: a bare `*u8` or `string` cannot be
initialized with `null` and has no implicit default. A struct field of such a type must
therefore be supplied by an aggregate initializer unless it declares an explicit non-null
default. Use `#null` to opt into nullability when null is part of the intended contract.

A `#null` value cannot flow into a bare (non-null) slot directly, and it cannot be
dereferenced, indexed, member-accessed or called while it is still nullable: every use
site needs a proof. Flow narrowing provides it implicitly (a dominating null test such
as `if p == null do return`, `if p do ...`, `@assert(p != null)`, or the left side of
`and`/`or`), the postfix `!` asserts it explicitly (a safety check panics at runtime if
the value is still null), and `?.` skips the access entirely when the value is null.
Comparisons between `#null` and bare values of the same type are always allowed.
`undefined` remains an explicit low-level escape hatch and must only be used when the
storage is initialized manually before it is read.

A value with `opDrop` can be consumed with `#move` only when resetting its moved-from
source does not require explicit initialization. Give required fields a default, or use
`undefined` deliberately as the low-level escape hatch described above, before moving a
droppable value.
*/
#test
{
    struct NonNullPointerHolder
    {
        ptr: *u8
    }

    var value           = 42'u8
    var values          = [1, 2, 3]
    let ptr:   *u8      = &value
    let text:  string   = "value"
    let slice: [..] s32 = values
    let holder          = NonNullPointerHolder{ptr: &value}

    #assert(#typeof(ptr) == *u8)
    #assert(#typeof(text) == string)
    #assert(#typeof(slice) == [..] s32)
    #assert(#typeof(holder.ptr) == *u8)
}

/**
# Use-Site Nullability, `?.` and `!`

Dereferencing a value whose type is still `#null` is a compile-time error: the flow
must prove the value non-null first. The sanctioned routes are a dominating null test
(flow narrowing), the `?.` guarded access, and the postfix `!` assertion.

`@assert(p != null)` is a dominating null test like any other: the statements after it
are only reachable when the condition held, so the proof covers the remainder of the
enclosing block. It reads as a precondition rather than as a per-use assertion, which
suits a value that is guaranteed non-null for a whole function body. Like every other
narrowing proof, it is dropped as soon as the path is reassigned.

`p!` and `p?.` are the two outcomes of the same test. `?.` skips the rest of the postfix
chain when the tested value is null; `!` claims the value is there and panics under
`Swag.SafetyWhat.Expect` when it is not. Being postfix, `!` binds tighter than every
prefix form and chains freely: `p!.count`, `buffer![i]`, `handler!()`. Because it cannot
produce an absent result, what follows keeps its plain type — `node!.count` is an `s64`,
never a `#null` one, and needs no fallback.

`try`, `catch` and `expect` swallow everything to their right, so a `!` written after one
of them applies to its **result**: `expect load(path)!` asserts the loaded value, not the
fallible call. Parenthesize to assert something inside instead.

A `?.` chain whose result is itself nullable-capable (a pointer, string, slice,
interface...) simply produces the null outcome in its own type. A chain producing a
plain value (an integer, a bool...) cannot carry the null outcome and must hand it to
an immediate `orelse` fallback. A void call through `?.` is a statement that does
nothing when the value is null.

Write `!` where an invariant makes the value always present and a null would be a bug
worth stopping on; write `?.` where absence is an ordinary outcome the code handles.
Both are tolerated on a value the flow already proved, so a redundant one in a narrowed
region is dead, not wrong.
*/
#test
{
    struct OptChainRefDoc
    {
        count: s64
        next:  #null *OptChainRefDoc
    }

    var first:  OptChainRefDoc
    var second: OptChainRefDoc
    first.count  = 2
    first.next   = &second
    second.count = 7

    var p: #null *OptChainRefDoc = &first

    // Narrowing: the null test dominates the dereference.
    if p != null do
        @assert(p.count == 2)

    // The postfix '!' asserts the proof explicitly (panics at runtime if wrong).
    let q = p!
    @assert(q.count == 2)

    // '@assert' proves the path for the rest of the block, like a precondition.
    @assert(p != null)
    @assert(p.count == 2)

    // '!' asserts instead of skipping, so the member keeps its plain type.
    @assert(p!.count == 2)
    @assert(p!.next!.count == 7)

    // '?.' skips the access when null; 'orelse' provides the scalar fallback.
    // 'orelse' binds loosely, so the comparison needs the parentheses.
    @assert((p?.count orelse -1) == 2)
    @assert((p?.next?.count orelse -1) == 7)

    // A nullable-capable chain result carries the null outcome itself.
    let tail = p?.next
    @assert(tail != null)

    p = null
    @assert((p?.count orelse -1) == -1)
    @assert(p?.next == null)
}

/**
# Nullability Through a Reference

A reference is transparent, so a binding to a nullable slot — what a container's `opIndex`
hands back — is exactly as unproven as the slot it names. Every use site looks through the
reference layer: reaching a member, dereferencing, indexing and calling through such a
binding all need the same proof they would need on the slot itself, and the postfix `!`
strips the nullability inside the reference so what follows reads the object.
*/
struct RefSlotDoc
{
    count: s64
}

alias RefSlot = #null *RefSlotDoc

struct RefSlotBoxDoc
{
    slot: RefSlot
}

impl RefSlotBoxDoc
{
    // What a container's 'opIndex' hands back: a reference to a nullable slot.
    mtd const at()->const &RefSlot => &.slot
}

#test
{
    var target: RefSlotDoc
    target.count = 3
    var box      = RefSlotBoxDoc{slot: &target}

    // The binding keeps the reference, and the slot's '#null' with it.
    let bound = box.at()
    #assert(#typeof(bound) == #type const &RefSlot)

    // 'bound.count' would be rejected: the slot can still be null.
    @assert(bound!.count == 3)
    @assert((dref bound!).count == 3)
}

/**
# Deferred Initialization with `Swag.Late`

The `Swag.Late` attribute declares a **non-null** field or **global variable** whose storage
starts unset (zero/null) and receives its value during setup — an initialization function,
a constructor, the first stage of `main`. It replaces the `#null ... = null` +
`!`-at-every-use pattern for values that are guaranteed to be set before first use but
cannot be initialized at their declaration.

The exposed type is non-null, so uses need no `!`; every read is guarded (a runtime
null panic when still unset). `@isset` tests whether the value has been assigned, without
reading it. `Swag.Late` needs a nullable-capable type (pointer, slice, `string`, `cstring`,
interface, function): it uses the null bit pattern as the 'unset' sentinel. A local or
parameter uses `= undefined` definite assignment instead.
*/
struct LateDocResource
{
    weight: s32
}

var g_lateDocStorage: LateDocResource

#[Swag.Late]
var g_lateDocResource: *LateDocResource     // non-null type, set later

func setupLateDocResource()
{
    g_lateDocStorage.weight = 5
    g_lateDocResource       = &g_lateDocStorage
}

#test
{
    // The type is non-null: no '!', no null test needed at the use site.
    #assert(#typeof(g_lateDocResource) == *LateDocResource)

    // Unset until setup runs, and '@isset' says so without reading the value.
    @assert(!@isset(g_lateDocResource))
    setupLateDocResource()
    @assert(@isset(g_lateDocResource))

    // Guarded read yields the value directly.
    @assert(g_lateDocResource.weight == 5)
}

/**
# Taking the Address of a Variable

The `&` operator returns the **address** of a variable, producing a pointer to it.
This allows you to access or modify a variable indirectly via its memory address.
*/
#test
{
    var value = 1
    let ptr   = &value
    @assert(#nameof(#typeof(ptr)) == "*s32")     // The pointer type matches the variable's type
}

/**
# Dereferencing a Pointer

To access the value stored at a pointer’s address, use the `dref` intrinsic.
Dereferencing retrieves the data located at the memory address referenced by the pointer.
*/
#test
{
    var value = 42
    let ptr   = &value
    @assert(dref ptr == 42)     // Access the value stored at the pointer
}

/**
# Pointers to Const Data

`const` qualifies the **pointed-to data**, never the pointer itself. Written just before
a `*`, it makes whatever that `*` points to read-only, so `const *u8` is a pointer to a
read-only `u8` and assigning through `dref` is rejected. The pointer variable stays free
to point somewhere else; `let` is what makes a pointer itself immutable.
*/
#test
{
    let str            = "string"
    let ptr: const *u8 = @dataof(str)
    @assert(dref ptr == 's')     // Reading through the pointer is fine,
// but assigning to 'dref ptr' would be rejected
}

/**
# Combining `const` with Pointers

Every `*` in a type carries its own `const`, so read-only access is chosen level by
level. Read the type from left to right: each `const` applies to the pointee of the `*`
that follows it, exactly one level down.
*/
#test
{
    var ptr:  #null *#null const *u8           // The 'u8' is read-only, the inner pointer is writable
    var ptr1: #null const *#null const *u8     // Both the inner pointer and the 'u8' are read-only
    var ptr2: #null const *#null *u8           // The inner pointer is read-only, the 'u8' is writable
}

/**
# Multi-Value Pointers

To enable **pointer arithmetic** or reference **contiguous memory blocks**,
use `[*]` instead of `*`.

This type of pointer behaves like a view over multiple elements,
allowing indexed access and pointer movement through memory.
*/
#[Swag.Sanity(Swag.SafetyWhat.All, false)]
#test
{
    var ptr: #null [*] u8     // Pointer to a block of 'u8' values
    ptr = ptr - 1             // Move the pointer back by one element
}

/**
# Pointer Arithmetic and Array Elements

When taking the address of an array element, the resulting pointer refers to that
single element. Cast it to a multi-value pointer when pointer arithmetic is intended.
*/
#test
{
    var arr: [4] s32
    var ptr = cast([*] s32) &arr[1]

    // The pointer is treated as a multi-value pointer
    ptr = ptr - 1
    #assert(#typeof(ptr) == [*] s32)
}

/**
# Dereferencing with Indexing

When pointer arithmetic is available, you can dereference a pointer using indexes,
just like accessing elements in an array.

This is particularly useful when traversing arrays or buffers via pointers.
*/

#test
{
    var arr = [1, 2, 3, 4]
    let ptr = cast([*] s32) &arr[0]
    @assert(#typeof(ptr) == [*] s32)
    let value1 = ptr[0]
    @assert(value1 == 1)
    #assert(#typeof(value1) == s32)
    let value2 = ptr[1]
    @assert(value2 == 2)
    #assert(#typeof(value2) == s32)
    let value = dref ptr
    @assert(value == 1)
    #assert(#typeof(value) == s32)
}

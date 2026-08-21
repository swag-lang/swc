#global private

/**
# Single-Value Pointers

A pointer to a **single element** is declared using the `*` symbol.
It represents the memory address of one instance of a given type.

Pointers can address any type of data and are fundamental for efficient memory access and manipulation.
*/
#test
{
    var ptr1: #null *u8            // Pointer to a single 'u8' value
    var ptr2: #null *#null *u8     // Pointer to another pointer to 'u8'
}

/**
# Null Pointers

In Swag, a pointer can be `null`, meaning it does not refer to any valid memory location.
Null pointers are often used to indicate uninitialized or intentionally absent values.

It is good practice to check for null pointers before dereferencing them to avoid runtime errors.
*/
#test
{
    var ptr1: #null *u8
    @assert(ptr1 == null)     // Uninitialized pointers are null by default
}

/**
# Non-Null by Default

Nullable-capable types â€” single-value and block pointers, slices, `string`, `cstring`,
`any`, and `typeinfo` â€” are non-null by default: a bare `*u8` or `string` cannot be
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
produce an absent result, what follows keeps its plain type â€” `node!.count` is an `s64`,
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
# Reaching Through a Pointer

A non-null `*T` needs no ceremony at the use site. A member access written on the
pointer reads the pointed-to object directly, and a method call binds the pointed-to
object as its receiver. The postfix `[]` opens the **whole value**: reading it out in
one expression, or replacing it in one assignment. Field for field, the code looks the
same whether a binding holds the object or its address, which is what makes `*T` the
everyday indirection.
*/
struct ReachDoc
{
    x, y: s32
}

impl ReachDoc
{
    mtd shift(dx: s32)
    {
        .x += dx
    }
}

#test
{
    var value = ReachDoc{1, 2}
    let ptr   = &value

    // Members are reached directly through the pointer.
    @assert(ptr.x == 1)
    ptr.y = 20
    @assert(value.y == 20)

    // A method call binds the pointed-to object as its receiver.
    ptr.shift(10)
    @assert(value.x == 11)

    // '[]' reads or replaces the whole pointed value.
    let copy = ptr[]
    @assert(copy.y == 20)
    ptr[] = ReachDoc{7, 8}
    @assert(value.x == 7)
}

/**
# Element Addresses from Containers

Indexing reaches through a pointer the same way: when a `*T` points to a value with
index operators, indexing the pointer indexes the pointed-to container. And a
container hands out the address of one of its elements through the `opIndexPtr`
hook: `&c[i]` is a plain non-null pointer into the container's storage, and
`c[i].field = x` or `c[i] += 1` writes the element in place. The operator
overloading chapter describes when each index hook is selected.
*/
struct ElemBoxDoc
{
    values: [4] s32
}

impl ElemBoxDoc
{
    mtd opIndexPtr(index: u64)->*s32
    {
        return &.values[index]
    }
}

#test
{
    var box: ElemBoxDoc

    // Without a dedicated write operator, assignments go through the element address.
    box[0] = 41
    box[0] += 1
    @assert(box.values[0] == 42)

    // The element address escapes as a plain pointer and stays writable.
    let p = &box[1]
    #assert(#typeof(p) == *s32)
    p[] = 7
    @assert(box.values[1] == 7)

    // Indexing through a pointer to the container reaches the same hooks.
    let boxPtr = &box
    boxPtr[2] = 5
    @assert(box.values[2] == 5)
}

/**
# Pointers to Nullable Slots

Taking an address never invents a proof. The address of a `#null` slot is a non-null
pointer TO that slot, and the slot's own nullability waits inside: reading the slot
with `[]` hands back the `#null` value, and every use of that value needs the same
proof it would need on the slot itself.
*/
struct SlotTargetDoc
{
    count: s64
}

alias DocSlot = #null *SlotTargetDoc

struct SlotBoxDoc
{
    slot: DocSlot
}

impl SlotBoxDoc
{
    // What a container's 'opIndexPtr' hands back: the address of a slot that can be null.
    mtd slotPtr()->*DocSlot => &.slot
}

#test
{
    var target: SlotTargetDoc
    target.count = 3
    var box = SlotBoxDoc{slot: &target}

    // The address itself is non-null; the slot's '#null' waits behind one '[]'.
    let bound = box.slotPtr()
    #assert(#typeof(bound) == #type *DocSlot)

    // The slot's value is still nullable: prove it, or assert it with '!'.
    let slot = bound[]
    @assert(slot!.count == 3)

    // Writing through the address updates the slot itself.
    bound[] = null
    @assert(box.slot == null)
}

/**
# Deferred Initialization with `Swag.Late`

The `Swag.Late` attribute declares a **non-null** field or **global variable** whose storage
starts unset (zero/null) and receives its value during setup â€” an initialization function,
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

To access the value stored at a pointer's address, write `[]` after the pointer:
empty brackets open the pointed storage as a read/write place. Being postfix, the
dereference composes left-to-right with member and index access, so a chain stays
readable without parentheses.
*/
#test
{
    var value = 42
    let ptr   = &value
    @assert(ptr[] == 42)     // Reads the value stored at the pointer
    ptr[] = 7                // Replaces the whole pointed value
    @assert(value == 7)

    // Being postfix, it chains without parentheses.
    var grid: [2, 3] s32
    let gp = &grid
    gp[][1, 2] = 5
    @assert(grid[1, 2] == 5)
}

/**
# Reinterpreting the Pointed Storage

`expr[as T]` opens the same place but types it as a `T`: the pointed storage is
reinterpreted, never converted. The result is a read/write place of type `T`, so both
reads and writes go through it. The classic use is reaching the bit pattern of a value
without a chain of pointer casts.
*/
#test
{
    var f = 1.0'f32
    let p = &f
    @assert(p[as u32] == 0x3F80_0000)     // The float's bit pattern, not a conversion

    var value = 0's32
    let vp    = &value
    vp[as u32] = 0xFFFF_FFFF     // Writes through the reinterpreted place
    @assert(value == -1)
}

/**
`[as T]` opens **one** place, so a following index applies to that `T` and not to a
buffer of them: `p[as u32][2]` asks a `u32` to be indexed. To walk a buffer under a
different lane type, reinterpret the pointer instead — `(cast([*] T) p)[i]` is the
spelling to use. An array shape works too, and keeps the reinterpretation postfix when
the element count is known: `p[as [4] u32][1]` names the second word of the first four.
*/
#test
{
    var bytes: [16] u8
    for i in 16 do
        bytes[i] = cast(u8) i

    // Walk the same storage as four words.
    let words = cast([*] u32) @dataof(bytes)
    @assert(words[0] == 0x0302_0100)
    @assert(words[1] == 0x0706_0504)

    // Or name a fixed shape in one postfix step.
    let p = @dataof(bytes)
    @assert(p[as [4] u32][1] == 0x0706_0504)
}

/**
# Pointers to Const Data

`const` qualifies the **pointed-to data**, never the pointer itself. Written just before
a `*`, it makes whatever that `*` points to read-only, so `const *u8` is a pointer to a
read-only `u8` and assigning through `[]` is rejected. The pointer variable stays free
to point somewhere else; `let` is what makes a pointer itself immutable.
*/
#test
{
    let str            = "string"
    let ptr: const *u8 = @dataof(str)
    @assert(ptr[] == 's')     // Reading through the pointer is fine,
// but assigning to 'ptr[]' would be rejected
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

To enable **pointer arithmetic** or address **contiguous memory blocks**,
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
    let value = ptr[]
    @assert(value == 1)
    #assert(#typeof(value) == s32)
}

#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-843 - Access of resource using incompatible type
//
// Storage is read as a type it does not hold. The read is in bounds for the type it claims
// and out of bounds for the object that is really there, which is why this class turns a
// small object into a large one and a integer into a pointer.
//
// Swag: the DYNAMIC form is checked - 'any' remembers its concrete type and a mismatched
// extraction panics under '.DynCast', and an interface knows what it was built from. The
// STATIC form is not: a reinterpreting cast between unrelated pointee types, and a read of a
// union member that was not the one written, are both accepted with no marker of any kind.
// -----------------------------------------------------------------------------

struct Small
{
    a: s32
}

struct Large
{
    a, b, c, d: s64
}

union Bits
{
    number:  u64
    pointer: *s32?
}

// --- Faults ---

// The dynamic form: 'any' carries its type and the extraction is checked. The value arrives
// as a parameter so the concrete type is only known through the box.
#[Swag.Safety(.DynCast, true)]
func extractWrongTypeFromAny(boxed: any)->s32
{
    return cast(s32) boxed     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run extractWrongTypeFromAny("text")
}

// GAP compiler.safety.006 - a reinterpreting cast between unrelated pointee types is
// accepted, and the read that follows is in bounds for 'Large' and far past the end of
// 'Small'. No diagnostic, no guard, no marker. Left commented because it really does read
// out of bounds.
//
// func readSmallAsLarge()->s64
// {
//     var small: Small
//     let wide = cast(*Large) &small
//     return wide.d          // reads 24 bytes past a 4-byte object
// }

// GAP compiler.safety.006 - reading the union member that was not written turns an integer
// into a pointer with no cast at all: the widest route on the unsafe surface, and the one
// that needs no ceremony whatsoever. See language.design.002 for the tagged form that would
// remove it rather than gate it. Left commented because it really does forge a pointer.
//
// func forgePointerThroughUnion()->s32
// {
//     var bits: Bits
//     bits.number = 0x4142434445
//     return bits.pointer![]     // dereferences an address that was never an address
// }

// --- Sound ---

// The matching extraction is what the guard lets through.
#[Swag.Safety(.DynCast, true)]
func extractRightTypeFromAny(boxed: any)->s32
{
    return cast(s32) boxed
}

// 'Swag.kindOf' asks the question instead of asserting the answer.
func inspectAnyKind()->bool
{
    var value      = 42's32
    let boxed: any = Swag.makeAny(&value, s32)
    return Swag.kindOf(boxed) == s32
}

// Reading the union member that WAS written is the defined use, and must stay silent.
func readWrittenUnionMember()->u64
{
    var bits: Bits
    bits.number = 0x4142434445
    return bits.number
}

#test
{
    Swag.assert(extractRightTypeFromAny(42's32) == 42)
    Swag.assert(inspectAnyKind())
    Swag.assert(readWrittenUnionMember() == 0x4142434445)
}

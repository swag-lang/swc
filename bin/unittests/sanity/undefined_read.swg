#global private

// '= undefined' skips a local's initialization. That is an optimization contract: the
// variable must be written before it is read. Three nets catch violations:
// - the SEMA definite-assignment analysis: any read not provably preceded by an
//   initialization on every path is a compile-time error (sema_err_undefined_use);
// - 'Swag.Sanity(.Lifecycle)', the static backend check: catches proven reads the
//   sema analysis had to give up on (address escapes, out-parameter fills that the
//   callee does not actually perform);
// - 'Swag.Safety(.Lifecycle)', the runtime poisoning: the storage is filled with 0xDD
//   at the declaration, so an unproven read sees a deterministic poison instead of
//   whatever the frame happened to hold.

struct UndItem
{
    x: u32
    y: u32
}

var g_undSink: u32

// An opaque touch: taking the address counts as an initialization for the sema
// analysis, and the call makes the static backend check conservatively forget the
// undefined range (out-parameter fills). The poison written at the declaration is
// untouched, which lets the runtime tests below observe the 0xDD pattern.
func undOpaqueTouch(v: *UndItem)
{
    g_undSink += 1
    discard v
}

func undFill(v: *UndItem)
{
    v.x = 7
    v.y = 8
}

// ---------------------------------------------------------------------------
// Definite assignment: proven reads of '= undefined' storage are sema errors.
// ---------------------------------------------------------------------------

// Reading a field of an '= undefined' struct before any store.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    @assert(a.x == 1) // swc-expected-error {{sema_err_undefined_field_use}}
}

// Reading the second field: the whole declared range is undefined.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    @assert(a.y == 2) // swc-expected-error {{sema_err_undefined_field_use}}
}

// The captme shape: a pointer declared '= undefined' tested as a guard before any
// assignment reads uninitialized storage.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var item: UndItem
    var last: #null *UndItem = undefined
    if last do // swc-expected-error {{sema_err_undefined_use}}
        g_undSink += 1
    last = &item
    discard last
}

// Taking an address is conservatively treated as initialization by sema because an
// out-parameter may fill the value. Without a call, the backend can still prove that
// no write occurred and pinpoints the first actual read.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    let address = &a
    discard address
    @assert(a.x == 1) // swc-expected-error {{sanity_err_undefined_read}}
}

// ---------------------------------------------------------------------------
// Valid programs: must NOT be flagged.
// ---------------------------------------------------------------------------

// Assigning before reading is the intended use of '= undefined'.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    a.x = 5
    a.y = 6
    @assert(a.x == 5)
    @assert(a.y == 6)
}

// Filling through an out-parameter initializes the storage.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    undFill(&a)
    @assert(a.x == 7)
    @assert(a.y == 8)
}

// A store on every path is definitely assigned at the join.
var g_undTakeBranch = false

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    if g_undTakeBranch do
        a.x = 1
    else do
        a.x = 2
    @assert(a.x == 2)
}

// ---------------------------------------------------------------------------
// Runtime poison: reads no static net can prove see 0xDD deterministically.
// ---------------------------------------------------------------------------

// The address escape silences both static nets, but nothing was written: the
// poison filled at the declaration is still there.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    undOpaqueTouch(&a)
    @assert(a.x == 0xDDDDDDDD)
    @assert(a.y == 0xDDDDDDDD)
}

// A filled variable reads back its stores, poison long overwritten.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    a.x = 11
    a.y = 12
    undOpaqueTouch(&a)
    @assert(a.x == 11)
    @assert(a.y == 12)
}

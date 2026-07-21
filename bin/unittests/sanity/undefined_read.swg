#global private

// '= undefined' skips a local's initialization. That is an optimization contract: the
// variable must be written before it is read. Two nets catch violations:
// - 'Swag.Sanity(.Lifecycle)', the static check: a PROVEN read of the untouched
//   storage (on every path, no call in between) is a compile-time error;
// - 'Swag.Safety(.Lifecycle)', the runtime poisoning: the storage is filled with 0xDD
//   at the declaration, so a read the static check cannot prove (first loop iteration,
//   opaque-call barriers) sees a deterministic poison instead of whatever the frame
//   happened to hold.

struct UndItem
{
    x: u32
    y: u32
}

var g_undSink: u32

// An opaque call: the static check conservatively forgets undefined ranges across
// calls (out-parameter fills), which lets the runtime-poison tests below observe the
// 0xDD pattern.
func undOpaque()
{
    g_undSink += 1
}

func undFill(v: *UndItem)
{
    v.x = 7
    v.y = 8
}

// ---------------------------------------------------------------------------
// Static check: proven reads of '= undefined' storage.
// ---------------------------------------------------------------------------

// Reading a field of an '= undefined' struct before any store.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    @assert(a.x == 1) // swc-expected-error {{sanity_err_undefined_read}}
}

// Reading the second field: the whole declared range is undefined.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    @assert(a.y == 2) // swc-expected-error {{sanity_err_undefined_read}}
}

// The captme shape: a pointer declared '= undefined' tested as a guard before any
// assignment reads uninitialized storage.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var item: UndItem
    var last: #null *UndItem = undefined
    if last do // swc-expected-error {{sanity_err_undefined_read}}
        g_undSink += 1
    last = &item
    discard last
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

// A store on only one path is not a proven undefined read at the join.
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
// Runtime poison: reads the static check cannot prove see 0xDD deterministically.
// ---------------------------------------------------------------------------

// The opaque call clears the static knowledge, but the poison filled at the
// declaration is still there.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a: UndItem = undefined
    undOpaque()
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
    undOpaque()
    @assert(a.x == 11)
    @assert(a.y == 12)
}

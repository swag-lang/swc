#global private

// 'SafetyWhat.Lifecycle' has two halves:
// - a static sanitizer check: a PROVEN read of a local abandoned by '#move'/'#relocate'
//   (moved-from and not reset) is reported at compile time;
// - runtime poisoning: abandoned or dropped storage is filled with 0xDD, so an access
//   the static check cannot prove fails deterministically instead of reading stale bits.
// A '#move' of a type with 'opDrop' is NOT concerned: the source is reset to its
// default value, which is defined behavior.

struct UamItem
{
    x: u32
    y: u32
}

struct UamDropped
{
    x: u32 = 9
}

impl UamDropped
{
    mtd opDrop() {}
}

var g_sink: u32

// An opaque call: the static check conservatively forgets moved-from ranges across
// calls, which lets the runtime-poison tests below observe the 0xDD pattern.
func opaque()
{
    g_sink += 1
}

#[Swag.Safety(.Lifecycle, false)]
func lifecycleSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Lifecycle)
}

#[Swag.Safety(.Lifecycle, true)]
func lifecycleSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Lifecycle)
}

#test
{
    @assert(lifecycleSafetyDisabled() == false)
    @assert(lifecycleSafetyEnabled() == true)
}

// ---------------------------------------------------------------------------
// Static check: proven reads of moved-from locals.
// ---------------------------------------------------------------------------

// Reading a local abandoned by '#relocate'.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 1}
    var b: UamItem
    b = #relocate a
    @assert(a.x == 1) // swc-expected-error {{safety_err_use_after_move}}
}

// Reading a non-first field of the abandoned local.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 1, y: 2}
    var b: UamItem
    b = #relocate a
    @assert(a.y == 2) // swc-expected-error {{safety_err_use_after_move}}
}

// Reading a local given away with '#move' when the type has no 'opDrop': the source is
// not reset, its stale bits are abandoned.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 4}
    var b = #move a
    @assert(a.x == 4) // swc-expected-error {{safety_err_use_after_move}}
}

// ---------------------------------------------------------------------------
// Valid programs: must NOT be flagged.
// ---------------------------------------------------------------------------

// Reassigning the moved-from local makes it readable again.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 1}
    var b: UamItem
    b = #relocate a
    a = UamItem{x: 5}
    @assert(a.x == 5)
    @assert(b.x == 1)
}

// '#move' of a type with 'opDrop' resets the source to its defaults: reading it is
// defined behavior and is not flagged.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamDropped{x: 3}
    var b = #move a
    @assert(b.x == 3)
    @assert(a.x == 9)
}

// A move on only one path is not a proven use-after-move at the join.
var g_takeBranch = false

#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 1}
    var b: UamItem
    if g_takeBranch do
        b = #relocate a
    @assert(a.x == 1)
}

// ---------------------------------------------------------------------------
// Runtime poisoning: when the static check cannot prove the read (an opaque call in
// between), the abandoned storage is observed as 0xDD bytes.
// ---------------------------------------------------------------------------

#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 1}
    var b: UamItem
    b = #relocate a
    opaque()
    @assert(a.x == 0xDDDD_DDDD)
    @assert(b.x == 1)
}

#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamItem{x: 6}
    var b = #move a // no 'opDrop': the abandoned source is poisoned
    opaque()
    @assert(a.x == 0xDDDD_DDDD)
    @assert(b.x == 6)
}

// '@drop' poisons the dropped storage; the caller re-initializes it before reuse.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UamDropped{x: 3}
    @drop(&a)
    opaque()
    @assert(a.x == 0xDDDD_DDDD)
    @init(&a)
    @assert(a.x == 9)
}

// ---------------------------------------------------------------------------
// Disabled: raw abandonment semantics, no poison, no static check.
// ---------------------------------------------------------------------------

#[Swag.Safety(.Lifecycle, false)]
#test
{
    var a = UamItem{x: 3}
    var b: UamItem
    b = #relocate a
    @assert(a.x == 3) // stale bits are still readable when the check is off
    @assert(b.x == 3)
}

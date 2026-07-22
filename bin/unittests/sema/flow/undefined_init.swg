#global private

// Definite-assignment analysis for '= undefined' locals: reads, drops and error
// unwinds must see an initialized value. Runtime behavior (drop elision on first
// assignment) is covered in unittests/jit/flow/undefined_init.swg.

var g_UndDropCount: s32

struct UndDrop
{
    value: s32
}

impl UndDrop
{
    mtd opDrop()
    {
        g_UndDropCount += 1
    }
}

func mkUndDrop(v: s32)->UndDrop
{
    var result: retval
    result.value = v
    return result
}

struct UndPod
{
    a: s32
    b: s32
    c: s32
}

enum UndKind
{
    First
    Second
}

func undBoom() throw
{
    throw Swag.BaseError{"boom"}
}

// -----------------------------------------------------------------------------
// Accepted patterns: every path initializes before any use.
// -----------------------------------------------------------------------------

// if/else covering both paths.
func undOkIfElse(c: bool)->s32
{
    var x: s32 = undefined
    if c do
        x = 1
    else do
        x = 2
    return x
}

// Complete switch over an enum, no default.
func undOkCompleteSwitch(kind: UndKind)->s32
{
    var x: s32 = undefined
    #[Swag.Complete]
    switch kind
    {
    case First:
        x = 1
    case Second:
        x = 2
    }
    return x
}

// Switch with a default.
func undOkDefaultSwitch(v: s32)->s32
{
    var x: s32 = undefined
    switch v
    {
    case 0:
        x = 1
    default:
        x = 2
    }
    return x
}

// Partial init of a plain-POD struct, then a whole copy (intentional: the
// unwritten fields are never read).
func undTakePod(p: UndPod)->s32 => p.a

func undOkPartialPodCopy()->s32
{
    var p: UndPod = undefined
    p.a = 1
    p.b = 2
    return undTakePod(p)
}

// Field-wise init of a retval, vector style.
func undOkRetvalFields()->UndPod
{
    var result: retval = undefined
    result.a = 1
    result.b = 2
    result.c = 3
    return result
}

// 'with' on an undefined retval, transform2 style.
func undOkWithRetval()->UndPod
{
    with var result: retval = undefined
    {
        .a = 1
        .b = 2
        .c = 3
    }
    return result
}

// -----------------------------------------------------------------------------
// Rejected patterns.
// -----------------------------------------------------------------------------

// Read before any initialization.
func undErrPlainRead()->s32
{
    var x: s32 = undefined
    return x // swc-expected-error {{sema_err_undefined_use}}
}

// Initialized on one path only.
func undErrHalfInit(c: bool)->s32
{
    var x: s32 = undefined
    if c do
        x = 1
    return x // swc-expected-error {{sema_err_undefined_use}}
}

// Incomplete switch without default.
func undErrSwitchNoDefault(v: s32)->s32
{
    var x: s32 = undefined
    switch v
    {
    case 0:
        x = 1
    case 1:
        x = 2
    }
    return x // swc-expected-error {{sema_err_undefined_use}}
}

// Compound assignment reads the destination.
func undErrCompound()
{
    var x: s32 = undefined
    x += 1 // swc-expected-error {{sema_err_undefined_use}}
}

// Reading a field that was never assigned.
func undErrFieldRead()->s32
{
    var p: UndPod = undefined
    p.a = 1
    return p.b // swc-expected-error {{sema_err_undefined_field_use}}
}

// Whole read of a fully untouched POD struct.
func undErrWholePodRead()->s32
{
    var p: UndPod = undefined
    return undTakePod(p) // swc-expected-error {{sema_err_undefined_use}}
}

// A droppable declared '= undefined' and possibly initialized cannot be
// reassigned: the compiler can neither drop nor skip the drop.
func undErrMaybeReassign(c: bool)
{
    var v: UndDrop = undefined
    if c do
        v = mkUndDrop(1)
    v = mkUndDrop(2) // swc-expected-error {{sema_err_undefined_drop}}
}

// First assignment inside a loop: later iterations hold a real value, the
// first one holds garbage.
func undErrLoopAssign()
{
    var v: UndDrop = undefined
    for 3 do
        v = mkUndDrop(1) // swc-expected-error {{sema_err_undefined_drop}}
}

// An error unwind would drop the still-uninitialized droppable.
func undErrUnwind() throw
{
    var v: UndDrop = undefined
    try undBoom() // swc-expected-error {{sema_err_undefined_drop}}
    v = mkUndDrop(1)
}

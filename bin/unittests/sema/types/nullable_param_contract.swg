#global private

// A parameter declared '#null' advertises that callers may pass null. When the
// body's FIRST use of that parameter, on every path to an exit, is an operation
// that requires a valid runtime address (dereference, member access, indexing,
// call), no call with null can survive: the signature promises what the body
// forbids. This is proven, so it is a compile-time error. Any other first use
// (null test, copy, argument, 'notnull') disarms the check.

struct NpcItem
{
    value: s32
}

interface INpcFace
{
    mtd get()->s32;
}

var g_npcSink: s32

func npcBoom() throw
{
    throw Swag.BaseError{"boom"}
}

func npcCheck(x: #null *s32)->bool => x != null

// -----------------------------------------------------------------------------
// Dead contracts: rejected.
// -----------------------------------------------------------------------------

func npcErrDeref(x: #null *s32)->s32 // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return dref x
}

func npcErrMember(v: #null *NpcItem)->s32 // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return v.value
}

func npcErrIndex(s: #null [*] s32)->s32 // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return s[0]
}

func npcErrCall(f: #null func()->s32)->s32 // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return f()
}

func npcErrInterface(i: #null INpcFace)->s32 // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return i.get()
}

// -----------------------------------------------------------------------------
// Honored contracts: accepted.
// -----------------------------------------------------------------------------

// Null test first.
func npcOkGuarded(x: #null *s32)->s32
{
    if x == null do
        return 0
    return dref x
}

// Truthiness guard first.
func npcOkTruthGuard(v: #null *NpcItem)->s32
{
    if !v do
        return 0
    return v.value
}

// Explicit 'notnull' assertion: the caller-visible contract moves to a runtime
// panic, which is a deliberate choice.
func npcOkAsserted(v: #null *NpcItem)->s32
{
    return (notnull v).value
}

// The first use hands the parameter to someone else: the body cannot be proven
// fatal for null.
func npcOkDelegated(x: #null *s32)->s32
{
    if !npcCheck(x) do
        return 0
    return dref x
}

// A throwing exit can leave the function before the dereference.
func npcOkThrowFirst(x: #null *s32)->s32 throw
{
    try npcBoom()
    return dref x
}

// Dereference on one branch only: some executions never touch the parameter.
func npcOkConditional(x: #null *s32, use: bool)->s32
{
    if use do
        return dref x
    return 0
}

// Never used at all.
func npcOkUnused(x: #null *s32)->s32
{
    return 1
}

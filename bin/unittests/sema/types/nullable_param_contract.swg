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

func npcErrDeref(x: #null *s32)->s32     // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return dref x
}

func npcErrMember(v: #null *NpcItem)->s32     // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return v.value
}

func npcErrIndex(s: #null [*] s32)->s32     // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return s[0]
}

func npcErrCall(f: #null func()->s32)->s32     // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return f()
}

func npcErrInterface(i: #null INpcFace)->s32     // swc-expected-error {{sema_err_nullable_param_contract}}
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

// -----------------------------------------------------------------------------
// Return contracts: a '#null' return type that no return path can produce is
// the dual dead contract.
// -----------------------------------------------------------------------------

var g_npcStorage: s32

func npcErrReturnNeverNull(c: bool)->#null *s32     // swc-expected-error {{sema_err_nullable_return_contract}}
{
    if c do
        return &g_npcStorage
    return &g_npcStorage
}

// An explicit null return keeps the contract alive.
func npcOkReturnNull(c: bool)->#null *s32
{
    if c do
        return null
    return &g_npcStorage
}

// Returning a nullable value keeps it alive too.
func npcOkReturnNullable(x: #null *s32)->#null *s32
{
    return x
}

// A throwable function is exempt: its 'catch' error path synthesizes null.
func npcOkReturnThrowable()->#null *s32 throw
{
    if g_npcStorage == 0 do
        throw Swag.BaseError{"boom"}
    return &g_npcStorage
}

// -----------------------------------------------------------------------------
// Local contracts: a '#null' local whose every value is provably non-null wears
// a dead qualifier.
// -----------------------------------------------------------------------------

func npcMayNull()->#null *s32 => null

func npcFillPtrPtr(pp: *#null *s32)
{
    dref pp = null
}

func npcErrLocalNeverNull()->s32
{
    var p: #null *s32 = &g_npcStorage     // swc-expected-error {{sema_err_nullable_local_contract}}
    return dref p
}

// No initializer: the local defaults to null.
func npcOkLocalDefaultsNull(use: bool)->s32
{
    var p: #null *s32
    if use do
        p = &g_npcStorage
    return p == null ? 0 : dref p
}

// Reassigned with a possibly-null value.
func npcOkLocalNullableValue()->s32
{
    var p: #null *s32 = &g_npcStorage
    p = npcMayNull()
    return p == null ? 0 : dref p
}

// Explicit null assignment.
func npcOkLocalNullAssign(c: bool)->s32
{
    var p: #null *s32 = &g_npcStorage
    if c do
        p = null
    return p == null ? 0 : dref p
}

// Address escape: the callee may store null through it.
func npcOkLocalEscaped()->s32
{
    var p: #null *s32 = &g_npcStorage
    npcFillPtrPtr(&p)
    return p == null ? 0 : dref p
}

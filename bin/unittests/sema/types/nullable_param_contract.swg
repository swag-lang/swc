#global private

// A parameter declared '#null' advertises that callers may pass null. Every
// unguarded dereference of such a parameter (dereference, member access, indexing,
// call) is rejected AT THE USE SITE: the deref is an error on its own node, so no
// separate whole-function "dead parameter contract" verdict is needed. The honored
// patterns below show the sanctioned proofs (null test, 'notnull', delegation,
// throwing exit, conditional). The return-contract and local-contract checks are
// independent — a deref cannot subsume them — and are exercised at the end.

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

func npcErrDeref(x: #null *s32)->s32
{
    return dref x     // swc-expected-error {{sema_err_nullable_deref}}
}

func npcErrMember(v: #null *NpcItem)->s32
{
    return v.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

func npcErrIndex(s: #null [*] s32)->s32
{
    return s[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func npcErrCall(f: #null func()->s32)->s32
{
    return f()     // swc-expected-error {{sema_err_nullable_call}}
}

func npcErrInterface(i: #null INpcFace)->s32
{
    return i.get()     // swc-expected-error {{sema_err_nullable_member_access}}
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
// fatal for null. The dereference itself still needs its own local proof.
func npcOkDelegated(x: #null *s32)->s32
{
    if !npcCheck(x) do
        return 0
    if x == null do
        return 0
    return dref x
}

// A throwing exit can leave the function before the dereference.
func npcOkThrowFirst(x: #null *s32)->s32 throw
{
    try npcBoom()
    return dref notnull x
}

// Dereference on one branch only: some executions never touch the parameter.
func npcOkConditional(x: #null *s32, use: bool)->s32
{
    if use and x != null do
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
    if p == null do
        return 0
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

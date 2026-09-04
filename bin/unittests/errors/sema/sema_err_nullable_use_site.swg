#global private

// Use-site nullability enforcement: dereferencing a value whose type is still
// nullable (no dominating null test, no '!', no '?.') is an error, for
// every dereferencing operation: member access, '[]', indexing, and calls
// through function values.

struct NullableUseSiteItem
{
    value: s32
}

impl NullableUseSiteItem
{
    mtd touch()->s32 => .value
}

var g_nullableUseSiteStorage: s32

func nullableUseSiteMember(p: *NullableUseSiteItem?)->s32
{
    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

func nullableUseSiteMethod(p: *NullableUseSiteItem?)->s32
{
    return p.touch()     // swc-expected-error {{sema_err_nullable_member_access}}
}

func nullableUseSiteInterface(itf: IsItf?)->s32
{
    return itf.get()     // swc-expected-error {{sema_err_nullable_member_access}}
}

interface IsItf
{
    mtd get()->s32
}

func nullableUseSiteDeref(p: *s32?)->s32
{
    return p[]     // swc-expected-error {{sema_err_nullable_deref}}
}

func nullableUseSiteDerefCast(p: *s32?)->u32
{
    return p[as u32]     // swc-expected-error {{sema_err_nullable_deref}}
}

func nullableUseSiteIndexBlock(p: [*] s32?)->s32
{
    return p[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteIndexSlice(s: [..] s32?)->s32
{
    return s[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteIndexString(s: string?)->u8
{
    return s[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteCall(f: (func()->s32)?)->s32
{
    return f()     // swc-expected-error {{sema_err_nullable_call}}
}

// A pointer to a nullable slot is as unproven as the slot it names: the outer pointer
// must not smuggle the inner value past the use-site rules.
alias NullableUseSiteSlot      = *NullableUseSiteItem?
alias NullableUseSiteBlockSlot = [*] s32?
alias NullableUseSiteFnSlot    = (func()->s32)?

struct NullableUseSiteBox
{
    slot:  NullableUseSiteSlot
    block: NullableUseSiteBlockSlot
    fn:    NullableUseSiteFnSlot
}

impl NullableUseSiteBox
{
    mtd const at()->const *NullableUseSiteSlot           => &.slot
    mtd const atBlock()->const *NullableUseSiteBlockSlot => &.block
    mtd const atFn()->const *NullableUseSiteFnSlot       => &.fn
}

func nullableUseSiteThroughRef(box: *NullableUseSiteBox)->s32
{
    let bound = box.at()
    return bound[].value     // swc-expected-error {{sema_err_nullable_member_access}}
}

func nullableUseSiteDerefThroughRef(box: *NullableUseSiteBox)->NullableUseSiteItem
{
    let bound = box.at()
    return bound[][]     // swc-expected-error {{sema_err_nullable_deref}}
}

func nullableUseSiteIndexThroughRef(box: *NullableUseSiteBox)->s32
{
    let bound = box.atBlock()
    return bound[][0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteCallThroughRef(box: *NullableUseSiteBox)->s32
{
    let bound = box.atFn()
    return bound[]()     // swc-expected-error {{sema_err_nullable_call}}
}

// A guard kills the fact after reassignment: the second access is unproven again.
func nullableUseSiteKilled(p: *NullableUseSiteItem?, q: *NullableUseSiteItem?)->s32
{
    var cur = p
    if cur == null do
        return 0
    let a = cur.value
    cur = q
    return a + cur.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// An 'Swag.assert' proof is scoped to its own block and does not outlive it.
func nullableUseSiteAssertScoped(p: *NullableUseSiteItem?)->s32
{
    {
        Swag.assert(p != null)
        discard p.value
    }

    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// An assertion on another path proves nothing about this one.
func nullableUseSiteAssertOtherPath(p: *NullableUseSiteItem?, q: *NullableUseSiteItem?)->s32
{
    Swag.assert(q != null)
    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// An assignment inside a branch is a proof for that branch alone: the other path never ran it.
func nullableUseSiteAssignedInBranch(flag: bool, q: *NullableUseSiteItem)->s32
{
    var p: *NullableUseSiteItem?
    if flag do
        p = q
    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// The same holds whichever side spells the assignment.
func nullableUseSiteAssignedInElse(flag: bool, q: *NullableUseSiteItem)->s32
{
    var p: *NullableUseSiteItem?
    if flag do
        p = null
    else do
        p = q
    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

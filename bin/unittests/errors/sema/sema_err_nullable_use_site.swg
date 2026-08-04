#global private

// Use-site nullability enforcement: dereferencing a value whose type is still
// nullable (no dominating null test, no '!', no '?.') is an error, for
// every dereferencing operation: member access, 'dref', indexing, and calls
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

func nullableUseSiteMember(p: #null *NullableUseSiteItem)->s32
{
    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

func nullableUseSiteMethod(p: #null *NullableUseSiteItem)->s32
{
    return p.touch()     // swc-expected-error {{sema_err_nullable_member_access}}
}

func nullableUseSiteInterface(itf: #null IsItf)->s32
{
    return itf.get()     // swc-expected-error {{sema_err_nullable_member_access}}
}

interface IsItf
{
    mtd get()->s32
}

func nullableUseSiteDeref(p: #null *s32)->s32
{
    return dref p     // swc-expected-error {{sema_err_nullable_deref}}
}

func nullableUseSiteIndexBlock(p: #null [*] s32)->s32
{
    return p[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteIndexSlice(s: #null [..] s32)->s32
{
    return s[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteIndexString(s: #null string)->u8
{
    return s[0]     // swc-expected-error {{sema_err_nullable_index}}
}

func nullableUseSiteCall(f: #null func()->s32)->s32
{
    return f()     // swc-expected-error {{sema_err_nullable_call}}
}

// A REFERENCE to a nullable slot is as unproven as the slot it names: the reference
// layer must not smuggle the value past the use-site rules. This is what a const
// 'opIndex' hands back, so the hole was reachable from any indexed container.
alias NullableUseSiteSlot = #null *NullableUseSiteItem

struct NullableUseSiteBox
{
    slot: NullableUseSiteSlot
}

impl NullableUseSiteBox
{
    mtd const at()->const &NullableUseSiteSlot => &.slot
}

func nullableUseSiteThroughRef(box: *NullableUseSiteBox)->s32
{
    let bound = box.at()
    return bound.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// A guard kills the fact after reassignment: the second access is unproven again.
func nullableUseSiteKilled(p: #null *NullableUseSiteItem, q: #null *NullableUseSiteItem)->s32
{
    var cur = p
    if cur == null do
        return 0
    let a = cur.value
    cur = q
    return a + cur.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// An '@assert' proof is scoped to its own block and does not outlive it.
func nullableUseSiteAssertScoped(p: #null *NullableUseSiteItem)->s32
{
    {
        @assert(p != null)
        discard p.value
    }

    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// An assertion on another path proves nothing about this one.
func nullableUseSiteAssertOtherPath(p: #null *NullableUseSiteItem, q: #null *NullableUseSiteItem)->s32
{
    @assert(q != null)
    return p.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

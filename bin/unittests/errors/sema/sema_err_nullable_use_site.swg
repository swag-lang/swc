#global private

// Use-site nullability enforcement: dereferencing a value whose type is still
// nullable (no dominating null test, no 'notnull', no '?.') is an error, for
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
    mtd get()->s32;
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

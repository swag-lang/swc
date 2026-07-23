#global private

func A() {}
func A(a: s32) {}

func overloadProbe(type: typeinfo, value: string)->#null any
{
    return null
}

func(T) overloadProbe(type: const *u8, value: string, def: T)->T
{
    return def
}

#test
{
    A()
    A(10)
    A(10, 10)     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    A("a")     // swc-expected-error {{sema_err_no_overload_match}}
}

struct S {}
impl S
{
    mtd foo() {}
    mtd foo(a: s32) {}
}
#test
{
    var s: S
    s.foo()
    s.foo(10)
    s.foo("a")     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    var s: S
    S.foo(&s)
    S.foo(&s, 10)
}

#test
{
    var s: S
    S.foo(s, "a")     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    A(1.0)     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    let type = #typeof(s32)
    overloadProbe(type, "priority", 0)     // swc-expected-error {{sema_err_no_overload_match}}
}

struct NullableRefNode {}
func takesNonNullRef(r: &NullableRefNode) {}

#test
{
    // Dereferencing a `#null` pointer is allowed, but binding it to a non-null
    // reference parameter (not a UFCS receiver) stays a cast error.
    var storage: NullableRefNode
    var p:       #null *NullableRefNode = &storage
    takesNonNullRef(p)     // swc-expected-error {{sema_err_cannot_cast}}
}

// A struct marked with '#[Swag.NoCopy]' is non-copyable: the copy variant of a
// '#fwd' function is discarded at overload resolution, so calling it without '#move'
// finds no viable overload.
#[Swag.NoCopy]
struct FwdMoveOnly { x: s32 }
impl FwdMoveOnly
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

var g_fwdTarget: FwdMoveOnly

func storeFwd(v: #fwd FwdMoveOnly)
{
    g_fwdTarget = #nodrop #fwd v
}

#test
{
    var m = FwdMoveOnly{1}
    storeFwd(m)     // swc-expected-error {{sema_err_no_overload_match}}
}

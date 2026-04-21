#global fileprivate

func A() {}
func A(a: s32) {}

#test
{
    A()
    A(10)
    A(10, 10) // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    A("a") // swc-expected-error {{sema_err_no_overload_match}}
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
    s.foo("a") // swc-expected-error {{sema_err_no_overload_match}}
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
    S.foo(s, "a") // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    A(1.0) // swc-expected-error {{sema_err_no_overload_match}}
}

struct ConstMethodOverload {}
impl ConstMethodOverload
{
    #[Swag.Overload]
    mtd select()->s32 => 1

    #[Swag.Overload]
    mtd const select()->bool => true
}

#test
{
    var value = ConstMethodOverload{}
    #assert(#typeof(value.select()) == s32)
}

#test
{
    let value = ConstMethodOverload{}
    #assert(#typeof(value.select()) == bool)
}

#[Swag.ConstExpr]
func preferConcrete(x, y: u64)->u64 => x

#[Swag.ConstExpr]
func(T) preferConcrete(x, y: T)->T => y

#assert(preferConcrete(1'u64, 2'u64) == 1'u64)
#assert(preferConcrete(1'u8, 2'u8) == 2'u8)

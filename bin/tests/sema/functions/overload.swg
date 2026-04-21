#global fileprivate

func A() {}
func A(a: s32) {}

struct S {}
impl S
{
    mtd foo() {}
    mtd foo(a: s32) {}
}

#test
{
    var s: S
    S.foo(&s)
    S.foo(&s, 10)
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

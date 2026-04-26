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
    mtd select()->s32 => 1

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

#[Swag.ConstExpr]
func preferFloatLiteral(x, y: f32)->f32 => y

#[Swag.ConstExpr]
func preferFloatLiteral(x, y: f64)->f64 => y

#[Swag.ConstExpr]
func(T) preferFloatLiteral(x, y: T)->T => y

#assert(preferConcrete(1'u64, 2'u64) == 1'u64)
#assert(preferConcrete(1'u8, 2'u8) == 2'u8)
#assert(#typeof(preferFloatLiteral(0.0001, 1.0'f32)) == f32)
#assert(#typeof(preferFloatLiteral(0.0001, 1.0'f64)) == f64)

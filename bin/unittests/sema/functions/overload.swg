#global private

func A() {}
func A(_: s32) {}

struct S {}
impl S
{
    mtd foo() {}
    mtd foo(_: s32) {}
}

func semaTest001()
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

func semaTest002()
{
    var value = ConstMethodOverload{}
    #assert(#typeof(value.select()) == s32)
}

func semaTest003()
{
    let value = ConstMethodOverload{}
    #assert(#typeof(value.select()) == bool)
}

#[Swag.ConstExpr]
func preferConcrete(x, _: u64)->u64 => x

#[Swag.ConstExpr]
func(T) preferConcrete(x, y: T)->T => y

#[Swag.ConstExpr]
func preferFloatLiteral(_, y: f32)->f32 => y

#[Swag.ConstExpr]
func preferFloatLiteral(_, y: f64)->f64 => y

#[Swag.ConstExpr]
func(T) preferFloatLiteral(x, y: T)->T => y

#assert(preferConcrete(1_u64, 2_u64) == 1_u64)
#assert(preferConcrete(1_u8, 2_u8) == 2_u8)
#assert(#typeof(preferFloatLiteral(0.0001, 1.0_f32)) == f32)
#assert(#typeof(preferFloatLiteral(0.0001, 1.0_f64)) == f64)

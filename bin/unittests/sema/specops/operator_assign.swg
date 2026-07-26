#global private

struct AssignBox
{
    a: s32
    b: s32
}

impl AssignBox
{
    mtd setPair(a, b: s32)
    {
        .a = a
        .b = b
    }

    mtd(op: Swag.Operator) opAssign(value: s32)
    {
        #if op == .AddAssign do
            .setPair(.a + value, .b + value)
        #elif op == .MulAssign do
            .setPair(.a * value, .b * value)
        #else do
            #error("unsupported opAssign op [[" ++ op.symbol() ++ "]]")
    }

    mtd(op: Swag.Operator) opAssign(value: u32)
    {
        #if op == .ShlAssign do
            .setPair(.a << value, .b << value)
        #else do
            #error("unsupported opAssign op [[" ++ op.symbol() ++ "]]")
    }

    mtd(op: Swag.Operator) opAssign(other: const &AssignBox)
    {
        #if op == .AddAssign do
            .setPair(.a + other.a, .b + other.b)
        #else do
            #error("unsupported opAssign op [[" ++ op.symbol() ++ "]]")
    }
}

struct AssignHolder
{
    value: AssignBox
}

func semaTest001()
{
    var box = AssignBox{a: 1, b: 2}
    box += 3's32
    box *= 2's32
    box <<= 1'u32

    let rhs = AssignBox{a: 5, b: 7}
    box += rhs

    #assert(#typeof(box) == AssignBox)
}

func semaTest002()
{
    var holder = AssignHolder{}
    holder.value += 4's32
}

func semaTest003()
{
    var box = AssignBox{}
    let ptr = &box
    dref ptr += 9's32
}

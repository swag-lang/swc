#global fileprivate

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

    #[Swag.Overload]
    mtd(op: string) opAssign(value: s32)
    {
        #if op == "+=" do
            .setPair(.a + value, .b + value)
        #elif op == "*=" do
            .setPair(.a * value, .b * value)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    mtd(op: string) opAssign(value: u32)
    {
        #if op == "<<=" do
            .setPair(.a << value, .b << value)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    mtd(op: string) opAssign(other: const &AssignBox)
    {
        #if op == "+=" do
            .setPair(.a + other.a, .b + other.b)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }
}

struct AssignHolder
{
    value: AssignBox
}

#test
{
    var box = AssignBox{a: 1, b: 2}
    box += 3's32
    box *= 2's32
    box <<= 1'u32

    let rhs = AssignBox{a: 5, b: 7}
    box += rhs

    #assert(#typeof(box) == AssignBox)
}

#test
{
    var holder = AssignHolder{}
    holder.value += 4's32
}

#test
{
    var box = AssignBox{}
    let ptr = &box
    dref ptr += 9's32
}

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
        where op == .AddAssign or op == .MulAssign
    {
        #static switch op
        {
        case .AddAssign:
            .setPair(.a + value, .b + value)

        case .MulAssign:
            .setPair(.a * value, .b * value)

        }
    }

    mtd(op: Swag.Operator) opAssign(value: u32)
        where op == .ShlAssign
    {
        .setPair(.a << value, .b << value)
    }

    mtd(op: Swag.Operator) opAssign(other: const &AssignBox)
        where op == .AddAssign
    {
        .setPair(.a + other.a, .b + other.b)
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

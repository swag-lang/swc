#global fileprivate

struct RuntimeAssignBox
{
    a: s32
    b: s32
    calls: s32
}

impl RuntimeAssignBox
{
    #[Swag.NoInline]
    mtd setPair(a, b: s32)
    {
        .a = a
        .b = b
        .calls += 1
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opAssign(value: s32)
    {
        #if op == "+=" do
            .setPair(.a + value, .b + value)
        #elif op == "*=" do
            .setPair(.a * value, .b * value)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opAssign(value: u32)
    {
        #if op == "<<=" do
            .setPair(.a << value, .b << value)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opAssign(other: const &RuntimeAssignBox)
    {
        #if op == "+=" do
            .setPair(.a + other.a, .b + other.b)
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }
}

struct RuntimeAssignHolder
{
    value: RuntimeAssignBox
}

#test
{
    var box = RuntimeAssignBox{a: 1, b: 2}
    box += 3's32

    @assert(box.a == 4)
    @assert(box.b == 5)
    @assert(box.calls == 1)
}

#test
{
    var box = RuntimeAssignBox{a: 2, b: 3}
    box *= 4's32

    @assert(box.a == 8)
    @assert(box.b == 12)
    @assert(box.calls == 1)
}

#test
{
    var box = RuntimeAssignBox{a: 3, b: 5}
    box <<= 2'u32

    @assert(box.a == 12)
    @assert(box.b == 20)
    @assert(box.calls == 1)
}

#test
{
    var lhs = RuntimeAssignBox{a: 7, b: 11}
    var rhs = RuntimeAssignBox{a: 13, b: 17}
    lhs += rhs

    @assert(lhs.a == 20)
    @assert(lhs.b == 28)
    @assert(lhs.calls == 1)
}

#test
{
    var holder = RuntimeAssignHolder{}
    holder.value += 9's32

    @assert(holder.value.a == 9)
    @assert(holder.value.b == 9)
    @assert(holder.value.calls == 1)
}

#test
{
    var box = RuntimeAssignBox{a: 10, b: 20}
    let ptr = &box
    dref ptr += 5's32

    @assert(box.a == 15)
    @assert(box.b == 25)
    @assert(box.calls == 1)
}

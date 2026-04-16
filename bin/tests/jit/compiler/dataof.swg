#global fileprivate

struct DataOfSpecBuffer
{
    data: [3] s32
}

impl DataOfSpecBuffer
{
    mtd opData()->[*] s32
    {
        return &.data[0]
    }
}

struct ConstDataOfSpecBuffer
{
    data: [2] u8
}

impl ConstDataOfSpecBuffer
{
    mtd const opData()->const [*] u8
    {
        return &.data[0]
    }
}

#test
{
    func mutateThroughSpecOp()->s32
    {
        var value: DataOfSpecBuffer = {data: [11, 22, 33]}
        let p = @dataof(value)
        p[1] = 44
        return p[0] + p[1] + value.data[2]
    }

    const V0 = #run mutateThroughSpecOp()
    #assert(V0 == 88)
}

#test
{
    func readConstThroughSpecOp()->u32
    {
        const value: ConstDataOfSpecBuffer = {data: [3'u8, 5'u8]}
        let p = @dataof(value)
        return cast(u32) p[0] + cast(u32) p[1]
    }

    const V0 = #run readConstThroughSpecOp()
    #assert(V0 == 8'u32)
}

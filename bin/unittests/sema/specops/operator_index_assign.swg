#global private

struct IndexAssignBox
{
    first:  s32
    second: s32
}

impl IndexAssignBox
{
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: s32)
    {
        #if op == .AddAssign do
            if index == 0 do
                .first += value
        else do
            .second += value
        #elif op == .MulAssign do
            if index == 0 do
            .first *= value
        else do
            .second *= value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op.symbol() ++ "]]")
    }

    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: u32)
    {
        #if op == .ShlAssign do
            if index == 0 do
                .first <<= value
        else do
            .second <<= value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op.symbol() ++ "]]")
    }
}

struct WriteOnlyIndexAssignBox
{
    first:  s32
    second: s32
}

impl WriteOnlyIndexAssignBox
{
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: s32)
    {
        #if op == .AddAssign do
            if index == 0 do
                .first += value
        else do
            .second += value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op.symbol() ++ "]]")
    }
}

struct IndexAssignHolder
{
    value:     IndexAssignBox
    writeOnly: WriteOnlyIndexAssignBox
}

func semaTest001()
{
    var box = IndexAssignBox{first: 1, second: 2}
    box[0] += 3
    box[1] *= 4
    box[0] <<= 1'u32

    var holder = IndexAssignHolder{}
    holder.value[1]     += 5
    holder.writeOnly[0] += 7

    #assert(#typeof(box) == IndexAssignBox)
}

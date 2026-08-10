#global private

struct IndexAssignBox
{
    first:  s32
    second: s32
}

impl IndexAssignBox
{
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: s32)
        where op == .AddAssign or op == .MulAssign
    {
        #static switch op
        {
        case .AddAssign:
            if index == 0 do
                .first += value
            else do
                .second += value

        case .MulAssign:
            if index == 0 do
                .first *= value
            else do
                .second *= value

        }
    }

    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: u32)
        where op == .ShlAssign
    {
        if index == 0 do
            .first <<= value
        else do
            .second <<= value
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
        where op == .AddAssign
    {
        if index == 0 do
            .first += value
        else do
            .second += value
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

#global fileprivate

struct IndexAssignBox
{
    first:  s32
    second: s32
}

impl IndexAssignBox
{
    #[Swag.Overload]
    mtd(op: string) opIndexAssign(index: s32, value: s32)
    {
        #if op == "+=" do
            if index == 0 do
                .first += value
            else do
                .second += value
        #elif op == "*=" do
            if index == 0 do
                .first *= value
            else do
                .second *= value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    mtd(op: string) opIndexAssign(index: s32, value: u32)
    {
        #if op == "<<=" do
            if index == 0 do
                .first <<= value
            else do
                .second <<= value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
    }
}

struct WriteOnlyIndexAssignBox
{
    first:  s32
    second: s32
}

impl WriteOnlyIndexAssignBox
{
    #[Swag.Overload]
    mtd(op: string) opIndexAssign(index: s32, value: s32)
    {
        #if op == "+=" do
            if index == 0 do
                .first += value
            else do
                .second += value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
    }
}

struct IndexAssignHolder
{
    value:     IndexAssignBox
    writeOnly: WriteOnlyIndexAssignBox
}

#test
{
    var box = IndexAssignBox{first: 1, second: 2}
    box[0] += 3
    box[1] *= 4
    box[0] <<= 1'u32

    var holder = IndexAssignHolder{}
    holder.value[1] += 5
    holder.writeOnly[0] += 7

    #assert(#typeof(box) == IndexAssignBox)
}

#test
{
    const box = IndexAssignBox{}
    box[0] += 1 // swc-expected-error {{sema_err_assign_to_const}}
}

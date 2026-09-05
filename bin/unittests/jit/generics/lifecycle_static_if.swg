#global private

var DropCount: s32

struct(T) Gated
{
    value: s32
}

impl Gated
{
    #static if T == s32
    {
        mtd opPostCopy()
        {
            .value += 10
        }

        mtd opPostMove()
        {
            .value += 100
        }

        mtd opDrop()
        {
            DropCount += 1
        }
    }
}

struct(T) Holder
{
    field: Gated'T
}

struct MixedHolder
{
    absent:  [2] Gated'u32
    present: Gated's32
}

#test
{
    DropCount = 0
    var source: Holder'u32 = {{3}}
    #assert(!#defined(source.field.opPostCopy))
    let copied = source
    Swag.assert(copied.field.value == 3)
    Swag.postCopy(&source)
    Swag.assert(source.field.value == 3)
    Swag.postMove(&source)
    Swag.assert(source.field.value == 3)
    Swag.drop(&source)
    Swag.assert(DropCount == 0)
}

#test
{
    DropCount = 0
    var source: Holder's32 = {{3}}
    #assert(#defined(source.field.opPostCopy))
    let copied = source
    Swag.assert(copied.field.value == 13)
    Swag.postCopy(&source)
    Swag.assert(source.field.value == 13)
    Swag.postMove(&source)
    Swag.assert(source.field.value == 113)
    Swag.drop(&source)
    Swag.assert(DropCount == 1)
}

#test
{
    let absent:  typeinfo = #typeof(Gated'u32)
    let present: typeinfo = #typeof(Gated's32)
    let flags             = Swag.TypeInfoFlags.HasDrop | Swag.TypeInfoFlags.HasPostCopy | Swag.TypeInfoFlags.HasPostMove
    Swag.assert((absent.flags & flags) == .Zero)
    Swag.assert((present.flags & flags) == flags)
}

#test
{
    var source: MixedHolder = {[{1}, {2}], {3}}
    let copied              = source
    Swag.assert(copied.absent[0].value == 1)
    Swag.assert(copied.absent[1].value == 2)
    Swag.assert(copied.present.value == 13)
}

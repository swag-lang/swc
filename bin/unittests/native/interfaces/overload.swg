#global private

interface IOverloaded
{
    mtd select(value: string)->s32
    mtd select(value: *s32)->s32
    mtd select(value: Selection)->s32
}

struct Selection
{
    value: s32
}

struct Overloaded
{
}

impl IOverloaded for Overloaded
{
    mtd impl select(value: string)->s32
    {
        return 1
    }

    mtd impl select(value: *s32)->s32
    {
        return 2
    }

    mtd impl select(value: Selection)->s32
    {
        return value.value
    }
}

#test
{
    var object: Overloaded
    let renderer = cast(IOverloaded) &object
    var value: s32

    @assert(renderer.select("value") == 1)
    @assert(renderer.select(&value) == 2)
    @assert(renderer.select(Selection{3}) == 3)
}

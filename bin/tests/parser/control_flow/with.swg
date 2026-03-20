#global fileprivate

namespace ParserWithNs
{
    func bias(v: s32)->s32
    {
        return v + 1
    }
}

enum ParserWithColor
{
    Red,
    Blue,
}

struct ParserWithPoint
{
    x: s32
    y: s32
}

struct ParserWithHolder
{
    ptr: *ParserWithPoint
}

impl ParserWithPoint
{
    mtd add(v: s32)
    {
        me.x += v
        me.y += v
    }
}

func parser_with_examples()
{
    var point: ParserWithPoint
    var holder: ParserWithHolder

    with point
    {
        .x = 1
        .add(2)
    }

    with point = ParserWithPoint{x: 3, y: 4}
    {
        .y += 1
    }

    with holder.ptr = &point
    {
        .x += 5
    }

    with ParserWithColor
    {
        let a = Red
        let b = .Blue
    }

    with ParserWithNs
    {
        bias(1)
        .bias(2)
    }

    with var pair: { a, b: s32 }
    {
        .a = 4
        .b = 5
    }
}

#test
{
    parser_with_examples()
}

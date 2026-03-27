#global fileprivate

struct A
{
    count: s32
    x: s32
    y: s32
}

impl A
{
    mtd whereFunction(n: s32)->bool => .count == n

    mtd foo()
    {
        let a = .x
        #assert(#typeof(a) == s32)
        let b = .x + .y
    }
}

interface I
{
}

impl I for A
{
    mtd bar()
    {
        let a = .x
        #assert(#typeof(a) == s32)
        let b = .x + .y
    }
}

#global fileprivate

struct A
{
    count: s32
    x: s32
    y: s32
}

impl A
{
    mtd const whereFunction(n: s32)->bool => .count == n

    mtd foo()
    {
        let a = .x
        #assert(#typeof(a) == s32)
        let b = .x + .y
    }
}

#test
{
    let value = A{count: 3, x: 1, y: 2}
    let ok = value.whereFunction(3)
    #assert(#typeof(ok) == bool)
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

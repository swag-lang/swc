#global internal

struct A
{
    x: s32
    y: s32
}

impl A
{
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
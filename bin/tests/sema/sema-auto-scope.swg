#global internal

struct A
{
    x: s32
}

impl A
{
    mtd foo()
    {
        let a = .x
        #assert(#typeof(a) == s32)
    }
}

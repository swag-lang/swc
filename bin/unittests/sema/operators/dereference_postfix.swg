#global private

// 'expr[]' is the postfix spelling of the dereference: it opens the pointed storage as
// a read/write place and composes left-to-right with member and index access.
// 'expr[as T]' reinterprets the pointed storage as a T.

func semaTest001()
{
    var value = 1's32
    var p     = &value
    #assert(#typeof(p[]) == s32)
}

func semaTest002()
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var p = &st
    #assert(#typeof(p[]) == AA)
    #assert(#typeof(p[].x) == s32)
}

func semaTest003()
{
    var value: s32
    var p  = &value
    var pp = &p
    #assert(#typeof(pp[]) == *s32)
    #assert(#typeof(pp[][]) == s32)
}

func semaTest004()
{
    var grid: [2, 3] s32
    var p = &grid
    #assert(#typeof(p[]) == #type [2, 3] s32)
    #assert(#typeof(p[][0]) == #type [3] s32)
    #assert(#typeof(p[][0, 0]) == s32)
}

func semaTest005()
{
    var value = 0'u32
    var p     = &value
    #assert(#typeof(p[as s32]) == s32)
    #assert(#typeof(p[as u8]) == u8)
}

func semaTest006()
{
    var value = 1's32
    #assert(#typeof((&value)[]) == s32)
}

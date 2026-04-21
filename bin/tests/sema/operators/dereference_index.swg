#global fileprivate

#test
{
    var buf1: [4] s32
    var a1 = buf1[0]
    #assert(#typeof(a1) == s32)

    var ptr1 = &buf1[0]
    #assert(#typeof(ptr1) == [*] s32)
}

#test
{
    var a4: [2, 3] s32
    #assert(#typeof(a4[0]) == #type [3] s32)
}

#test
{
    var a6: [..] s32
    var b6 = a6[0]
    #assert(#typeof(b6) == s32)
}

#test
{
    var a2: [..] s32
    var b2 = a2[0]
    #assert(#typeof(b2) == s32)
}

#test
{
    var A = "titi"
    var B = A[1]
}

#test
{
    var text = "hello"
    var textRef: &string = &text
    var ch = textRef[1]
    #assert(#typeof(ch) == u8)

    var grid: [2, 3] s32
    var gridRef: &[2, 3] s32 = &grid
    #assert(#typeof(gridRef[0]) == #type [3] s32)
    #assert(#typeof(gridRef[0, 0]) == s32)

    var backing: [2] s32
    var slice: [..] s32 = backing
    var sliceRef: &[..] s32 = &slice
    var elem = sliceRef[0]
    #assert(#typeof(elem) == s32)
}

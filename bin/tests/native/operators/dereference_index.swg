#global fileprivate // 

#test
{
    var buf1: [4] s32
    var a1 = buf1[0]
    #assert(#typeof(a1) == s32)

    var ptr1 = &buf1[0]
    #assert(#typeof(ptr1) == [*] s32)
    @assert(a1 == 0)
    @assert(ptr1 == &buf1[0])
}



#test
{
    var a4: [2, 3] s32
    #assert(#typeof(a4[0]) == #type [3] s32)
    @assert(@countof(a4[0]) == 3)
}


#test
{
    var backing6: [2] s32 = [11, 22]
    var a6: [..] s32 = backing6
    var b6 = a6[0]
    #assert(#typeof(b6) == s32)
    @assert(b6 == 11)
}



#test
{
    var backing2: [2] s32 = [33, 44]
    var a2: [..] s32 = backing2
    var b2 = a2[0]
    #assert(#typeof(b2) == s32)
    @assert(b2 == 33)
}


#test
{
    var A = "titi"
    var B = A[1]
    @assert(B == cast(u8) 'i''rune)
}

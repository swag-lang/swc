#global fileprivate

// Array indexing and address-of element
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

// Multidimensional array indexing
#test
{
    var a4: [2, 3] s32
    #assert(#typeof(a4[0]) == #type [3] s32)
    @assert(@countof(a4[0]) == 3)
}

// Slice indexing from backing array
#test
{
    var backing6: [2] s32 = [11, 22]
    var a6: [..] s32 = backing6
    var b6 = a6[0]
    #assert(#typeof(b6) == s32)
    @assert(b6 == 11)
}

// Slice indexing with different initial values
#test
{
    var backing2: [2] s32 = [33, 44]
    var a2: [..] s32 = backing2
    var b2 = a2[0]
    #assert(#typeof(b2) == s32)
    @assert(b2 == 33)
}

// String character indexing
#test
{
    var A = "titi"
    var B = A[1]
    @assert(B == cast(u8) 'i''rune)
}

// Multi-index on C-style nested arrays.
#test
{
    var a: [2][2] s32
    a[0, 0] = 10
    a[0, 1] = 20
    a[1, 0] = 30
    a[1, 1] = 40
    @assert(a[0, 0] == 10)
    @assert(a[0, 1] == 20)
    @assert(a[1, 0] == 30)
    @assert(a[1, 1] == 40)
}

#test
{
    var a: [3][2] s32
    a[0, 0] = 1
    a[2, 1] = 6
    @assert(a[0, 0] == 1)
    @assert(a[2, 1] == 6)
}

#test
{
    var text = "hello"
    var textRef: &string = &text
    @assert(textRef[1] == cast(u8) 'e''rune)

    var grid: [2, 3] s32
    grid[1, 2] = 42
    var gridRef: &[2, 3] s32 = &grid
    @assert(@countof(gridRef[0]) == 3)
    @assert(gridRef[1, 2] == 42)

    var backing: [2] s32 = [11, 22]
    var slice: [..] s32 = backing
    var sliceRef: &[..] s32 = &slice
    @assert(sliceRef[0] == 11)
    sliceRef[1] = 99
    @assert(backing[1] == 99)
}

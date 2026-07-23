#global private

struct(T) BufferBox
{
    buffer: [*] T
    count:  u64
}

impl BufferBox
{
    mtd firstPtr()->[*] T
    {
        var ptr = .buffer
        return ptr
    }

    mtd toLocalSlice()->[..] T
    {
        var ptr = .buffer
        let len = .count
        return @mkslice(ptr, len)
    }
}

func semaTest001()
{
    var values: [3] s32
    values[0] = 11
    values[1] = 22
    values[2] = 33
    var box    = BufferBox's32{buffer: cast([*] s32) &values[0], count: 3}
    let ptr    = box.firstPtr()
    let sl     = box.toLocalSlice()

    #assert(#typeof(ptr) == [*] s32)
    #assert(#typeof(sl) == [..] s32)
    #assert(#typeof(sl[0]) == s32)
}

#global fileprivate // 

#test
{
    var buf: [100] u8
    let str = @mkstring(&buf[0], 10)
    #assert(#typeof(str) == string)
    @assert(@countof(str) == 10)
}

#test
{
    var buf: [8] u8 = ['s''u8, 'w''u8, 'a''u8, 'g''u8, '-''u8, '4''u8, '2''u8, '!''u8]
    let head = @mkstring(&buf[0], 4)
    let tail = @mkstring(&buf[4], 4)
    let empty = @mkstring(&buf[2], 0)

    #assert(#typeof(head) == string)
    #assert(#typeof(tail) == string)
    #assert(#typeof(empty) == string)
    @assert(head == "swag")
    @assert(tail == "-42!")
    @assert(head[1] == 'w''u8)
    @assert(tail[3] == '!''u8)
    @assert(@countof(empty) == 0)
}

#test
{
    var buf: [5] u8 = ['h''u8, 'e''u8, 'l''u8, 'l''u8, 'o''u8]
    let str = @mkstring(&buf[1], 3)

    #assert(#typeof(str) == string)
    @assert(str == "ell")
    @assert(@countof(str) == 3)
    @assert(str[0] == 'e''u8)
    @assert(str[2] == 'l''u8)
}

#test
{
    var buf: [4] u8 = ['a''u8, 'b''u8, 'c''u8, 'd''u8]
    let str = @mkstring(&buf[2], 0)

    #assert(#typeof(str) == string)
    @assert(@countof(str) == 0)
}

#test
{
    var buf: [6] u8 = ['s''u8, 'w''u8, 'a''u8, 'g''u8, '4''u8, '2''u8]
    let str = @mkstring(&buf[0], 6)
    let bytes = cast(const [..] u8) str

    #assert(#typeof(bytes) == const [..] u8)
    @assert(@countof(bytes) == 6)
    @assert(bytes[0] == 's''u8)
    @assert(bytes[5] == '2''u8)
    @assert(str == "swag42")
}

#test
{
    var buf: [4] u8 = ['t''u8, 'e''u8, 's''u8, 't''u8]
    let ptr: const *u8 = &buf[0]
    let str = @mkstring(ptr, 4)

    #assert(#typeof(str) == string)
    @assert(@countof(str) == 4)
    @assert(str == "test")
}



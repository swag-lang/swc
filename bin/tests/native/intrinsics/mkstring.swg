#global fileprivate // swc-option suite-test

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



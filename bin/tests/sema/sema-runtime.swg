#global internal

#test
{
    var v = @getcontext()
    #assert(#defined(v.allocator))

    var buf: [100] u8
    let str = cast(string) @mkslice(&buf[0], @strlen(&buf[0]))
}
#global internal

#test
{
    var buf: [100] u8
    let str = @mkstring(&buf[0], 10)
    #assert(#typeof(str) == string)
}

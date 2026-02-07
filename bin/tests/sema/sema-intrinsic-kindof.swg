#global internal

#test
{
    var a: any
    var b = @kindof(a)
    #assert(#typeof(b) == typeinfo)
}

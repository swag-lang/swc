#global internal

func A() => true
#test
{
    let a = A()
    #assert(#typeof(a) == bool)
}
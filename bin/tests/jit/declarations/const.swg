#global fileprivate

// Grouped const declarations must not trip JIT codegen.
#test
{
    const a, b = false
    #assert(a == false)
    #assert(b == false)
}

#test
{
    const a, b = true
    #assert(a == true)
    #assert(b == true)
}

#test
{
    const a, b: s32 = 42
    #assert(a == 42)
    #assert(b == 42)
}

#test
{
    const a, b = 0xFF
    #assert(a == 0xFF)
    #assert(b == 0xFF)
}

#test
{
    const a = 1, b = 2
    #assert(a == 1)
    #assert(b == 2)
}

#test
{
    const a, b, c = 7
    #assert(a == 7)
    #assert(b == 7)
    #assert(c == 7)
}

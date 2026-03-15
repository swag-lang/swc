#global #if true // swc-option suite-test
#global namespace GIf

func makeValue()->s32
{
    return 42
}

#test
{
    @assert(GIf.makeValue() == 42)
}

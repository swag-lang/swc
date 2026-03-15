#global #if true
#global namespace GIf

func makeValue()->s32
{
    return 42
}

#test
{
    @assert(GIf.makeValue() == 42)
}

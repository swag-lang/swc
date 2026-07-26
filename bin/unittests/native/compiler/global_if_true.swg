#global #static if true     //
#global private
#global namespace GIf

func makeValue()->s32
{
    return 42
}

// #global #static if true preserves declarations
#test
{
    @assert(GIf.makeValue() == 42)
}

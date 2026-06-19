#global #if true // 
#global fileprivate
#global namespace GIf

func makeValue()->s32
{
    return 42
}

// #global #if true preserves declarations
#test
{
    @assert(GIf.makeValue() == 42)
}

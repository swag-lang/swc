#global #if 1
#global fileprivate
#global namespace GIf

func makeValue()->s32
{
    return 42
}

func semaTest001()
{
    @assert(GIf.makeValue() == 42)
}

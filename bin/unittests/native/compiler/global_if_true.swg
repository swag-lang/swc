#global if true     //
#global private
#global namespace GIf

func makeValue()->s32
{
    return 42
}

// #global if true preserves declarations
#test
{
    Swag.require(GIf.makeValue() == 42)
}

#global fileprivate

func parseCompilerAstBlock()
{
    #ast
    {
        var value = 1
        return "let generated = 2"
    }
}

struct(T) ParseCompilerAstMembers
{
    #ast
    {
        var typeInfo = #typeof(T)
        return "field: s32"
    }
}

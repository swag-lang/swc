#global fileprivate
using Swag

var X: u32 = undefined

#[Swag.Compiler, Swag.Inline]
func inlineCompilerSet()
{
    X = 6
}

#test
{
    #run inlineCompilerSet()
    @assert(X == 6)
}

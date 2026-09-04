#global private
using Swag

var X: u32

#[Swag.Compiler, Swag.Inline]
func inlineCompilerSet()
{
    X = 6
}

#test
{
    #run inlineCompilerSet()
    Swag.assert(X == 6)
}

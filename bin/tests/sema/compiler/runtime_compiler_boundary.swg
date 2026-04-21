#global fileprivate
using Swag

#[Compiler]
var CompilerValue = 1

#[Compiler]
func compilerOnlyFn()->s32
{
    return CompilerValue
}

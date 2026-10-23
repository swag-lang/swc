#global private
using Swag

#[Compiler]
var CompilerValue = 1     // swc-expected-note {{compile-time-only variable 'CompilerValue' is declared here}}

#[Compiler]
func compilerOnlyFn()->s32     // swc-expected-note {{compile-time-only function 'compilerOnlyFn' is declared here}}
{
    return CompilerValue
}

func useCompilerVariable()->s32
{
    return CompilerValue     // swc-expected-error {{runtime function 'useCompilerVariable' cannot reference compile-time-only variable 'CompilerValue'}}
}

func useCompilerFunction()->s32
{
    return compilerOnlyFn()     // swc-expected-error {{runtime function 'useCompilerFunction' cannot reference compile-time-only function 'compilerOnlyFn'}}
}

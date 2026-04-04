#global fileprivate
using Swag

#[Compiler]
var CompilerValue = 1

#[Compiler]
func compilerOnlyFn()->s32
{
    return CompilerValue
}

func useCompilerVariable()->s32
{
    return CompilerValue // swc-expected-error {{sema_err_runtime_uses_compiler_only_symbol}}
}

func useCompilerFunction()->s32
{
    return compilerOnlyFn() // swc-expected-error {{sema_err_runtime_uses_compiler_only_symbol}}
}

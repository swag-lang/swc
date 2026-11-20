#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

// WGL lookup treats unsupported sentinel addresses the same as a missing entry point.
#test
{
    Swag.require(not Ogl.isValidWglProcAddress(null))
    for value in [1'u64, 2, 3, 0xFFFFFFFFFFFFFFFF] do
        Swag.require(not Ogl.isValidWglProcAddress(cast(const *void?, value)))
    Swag.require(Ogl.isValidWglProcAddress(cast(const *void?, 4'u64)))
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#test
{
    let window = 0x12345678'u32
    let native = Ogl.Platform.Xcb.nativeWindowHandle(window)
    Swag.require(cast(u64, native) == cast(u64, window))
}

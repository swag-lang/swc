#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#test
{
    var window = 0x12345678'u32
    let native = Ogl.Platform.Xcb.nativeWindowHandle(&window)
    Swag.require(cast(*u32?, native) == &window)
}

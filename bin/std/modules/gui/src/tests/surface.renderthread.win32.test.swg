#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Win32, Ogl

// The window's rendering context must stay on its owner thread. Delegating synchronous WGL
// calls to another thread lets drawable reallocation overlap USER32's geometry transaction;
// the driver can then stall for seconds even when the surface contains no controls.
#[Swag.TestTag("gpu")]
#test
{
    var app: Application
    let surface = (expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-render-owner-test"))!
    let context = Ogl.wglGetCurrentContext()
    Swag.assert(context != null, "the window owner must own the default OpenGL context")

    var processId: u32
    let owner = GetWindowThreadProcessId(surface.win32Handle(), &processId)
    Swag.assert(owner == GetCurrentThreadId())

    for step in 4
    {
        surface.setPosition({40, 40, cast(f32) (320 + step * 2), 180})
        surface.paint()
        Swag.assert(Ogl.wglGetCurrentContext() == context)
        Swag.assert(surface.rt.colorBuffer.isValid())
    }
}

#global #if #command == Swag.CompilerCommand.Test
#global #if #os == Swag.TargetOs.Windows
#global fileprivate
using Swag, Core

#test
{
    var app: Application
    let surface = try app.createSurface(32, 32, 160, 128, SurfaceFlags.NoShadow, surfaceID: "gui-test-create-window")
    surface.show()

    @assert(surface != null)
    @assert(surface.hWnd != null)
    @assert(!surface.isHidden)
    @assert(app.mainSurface == surface)
    @assert(app.surfaces.count == 1)
    @assert(surface.getView() != null)
    @assert(surface.getView().surface == surface)
    @assert(surface.rc.width == 160)
    @assert(surface.rc.height == 128)
}

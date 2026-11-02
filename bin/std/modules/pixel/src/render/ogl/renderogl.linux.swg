#global if #os == Swag.TargetOs.Linux

using Core

private func xcbSurface(rc: OglContext)->*Ogl.Platform.Xcb.Surface => cast #unconst (*Ogl.Platform.Xcb.Surface, unwrap rc.hDC)

internal impl NativeRenderOgl
{
    mtd createWindowContext(renderHandle: const *void?, width, height: s32, mainRC: const *void? = null)->OglContext fail
    {
        if not renderHandle do
            fail Errors.BadParameterError{"OpenGL context needs an XCB drawable"}
        let drawable = cast(const *Env.XcbDrawable, renderHandle)[]
        var context: *Ogl.Platform.Xcb.Context
        if mainRC do
            context = cast #unconst (*Ogl.Platform.Xcb.Context, mainRC)
        else do
            context = Memory.new'Ogl.Platform.Xcb.Context()
        defer #fail if not mainRC do
            Memory.delete(context)
        let surface = Memory.new'Ogl.Platform.Xcb.Surface()
        defer #fail Memory.delete(surface)
        if mainRC
        {
            surface[] = try context.createSurface(drawable)
        }
        else
        {
            context[] = try Ogl.Platform.Xcb.createContextForDrawable(drawable)
            surface[] = try context.takeSurface()
        }

        return {hDC: surface, hRC: context, hWnd: renderHandle, width: width, height: height, ownsDC: true, ownsRC: mainRC == null}
    }

    mtd dropContext(rc: OglContext)
    {
        if rc.ownsDC do
            Memory.delete(xcbSurface(rc))
        if rc.ownsRC do
            .deleteContextHandle(rc.hRC)
    }

    mtd deleteContextHandle(handle: const *void?)
    {
        if handle do
            Memory.delete(cast #unconst (*Ogl.Platform.Xcb.Context, handle))
    }

    mtd setCurrentContext(rc: OglContext) { expect xcbSurface(rc).makeCurrent() }
    mtd swapBuffers(rc: OglContext) { expect xcbSurface(rc).swapBuffers() }
    mtd applyPresentPolicy() { expect Ogl.Platform.Xcb.setSwapInterval(1) }
}

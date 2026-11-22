#global public
#global if #os == Swag.TargetOs.Linux

using Core, Ogl

private func xcbSurface(rc: OglContext)->*Ogl.Platform.Xcb.Surface => cast #unconst (*Ogl.Platform.Xcb.Surface, unwrap rc.hDC)

internal impl NativeRenderOgl
{
    mtd createWindowContext(renderHandle: const *void?, width, height: s32, mainRC: const *void? = null)->OglContext fail
    {
        var context: *Ogl.Platform.Xcb.Context
        if mainRC do
            context = cast #unconst (*Ogl.Platform.Xcb.Context, mainRC)
        else do
            context = Memory.new'Ogl.Platform.Xcb.Context()
        defer #fail if not mainRC do
            Memory.delete(context)
        let surface = Memory.new'Ogl.Platform.Xcb.Surface()
        defer #fail Memory.delete(surface)
        if renderHandle
        {
            let drawable = cast(const *Env.XcbDrawable, renderHandle)[]
            if mainRC
            {
                surface[] = try context.createSurface(drawable)
            }
            else
            {
                context[] = try Ogl.Platform.Xcb.createContextForDrawable(drawable)
                surface[] = try context.takeSurface()
            }
        }
        elif mainRC
        {
            surface[] = try context.createPbufferSurface(width, height)
        }
        else
        {
            context[] = try Ogl.Platform.Egl.createOffscreenContext(width, height)
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

    // EGL contexts here are not created to report device resets, so the renderer never asks for
    // a replacement; see [[Pixel.RenderOgl.recoverLostDevice]].
    mtd replaceLostContext(_: const [..] *OglContext, _: const *void?)->const *void? fail
    {
        fail RenderResourceError{"OpenGL device reset recovery is not available with EGL"}
    }

    mtd makeCurrent(rc: OglContext) fail => try xcbSurface(rc).makeCurrent()
    mtd swapBuffers(rc: OglContext) { expect xcbSurface(rc).swapBuffers() }
    mtd applyPresentPolicy() { expect Ogl.Platform.Xcb.setSwapInterval(1) }

    mtd resizeWindowBackBuffer(context: *OglContext, width, height: s32) fail
    {
        if context.width == width and context.height == height do
            return

        // Mesa's XCB EGL window surface retains its original back-buffer size. Replace
        // the drawable after xcb_configure_window and keep the shared GL context.
        let nativeContext = cast #unconst (*Ogl.Platform.Xcb.Context, unwrap context.hRC)
        let drawable      = cast(const *Env.XcbDrawable, unwrap context.hWnd)[]
        let surface       = xcbSurface(context[])
        surface.destroy()
        surface[] = try nativeContext.createSurface(drawable)
        try surface.makeCurrent()
        context.width  = width
        context.height = height
    }
}

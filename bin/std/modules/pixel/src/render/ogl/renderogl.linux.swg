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

    mtd setCurrentContext(rc: OglContext) { expect xcbSurface(rc).makeCurrent() }
    mtd swapBuffers(rc: OglContext) { expect xcbSurface(rc).swapBuffers() }
    mtd applyPresentPolicy() { expect Ogl.Platform.Xcb.setSwapInterval(1) }
}

impl RenderOgl
{
    // The GUI render target may be padded beyond the current window size. Copy its
    // visible top-left rectangle directly into the EGL back buffer, preserving texels.
    mtd blitRenderTargetToWindow(target: const *RenderTarget, width, height: s32)->bool fail
    {
        if not target.colorBuffer.isValid() or width <= 0 or height <= 0 or
           width > target.colorBuffer.width or height > target.colorBuffer.height do
            return false

        let context = oglContext(.curRC)
        if context.width != width or context.height != height
        {
            // Mesa's XCB EGL window surface retains its original back-buffer size after
            // xcb_configure_window. Replace that drawable without replacing the GL context.
            let nativeContext = cast #unconst (*Ogl.Platform.Xcb.Context, unwrap context.hRC)
            let drawable      = cast(const *Env.XcbDrawable, unwrap context.hWnd)[]
            let surface       = xcbSurface(context[])
            surface.destroy()
            surface[] = try nativeContext.createSurface(drawable)
            try surface.makeCurrent()
            context.width  = width
            context.height = height
        }

        var previousRead, previousDraw: GLint
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousRead)
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousDraw)
        let scissorEnabled = glIsEnabled(GL_SCISSOR_TEST) != 0
        defer
        {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, previousRead))
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, cast(GLuint, previousDraw))
            if scissorEnabled do
                glEnable(GL_SCISSOR_TEST)
        }

        glDisable(GL_SCISSOR_TEST)
        glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, target.handle))
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
        glBlitFramebuffer(0, target.colorBuffer.height - height,
                          width, target.colorBuffer.height,
                          0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST)
        return glGetError() == GL_NO_ERROR
    }
}

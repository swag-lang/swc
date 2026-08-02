#global public

using Core, Pixel, Serialization

// Serializable placement and display state of a surface.
//
// This is what an application persists through [[Gui.Application.saveState]], so a field
// here keeps an alias for every name it has been written under; see [[Pixel.Image]].
struct SurfaceState
{
    position: Math.Rectangle     // Current surface bounds in screen coordinates.

    #[Serialization.Alias("positionNotMaximized")]
    restoredPosition: Math.Rectangle     // Bounds restored after leaving a maximized state.

    isMaximized: bool     // Whether the surface is maximized.
}

// Top-level drawable window managed by an [[Application]].
struct Surface
{
    using native: NativeSurface                // Platform-specific window state.
    app:          *Application = undefined     // Application that owns the surface.
    wnd:          *SurfaceWnd  = undefined     // Root window containing the surface view.
    userData:     #null *void                  // Optional caller-owned data.
    surfaceId:    String                       // Identifier used by cross-process custom messages.

    minSize: Math.Point     // Minimum allowed width and height; zero disables a dimension limit.
    maxSize: Math.Point     // Maximum allowed width and height; zero disables a dimension limit.

    flags:         SurfaceFlags = None     // Current presentation and window-manager flags.
    colorDisabled: Color                   // Animated tint used while the surface is disabled.

    // What the surface is made of and where it stands. The application creates surfaces and
    // the event loop moves them between these states; reading them tells what is on screen.
    readonly
    {
        painter: Painter          // Painter recording the surface's frame.
        rt:      RenderTarget     // Render target the frame is drawn into.

        isHidden:      bool = true     // Whether the surface is not visible.
        isInitialized: bool            // Whether the surface has received its one-time initialization event.
        isDisabled:    bool            // Whether the surface refuses input, for example during a modal operation.
        isMinimized:   bool            // Whether the surface is minimized.
    }

    // Drawable and viewport of the surface, plus repaint bookkeeping. The platform layer and
    // the paint loop own them; callers reach the drawable with 'renderingContext'.
    internal
    {
        rc:        RenderContext                                           // Drawable and viewport the frame targets.
        dirtyRect: Math.Rectangle = {Swag.F32.Max, Swag.F32.Max, 0, 0}     // Region to repaint.
        isDirty:   bool                                                    // Whether a repaint is pending.
    }

    using state: SurfaceState     // Serializable placement and maximized state.
}

// Configures a surface's native chrome, resize behavior, and Z-order class.
#[Swag.EnumFlags]
enum SurfaceFlags
{
    None = 0                                                                                               // Creates a frameless, non-resizable surface.
    LargeCaption                                                                                           // Uses the standard large title bar.
    SmallCaption                                                                                           // Uses the compact tool-window title bar.
    MinimizeButton                                                                                         // Displays a minimize button in the title bar.
    MaximizeButton                                                                                         // Displays a maximize button in the title bar.
    CloseButton                                                                                            // Displays a close button in the title bar.
    Border                                                                                                 // Draws the themed window border.
    Resizable                                                                                              // Allows the user to resize the surface by dragging its border.
    ToolWindow                                                                                             // Creates a secondary tool window that does not appear in the taskbar.
    TopMost                                                                                                // Keeps the surface above non-topmost windows.
    NoShadow                                                                                               // Disables the themed shadow around the surface.
    StandardWindow = LargeCaption | MinimizeButton | MaximizeButton | CloseButton | Border | Resizable     // Standard resizable application window.
}

impl Surface
{
    internal mtd bindPainterToRenderer(renderer: IRenderer)
    {
        .painter.setRenderer(renderer)
    }

    // Returns the drawable and viewport of this surface.
    //
    // Pass it to [[Pixel.IRenderer.begin]] to draw into this surface with an own painter,
    // as a capture or an export pass does.
    mtd const renderingContext()->Pixel.RenderContext
    {
        return .rc
    }

    // Adds and removes runtime-changeable surface flags.
    //
    // [[SurfaceFlags.ToolWindow]] is fixed when the native window is created and cannot be
    // changed with this method.
    mtd updateFlags(add: SurfaceFlags = .None, remove = SurfaceFlags.None)
    {
        // Cannot be changed at runtime
        Debug.assert(!(add & .ToolWindow) and !(remove & .ToolWindow))

        .flags.add(add)
        .flags.remove(remove)
        .applySurfaceFlags()
    }

    private mtd applySurfaceFlags()
    {
        if .flags.has(.LargeCaption) do
            .wnd.padding.y = .app.theme.metrics.wnd_BigCaptionCY
        elif .flags.has(.SmallCaption) do
            .wnd.padding.y = .app.theme.metrics.wnd_SmallCaptionCY
        else do
            .wnd.padding.y = 0

        if .flags.has(.Border) and .app.theme.metrics.surfaceWnd_ShadowSize > 0
        {
            let size = .app.theme.metrics.wnd_BorderSize
            .wnd.padding.x = size
            .wnd.padding.y = Math.max(.wnd.padding.y, size)
            .wnd.padding.z = size
            .wnd.padding.w = size
        }
        else
        {
            .wnd.padding.x = 0
            .wnd.padding.z = 0
            .wnd.padding.w = 0
        }

        .applyNativeSurfaceFlags()
        .wnd.applySurfaceFlags()
        .wnd.sendResizeEvent()
    }

    internal func create(surface: *Surface, x, y, width, height: s32, flags: SurfaceFlags, mainSurface: #null *Surface) fail
    {
        with surface
        {
            .flags             = flags
            .wnd               = Memory.new'SurfaceWnd()
            .wnd.isAllocated   = true
            .wnd.itf           = .wnd
            .wnd.type          = SurfaceWnd
            .wnd.surface       = surface
            .wnd.focusStrategy = .None
            .wnd.computeStyle()
            .applySurfaceFlags()
        }

        let app = surface.app
        if app.renderer.needsNativeWindow() do
            try createNative(app, surface, x, y, width, height, flags)

        surface.rc      = try app.renderer.createContext(surface.nativeRenderHandle(), width, height, mainSurface ? &mainSurface.rc : null)
        surface.painter = Painter.create(app.renderer)

        surface.minSize = {128, 128}
        let w = cast(f32) Math.max(surface.minSize.x, cast(f32) width)
        let h = cast(f32) Math.max(surface.minSize.y, cast(f32) height)

        surface.sendResizeEvent(w, h)
    }

    internal mtd destroyRendering()
    {
        if .rt.colorBuffer.isValid()
        {
            .app.renderer.setCurrentContext(.rc)
            .app.renderer.deleteRenderTarget(&.rt)
        }

        .app.renderer.deleteContext(&.rc)
    }

    // Schedules the surface and its complete window tree for destruction.
    mtd destroy()
    {
        .wnd.destroy()
        .hide()
    }

    // Returns the root user view displayed by the surface.
    mtd const view()->*Wnd
    {
        return .wnd.view
    }

    // Changes the icon displayed in the surface title bar.
    mtd setIcon(icon: Icon)
    {
        .wnd.icon = icon
        .invalidate()
    }

    // Changes the surface title, or clears it when `name` is `null`.
    mtd setTitle(name: #null string)
    {
        .wnd.name.set(name)
        .invalidate()
    }

    // Schedules the complete surface for repainting.
    mtd invalidate()
    {
        .invalidateRect({0, 0, .position.width, .position.height})
    }

    // Adds a rectangle in surface coordinates to the pending repaint region.
    mtd invalidateRect(rect: Math.Rectangle)
    {
        if !.isDirty
        {
            .dirtyRect = rect
            .isDirty   = true
            return
        }

        let r = .dirtyRect.right()
        let b = .dirtyRect.bottom()
        .dirtyRect.x = Math.min(.dirtyRect.x, rect.x)
        .dirtyRect.y = Math.min(.dirtyRect.y, rect.y)
        .dirtyRect.setRight(Math.max(r, rect.right()))
        .dirtyRect.setBottom(Math.max(b, rect.bottom()))
    }

    // Centers this surface over `from` without changing its size.
    mtd center(from: *Surface)
    {
        var pos = .position
        pos.x = from.position.horzCenter()
        pos.y = from.position.vertCenter()
        pos.x -= .position.width * 0.5
        pos.y -= .position.height * 0.5
        .setPosition(pos)
    }

    // Moves the surface inside the closest monitor's bounds.
    //
    // `topLeft` and `bottomRight` select which corners are constrained. `margin` keeps the
    // selected edges that many pixels away from the monitor boundary.
    mtd constrainPositionToScreen(topLeft, bottomRight = true, margin = 0'f32)
    {
        if .isMaximized or .isMinimized do
            return

        let monitor = Env.monitorForPoint({.position.x, .position.y})
        var np      = .position

        if topLeft
        {
            np.x = Math.max(np.x, monitor.bounds.x + margin)
            np.x = Math.min(np.x, monitor.bounds.right() - margin)
            np.y = Math.max(np.y, monitor.bounds.y + margin)
            np.y = Math.min(np.y, monitor.bounds.bottom() - margin)
        }

        if bottomRight
        {
            np.x = Math.min(np.x, monitor.bounds.right() - margin - .position.width)
            np.y = Math.min(np.y, monitor.bounds.bottom() - margin - .position.height)
        }

        .setPosition(np)
    }

    private mtd createRT()
    {
        if !.rt.colorBuffer.isValid() or .rt.colorBuffer.width < .rc.width or .rt.colorBuffer.height < .rc.height
        {
            .app.renderer.deleteRenderTarget(&.rt)
            let w = Math.roundUpToPowerOf2(cast(u32) .rc.width)
            let h = Math.roundUpToPowerOf2(cast(u32) .rc.height)
            .rt = .app.renderer.createRenderTarget(w, h)
            .invalidate()
        }
    }

    internal mtd paint()
    {
        .paintWnd(.wnd)
    }

    // Paints an explicit root through the surface pipeline. Headless tests use their detached
    // deterministic root; native surfaces use the SurfaceWnd selected by paint().
    internal mtd paintWnd(root: *Wnd)
    {
        .createRT()

        if !.isDirty do
            return
        let clipRect = .dirtyRect
        .dirtyRect = {Swag.F32.Max, Swag.F32.Max, 0, 0}
        .isDirty   = false

        with var cxt: PaintContext
        {
            .painter  = &me.painter
            .renderer = me.app.renderer
            .renderer.begin(me.rc)
            .painter.begin()
        }

        // Draw shadow around surface
        var myRect = Math.Rectangle{0, 0, .position.width, .position.height}
        .painter.pushClippingRect(clipRect)
        .painter.setColorMaskFull()
        .paintShadow()

        // Hierarchy paint
        .painter.pushClippingRect(root.surfaceRect())
        .painter.setColorMaskColor()
        root.paint(&cxt)
        .painter.resetTransform()
        .painter.popClippingRect()

        if .app.options.showClipRect
        {
            var dbgColor = Random.shared().nextU32() & 0x00FFFFFF
            dbgColor |= 0x55000000
            .painter.fillRect(clipRect, Color.fromArgb(dbgColor))
        }

        .paintShadowOutsideBody()
        .paintAlphaMask()
        .painter.end()

        // Paint to surface render target
        with cxt
        {
            .renderer.bindRenderTarget(&me.rt, vp: &myRect)
            .renderer.setScissorRect(clipRect)
            .renderer.clear()
            .renderer.draw(&me.painter)
            .renderer.unbindRenderTarget()
        }

        // Paint render target to screen
        .painter.begin()
        .painter.setColorMaskFull()
        .painter.setInterpolationMode(.Pixel)
        .painter.setBlendingMode(.Copy)

        // If surface is disabled, blend to disabled blit color
        var color: Color
        if .isDisabled and .app.fadeDisabledSurface
        {
            .colorDisabled = Color.lerp(.colorDisabled, .app.theme.colors.surfaceDisabled, .app.deltaSeconds())
            color          = .colorDisabled
            .isDirty       = true
            .dirtyRect.clear()
        }
        else
        {
            color          = Argb.White
            .colorDisabled = Argb.White
        }

        let dstRect = Math.Rectangle{0, 0, cast(f32) .rc.width, cast(f32) .rc.height}
        .painter.drawTexture(dstRect, dstRect, .rt.colorBuffer, color)
        .painter.end()

        cxt.renderer.draw(&.painter)
        cxt.renderer.end()
    }

    private mtd sendResizeEvent(width, height: f32)
    {
        .rc.width        = cast(s32) width
        .rc.height       = cast(s32) height
        .position.width  = width
        .position.height = height

        let sdw = .flags.has(.NoShadow) ? 0 : .app.theme.metrics.surfaceWnd_ShadowSize
        .wnd.setPosition({sdw, sdw, width - 2 * sdw, height - 2 * sdw})
    }

    // Returns the themed corner radius, or zero when rounding is disabled by the surface state.
    mtd const cornerRadius()->f32
    {
        if .isMaximized or .flags.has(.NoShadow) do
            return 0
        return .app.theme.metrics.surfaceWnd_CornerRadius
    }

    private mtd paintShadow()
    {
        if .flags.has(.NoShadow) do
            return

        let metrics = &.app.theme.metrics
        let layers  = metrics.surfaceWnd_ShadowLayers
        if layers == 0 or metrics.surfaceWnd_ShadowSpread <= 0 or .app.theme.colors.wnd_Shadow.a == 0 do
            return

        var bodyRect = .wnd.surfaceRect()
        bodyRect.offset(metrics.surfaceWnd_ShadowOffsetX, metrics.surfaceWnd_ShadowOffsetY)

        let baseAlpha = cast(f32) .app.theme.colors.wnd_Shadow.a
        for [i] in layers
        {
            let t          = cast(f32) (layers - i) / cast(f32) layers
            let alphaScale = (1.0 - t) * (1.0 - t)
            let alpha      = cast(u8) Math.clamp(baseAlpha * alphaScale, 0.0, 255.0)
            if alpha == 0 do
                continue

            let spread = metrics.surfaceWnd_ShadowSpread * t
            var rect   = bodyRect
            rect.inflate(spread)
            let radius = .cornerRadius() + spread
            .painter.fillRoundRect(rect, radius, radius, .app.theme.colors.wnd_Shadow.withAlpha(alpha))
        }
    }

    private mtd paintShadowOutsideBody()
    {
        if .app.theme.metrics.surfaceWnd_ShadowSize <= 0 do
            return

        let radius = .cornerRadius()
        if radius <= 0 do
            return

        let surfaceRect = Math.Rectangle{0, 0, .position.width, .position.height}

        .painter.startClippingRegion()
        .painter.fillRect(surfaceRect, Argb.White)
        .painter.setClippingRegionMode(.Clear)
        .painter.fillRoundRect(.wnd.surfaceRect(), radius, radius, Argb.White)
        .painter.endClippingRegion()
        .paintShadow()
        .painter.resetClippingRegion()
    }

    private mtd paintAlphaMask()
    {
        let rect = .wnd.surfaceRect()

        .painter.resetTransform()
        .painter.setColorMaskAlpha()
        if .app.theme.metrics.surfaceWnd_ShadowSize <= 0
        {
            .painter.fillRect(rect, Argb.Black)
            return
        }

        let radius = .cornerRadius()
        if radius > 0 do
            .painter.fillRoundRect(rect, radius, radius, Argb.Black)
        else do
            .painter.fillRect(rect, Argb.Black)
    }

    // Replaces and destroys the current user view, then attaches `view` to this surface.
    mtd setView(view: *Wnd)
    {
        if @isset(.wnd.view) and .wnd.view == view do
            return
        if @isset(.wnd.view) do
            .wnd.view.destroy()
        view.setParent(.wnd)
        .wnd.view = view
        .wnd.sendResizeEvent()
    }

    private mtd serializeState(ser: *Serializer) fail
    {
        // Save position and surface state
        if @isset(.wnd.view) and .wnd.view.id != null
        {
            catch ser.serialize(.wnd.view.id, .wnd.view.id ? Hash.Crc32.compute(.wnd.view.id) : 0, &.state) as err
            if err == null and ser.isReading()
            {
                if .isMaximized
                {
                    .setPosition(.restoredPosition)
                    .isMaximized = false
                    .showMaximized()
                }
                else
                {
                    .setPosition(.position)
                }
            }
        }

        .wnd.serializeState(ser)
    }
}

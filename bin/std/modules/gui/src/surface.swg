#global public

using Core, Pixel, Serialization

// Serializable placement and display state of a surface.
//
// This is what an application persists through [[Gui.Application.saveState]], so a field
// here keeps an alias for every name it has been written under; see [[Pixel.Image]].
struct SurfaceState
{
    position: Math.Rectangle     // Current surface bounds in physical screen pixels.

    #[Serialization.Alias("positionNotMaximized")]
    restoredPosition: Math.Rectangle     // Bounds restored after leaving a maximized state.

    isMaximized: bool     // Whether the surface is maximized.

    // Monitor scale the bounds were saved under, or zero for state written before
    // scales were recorded. Restoring on a monitor with another scale rescales the
    // sizes so the surface keeps its logical dimensions.
    savedDpiScale: f32
}

// Top-level drawable window managed by an [[Application]].
struct Surface
{
    using native: NativeSurface                // Platform-specific window state.
    app:          *Application = undefined     // Application that owns the surface.
    wnd:          *SurfaceWnd  = undefined     // Root window containing the surface view.
    userData:     #null *void                  // Optional caller-owned data.
    surfaceId:    String                       // Identifier used by cross-process custom messages.

    minSize: Math.Point     // Minimum allowed width and height in logical units; zero disables a dimension limit.
    maxSize: Math.Point     // Maximum allowed width and height in logical units; zero disables a dimension limit.

    // Window Enter stands for while no focused control claims it, or `null` for none.
    //
    // This and [[Gui.Surface.cancelButton]] are what make a form answerable without the pointer:
    // Enter runs the dominant action of the surface, Escape backs out of it. A focused button
    // always answers Enter itself, so these two only speak for a keyboard that is somewhere else —
    // in a field, in a list. Both are borrowed and never owned.
    defaultButton: #null *Wnd

    cancelButton: #null *Wnd     // Window Escape stands for, or `null` when the surface cannot be dismissed.

    flags:         SurfaceFlags = None     // Current presentation and window-manager flags.
    colorDisabled: Color                   // Animated tint used while the surface is disabled.

    // What the surface is made of and where it stands. The application creates surfaces and
    // the event loop moves them between these states; reading them tells what is on screen.
    readonly
    {
        painter: Painter          // Painter recording the surface's frame.
        rt:      RenderTarget     // Render target the frame is drawn into.

        // Physical device pixels per logical unit on the monitor showing this surface.
        // `position` is in physical screen pixels; the window tree, painting, and mouse
        // surface coordinates are logical and map through this factor.
        dpiScale: f32 = 1

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

    // Returns the logical client size of the surface.
    //
    // The window tree, painting, and mouse surface positions live in this space;
    // multiply by [[Gui.Surface.dpiScale]] to obtain physical pixels.
    mtd const size()->Math.Point
    {
        return {.position.width / .dpiScale, .position.height / .dpiScale}
    }

    // Sets the surface scale outside the native creation path.
    //
    // The native layer resolves the scale from the window's monitor; this exists for
    // the platform message handler and for the headless host, which simulates the
    // platform side in tests.
    internal mtd setDpiScaleRaw(scale: f32)
    {
        Debug.assert(scale > 0)
        .dpiScale = scale

        // A move to a denser monitor must resharpen the shared theme atlas.
        if @isset(.app.theme) and .app.theme.initialized and @isset(.app.renderer) do
            .app.theme.ensureAtlasScale(.app.renderer, scale)
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

        if .flags.has(.Border)
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
            .flags           = flags
            .wnd             = Memory.new'SurfaceWnd()
            .wnd.isAllocated = true
            .wnd.itf         = .wnd
            .wnd.type        = SurfaceWnd
            .wnd.surface     = surface
            .wnd.computeStyle()
            .applySurfaceFlags()
        }

        // `width` and `height` are the visible window the caller asked for. The margin the drop
        // shadow is cast into is chrome around that, not room taken out of it: counted inside, a
        // window would silently lose twice the margin the day the theme starts casting a shadow,
        // and every layout tuned against its size would come up short — which is exactly what
        // clipped the last field of a form off the bottom of its card.
        let margin = surface.shadowMargin()
        let outerW = width + 2 * cast(s32) margin
        let outerH = height + 2 * cast(s32) margin

        // These are logical units. The native layer resolves the monitor's scale and sizes the
        // window in physical pixels; everything after this point that touches the screen is
        // physical.
        let app = surface.app
        if app.renderer.needsNativeWindow() do
            try createNative(app, surface, x, y, outerW, outerH, flags)

        let physWidth  = cast(s32) Math.round(outerW * surface.dpiScale)
        let physHeight = cast(s32) Math.round(outerH * surface.dpiScale)
        surface.rc      = try app.renderer.createContext(surface.nativeRenderHandle(), physWidth, physHeight, mainSurface ? &mainSurface.rc : null)
        surface.painter = Painter.create(app.renderer)

        surface.minSize = {128, 128}
        let w = Math.max(surface.minSize.x * surface.dpiScale, cast(f32) physWidth)
        let h = Math.max(surface.minSize.y * surface.dpiScale, cast(f32) physHeight)

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
        let sz = .size()
        .invalidateRect({0, 0, sz.x, sz.y})
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
    // selected edges that many physical pixels away from the monitor boundary.
    mtd constrainPositionToScreen(topLeft, bottomRight = true, margin = 0'f32)
    {
        if .isMaximized or .isMinimized do
            return

        // The surface position and the constraint work in physical desktop pixels.
        let monitor = Env.monitorForPoint({.position.x, .position.y})
        var np      = .position

        if topLeft
        {
            np.x = Math.max(np.x, monitor.physicalBounds.x + margin)
            np.x = Math.min(np.x, monitor.physicalBounds.right() - margin)
            np.y = Math.max(np.y, monitor.physicalBounds.y + margin)
            np.y = Math.min(np.y, monitor.physicalBounds.bottom() - margin)
        }

        if bottomRight
        {
            np.x = Math.min(np.x, monitor.physicalBounds.right() - margin - .position.width)
            np.y = Math.min(np.y, monitor.physicalBounds.bottom() - margin - .position.height)
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

        // Round the dirty rectangle once, on the logical grid the painter clip uses:
        // deriving the physical clear scissor from the raw edges instead would put
        // the two on grids that disagree by one device pixel, leaving a cleared but
        // never-repainted seam along the dirty edge.
        var clipRect = .dirtyRect
        clipRect.round()
        .dirtyRect = {Swag.F32.Max, Swag.F32.Max, 0, 0}
        .isDirty   = false

        with var cxt: PaintContext
        {
            .painter  = &me.painter
            .renderer = me.app.renderer
            .renderer.begin(me.rc)
            .painter.begin()
        }

        // The window hierarchy records logical units; the renderer maps them to the
        // physical render target through the surface scale.
        .painter.setContentScale(.dpiScale)

        var myRect = Math.Rectangle{0, 0, .position.width, .position.height}
        .painter.pushClippingRect(clipRect)
        .painter.setColorMaskFull()

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

        // Order matters. An antialiased pen stroke replays through the renderer's no-overlap
        // path, which clears the destination alpha of the whole scissor region to use it as a
        // scratch channel and leaves it at zero — so the outline must come first, before any
        // pass whose alpha has to survive to the compositor. The silhouette then premultiplies
        // the body ink and stamps its coverage, and the shadow pass erases the margin before
        // laying its rings down, so it relies on the silhouette's fringe being in place.
        .paintBorder()
        .paintSilhouette()
        .paintShadowOutsideBody()
        .painter.end()

        // Paint to surface render target. The direct scissor works in physical
        // render-target pixels, unlike painter clip rectangles which stay logical.
        var physClip = clipRect
        physClip.x      = Math.round(clipRect.x * .dpiScale)
        physClip.y      = Math.round(clipRect.y * .dpiScale)
        physClip.width  = Math.round(clipRect.right() * .dpiScale) - physClip.x
        physClip.height = Math.round(clipRect.bottom() * .dpiScale) - physClip.y

        with cxt
        {
            .renderer.bindRenderTarget(&me.rt, vp: &myRect)
            .renderer.setScissorRect(physClip)
            .renderer.clear()
            .renderer.draw(&me.painter)
            .renderer.unbindRenderTarget()
        }

        // Paint render target to screen. This pass copies physical texels one to
        // one, so it runs unscaled: destination and source are both device pixels.
        .painter.begin()
        .painter.setContentScale(1)
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

    // `width` and `height` are in physical pixels; the window tree receives the
    // logical size derived through the surface scale.
    private mtd sendResizeEvent(width, height: f32)
    {
        .rc.width        = cast(s32) width
        .rc.height       = cast(s32) height
        .position.width  = width
        .position.height = height

        let sz  = .size()
        let sdw = .shadowMargin()
        .wnd.setPosition({sdw, sdw, sz.x - 2 * sdw, sz.y - 2 * sdw})
    }

    // Returns the transparent margin, in logical units, the surface keeps around its body.
    //
    // The drop shadow is cast into it, so a surface that takes no shadow keeps none of it and its
    // body fills the window. A maximized surface keeps its margin: the window is made that much
    // larger than the work area, so the body still covers the screen and the margin is what hangs
    // off the edges — see the maximized placement in the platform layer.
    mtd const shadowMargin()->f32
    {
        if .flags.has(.NoShadow) do
            return 0
        return .app.theme.metrics.surfaceWnd_ShadowSize
    }

    // Returns the themed corner radius, or zero when rounding is disabled by the surface state.
    mtd const cornerRadius()->f32
    {
        if .isMaximized or .flags.has(.NoShadow) do
            return 0
        return .app.theme.metrics.surfaceWnd_CornerRadius
    }

    // Returns the rectangle the outline, the silhouette and the shadow all work from.
    //
    // The three are passes over one shape and have to agree to the pixel, so the rounding
    // happens once, here — and on the DEVICE grid, not the logical one. A whole logical
    // coordinate lands between two device pixels at any fractional display scale whenever the
    // window's physical size makes it so, and the edge then reads as a half-covered column
    // whose look changes with the size parity — the same window came back crisp or soft
    // depending on the size the last session saved.
    private mtd const bodyShape()->Math.Rectangle
    {
        let k    = .dpiScale
        let body = .wnd.surfaceRect()
        let l    = Math.round(body.x * k) / k
        let t    = Math.round(body.y * k) / k
        let r    = Math.round(body.right() * k) / k
        let b    = Math.round(body.bottom() * k) / k
        return {l, t, r - l, b - t}
    }

    // Strokes the outline of the surface, above everything the hierarchy painted.
    //
    // The outline is chrome and belongs on top. Drawn with the caption instead, it was covered by
    // whatever docked against an edge: the stroke snaps to whole device pixels, so past 100% it
    // is wider than the room the caption reserves for it, and the line read at full strength
    // beside the caption, which nothing covers, and at half strength down the sides.
    private mtd paintBorder()
    {
        if !.flags.has(.Border) do
            return

        var pen = Pen.createSolid(.app.theme.colors.wnd_Border, .painter.hairline(.app.theme.metrics.wnd_BorderSize))
        pen.borderPos = .Inside

        let body   = .bodyShape()
        let radius = .cornerRadius()

        .painter.resetTransform()
        .painter.setColorMaskColor()
        if radius > 0 do
            .painter.drawRoundRect(body, radius, radius, pen)
        else do
            .painter.drawRect(body, pen)
    }

    // Casts the themed drop shadow into the transparent margin, outside the body.
    //
    // The compositor reads this window premultiplied, so a margin pixel must carry ink times
    // coverage — and the hierarchy leaves it carrying full-strength ground ink under no
    // coverage at all, because it paints the body as a square through a colour-only mask. The
    // pass therefore first erases its whole region to premultiplied nothing with a transparent
    // 'Copy' fill, then blends the rings onto that clean ground: alpha-compositing shadow ink
    // over transparent black accumulates exactly ink times coverage in the colour channels and
    // coverage in alpha, which is the premultiplied value the compositor expects. The region
    // excludes the body and the silhouette's antialiased fringe, so the arc pixels the
    // silhouette premultiplied stay untouched.
    private mtd paintShadowOutsideBody()
    {
        if .app.theme.metrics.surfaceWnd_ShadowSize <= 0 do
            return

        let radius = .cornerRadius()
        let body   = .bodyShape()

        .painter.startClippingRegion()
        .painter.fillRect({0, 0, .position.width, .position.height}, Argb.White)
        .painter.setClippingRegionMode(.Clear)
        if radius > 0 do
            .painter.fillRoundRect(body, radius, radius, Argb.White)
        else do
            .painter.fillRect(body, Argb.White)
        .painter.endClippingRegion()

        .painter.setColorMaskFull()
        .painter.setBlendingMode(.Copy)
        .painter.fillRect({0, 0, .position.width, .position.height}, Color.fromArgb(Argb.Zero))
        .painter.setBlendingMode(.Alpha)
        .paintShadow()
        .painter.resetClippingRegion()
    }

    // Builds the shadow out of nested rings, from the faint outer edge in to the body.
    //
    // The rings are filled shapes stacked on one another, so what a pixel ends up with is the
    // product of everything painted over it, not the last value written. Handing each ring the
    // alpha the profile asks for at its own distance therefore darkens the shadow with every ring
    // added, and the whole picture changes the moment the ring count is tuned for smoothness. The
    // per-ring alpha is solved from what the stack has already reached instead, so the accumulated
    // profile is the same at any ring count and the count becomes a pure quality knob: one ring
    // per device pixel of spread, below which the gradient bands and above which the extra rings
    // land on a pixel that is already covered.
    private mtd paintShadow()
    {
        let metrics = &.app.theme.metrics
        let spread  = metrics.surfaceWnd_ShadowSpread
        let color   = .app.theme.colors.wnd_Shadow
        if .flags.has(.NoShadow) or spread <= 0 or color.a == 0 do
            return

        var bodyRect = .bodyShape()
        bodyRect.offset(metrics.surfaceWnd_ShadowOffsetX, metrics.surfaceWnd_ShadowOffsetY)

        let rings      = Math.max(1, Math.ceilS32(spread * .dpiScale))
        let peak       = cast(f32) color.a / 255.0
        let baseCorner = .cornerRadius()

        var reached = 0.0'f32
        for [i] in rings
        {
            // `depth` runs 0 at the outermost ring to 1 at the body. Smoothstep gives the shadow
            // a long faint tail where it meets the desktop and a flat shoulder against the body,
            // which is what reads as air under the window rather than as an outline drawn around
            // it.
            let ringSpread = spread * cast(f32) (rings - i) / cast(f32) rings
            let depth      = 1.0 - ringSpread / spread
            let target     = peak * Math.smoothstep(0.0, 1.0, depth)

            let alpha = 1.0 - (1.0 - target) / (1.0 - reached)
            reached = target

            let quantized = cast(u8) Math.clamp(alpha * 255.0 + 0.5, 0.0, 255.0)
            if quantized == 0 do
                continue

            var rect = bodyRect
            rect.inflate(ringSpread)
            let radius = baseCorner + ringSpread
            .painter.fillRoundRect(rect, radius, radius, color.withAlpha(quantized))
        }
    }

    // Presses one of the two standard buttons of the surface, when there is one to press.
    //
    // The button is pressed the way Enter presses a focused one, so a widget that answers keys
    // at all can stand for the default or the cancel action, and a button that is down or gone
    // simply does not answer.
    private mtd pressStandardButton(button: #null *Wnd)->bool
    {
        if !button do
            return false
        if !button.isVisible() or !button.isEnabled() do
            return false
        return button.sendKeyPress(Input.Key.Return)
    }

    // Stamps the silhouette of the surface: its coverage into the alpha channel, and that
    // same coverage multiplied into the body ink.
    //
    // The compositor reads this window premultiplied, so the alpha channel — and not the
    // window rectangle — is what the user sees the surface as, and every pixel's colour must
    // carry its coverage. Inside the body the coverage is one and the ink is untouched; along
    // the antialiased edge of the arc it is fractional, and multiplying the ink by it
    // ([[Pixel.BlendingMode.DstIn]]) is what keeps the corner from compositing brighter than
    // both the window and the desktop behind it.
    private mtd paintSilhouette()
    {
        let rect   = .bodyShape()
        let radius = .cornerRadius()

        .painter.resetTransform()

        // Premultiply the body ink by the silhouette coverage.
        .painter.setColorMaskColor()
        .painter.setBlendingMode(.DstIn)
        if radius > 0 do
            .painter.fillRoundRect(rect, radius, radius, Argb.White)
        else do
            .painter.fillRect(rect, Argb.White)
        .painter.setBlendingMode(.Alpha)

        // Stamp the same coverage into the alpha channel.
        .painter.setColorMaskAlpha()
        if radius > 0 do
            .painter.fillRoundRect(rect, radius, radius, Argb.Black)
        else do
            .painter.fillRect(rect, Argb.Black)
    }

    // Applies the surface-wide keyboard navigation to a key nobody claimed, and reports whether
    // it was used.
    //
    // Tab and Shift+Tab walk the whole ring of [[Gui.FocusOrder]]; the four arrows walk the group
    // the focus stands in, so an action bar answers Left and Right by choosing between its own
    // actions. Enter and Escape press [[Gui.Surface.defaultButton]] and
    // [[Gui.Surface.cancelButton]]. Every other key belongs to whatever holds the focus, which is
    // why this runs only once the focused window and its parents have all declined the event —
    // a field keeps its caret arrows and a list keeps its rows without knowing a traversal exists.
    //
    // The arrows navigate bare only. Shift, Control, and Alt turn an arrow into a gesture of its
    // own — extend a selection, jump by word, reach a drop-down — and a surface that answered
    // those would take them from the control that declined this press but means to claim the next.
    internal mtd navigateKey(from: *Wnd, key: Input.Key, modifiers: Input.KeyModifiers)->bool
    {
        switch key
        {
        case .Tab:
            let backward = cast(bool) (modifiers & Input.KeyModifiers.Shift)
            .app.setFocusVisible(true)
            return from.focusNext(!backward)

        case .Left, .Up, .Right, .Down:
            if modifiers != .None do
                return false
            let forward = key == .Right or key == .Down
            .app.setFocusVisible(true)
            return from.focusNextInGroup(forward)

        case .Return:
            return .pressStandardButton(.defaultButton)

        case .Escape:
            return .pressStandardButton(.cancelButton)
        }

        return false
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
            // What is persisted is the window the user sized, with the transparent margin taken
            // back out of it. The margin is chrome the theme owns: left in the stored rectangle,
            // an application would come back that much smaller every time the theme reached
            // further with its shadow, and a form tuned to its card would lose its last row.
            let margin = .shadowMargin() * .dpiScale

            if !ser.isReading()
            {
                .savedDpiScale = .dpiScale
                .position.inflate(-margin)
                .restoredPosition.inflate(-margin)
            }

            defer if !ser.isReading()
            {
                .position.inflate(margin)
                .restoredPosition.inflate(margin)
            }

            catch ser.serialize(.wnd.view.id, .wnd.view.id ? Hash.Crc32.compute(.wnd.view.id) : 0, &.state) as err
            if err == null and ser.isReading()
            {
                // Bounds were saved in physical pixels of the monitor of that
                // session. When the target monitor uses another scale, rescale the
                // sizes so the surface keeps its logical dimensions. The monitor
                // scale is derived from DPI-virtualized integer widths and is a
                // fraction of a percent off the exact window scale, so an exact
                // comparison would rescale by ~0.9998 on every launch and shrink
                // the window forever; a real scale change is at least 25%.
                if .savedDpiScale > 0
                {
                    let target = Env.monitorForPoint({.position.x, .position.y})
                    if target.scaleFactor > 0 and Math.abs(target.scaleFactor - .savedDpiScale) > 0.02 * .savedDpiScale
                    {
                        let factor = target.scaleFactor / .savedDpiScale
                        .position.width          *= factor
                        .position.height         *= factor
                        .restoredPosition.width  *= factor
                        .restoredPosition.height *= factor
                    }
                }

                // The margin goes back on at the scale of this session, after any rescale above.
                .position.inflate(margin)
                .restoredPosition.inflate(margin)

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

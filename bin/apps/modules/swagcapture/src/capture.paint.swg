impl Capture
{
    // Finds the retained rendering of `f`, or null when it has none yet.
    mtd findFormCache(f: IForm)->*FormCache?
    {
        for c in .formCaches
        {
            let entry = unwrap c
            if entry.form.buffer == f.buffer do
                return entry
        }

        return null
    }

    // Marks the retained rendering of `f` for a re-render (no-op without one).
    mtd invalidateFormCache(f: IForm)
    {
        let c = .findFormCache(f)
        if c do
            c.dirty = true
    }

    // The pixels an image form shows can come from the capture background under it,
    // so a move or a background change re-renders every image form.
    mtd invalidateImageFormCaches()
    {
        for c in .formCaches
        {
            let entry = unwrap c
            if Swag.kindOf(unwrap entry.form) == FormImage do
                entry.dirty = true
        }
    }

    // Marks every retained form rendering for a re-render (theme switch).
    mtd invalidateAllFormCaches()
    {
        for c in .formCaches do
            c!.dirty = true
    }

    // Drops the cache entries whose form left the capture, before that form's memory
    // is recycled: an entry can then never match a recycled allocation. Runs on every
    // non-interactive hasChanged(), which follows every form addition and removal.
    mtd pruneFormCaches()
    {
        var i = 0'u64
        while i < .formCaches.count
        {
            let c    = unwrap .formCaches[i]
            var live = false
            for f in .forms
            {
                if f.buffer == c.form.buffer
                {
                    live = true
                    break
                }
            }

            if live
            {
                i += 1
                continue
            }

            .formCaches.deleteAt(i)
        }
    }

    // Reports whether the self-managed pixels of `f` are still the ones a retained
    // rendering baked. Image forms rebuild their texture from their own trigger
    // fields (a moved effect crops new background pixels, a pasted image arrives
    // through `dirty`); the cache honors those triggers without an undo.
    func formContentFresh(f: IForm)->bool
    {
        let fi = catch cast(*FormImage?, f)
        if not fi do
            return true

        switch fi.kind
        {
        case .Image:   return not fi.image.isValid() or (fi.texture.isValid() and fi.textureKind == fi.kind and not fi.dirty)
        case .Capture: return fi.texture.isValid() and fi.textureKind == fi.kind
        }

        return fi.texture.isValid() and
               fi.textureKind == fi.kind and
               not fi.dirty and
               fi.xc == fi.x and
               fi.yc == fi.y and
               fi.wc == fi.w and
               fi.hc == fi.h and
               fi.stc == fi.strength and
               fi.serial == fi.capture!.serialBackTexture
    }

    // Turns the painter by `degrees` about the center of `around`, and
    // moves `rect` into the turned frame, where the center is the origin.
    func turnAbout(painter: *Painter, around: Math.Rectangle, rect: *Math.Rectangle, degrees: f32)
    {
        painter.translateTransform(around.horzCenter(), around.vertCenter())
        rect.offset(-around.horzCenter(), -around.vertCenter())
        painter.rotateTransformInPlace(Math.map(degrees, -180, 180, -Math.ConstF32.Pi, Math.ConstF32.Pi))
    }

    // Puts back the painter state a form layer leaves changed.
    func restorePaintState(painter: *Painter)
    {
        with painter
        {
            .setColorMaskColor()
            .setBlendingMode(.Alpha)
            .setInterpolationMode(.Linear)
            .setAntialiased(true)
        }
    }

    // Bakes the form into a small, transparent mask. The Gaussian is
    // applied once in capture coordinates, so view zoom only scales the same
    // shadow instead of changing its radius or rebuilding full-size targets.
    func bakeFormShadow(layer: *Layer, painter: *Painter, f: IForm, bounds: Math.Rectangle, quickMode = false)->f32
    {
        let extent     = Math.max(bounds.width, bounds.height)
        let maxLogical = cast(f32, MaxFormShadowDim) / painter.contentScale()
        let scale      = Math.min(1.0'f32,
                                  (maxLogical - 2 * FormShadowMargin - 1) / extent)
        let width  = cast(s32, Math.ceil(bounds.width * scale)) + 2 * FormShadowMargin
        let height = cast(s32, Math.ceil(bounds.height * scale)) + 2 * FormShadowMargin

        layer.releaseImmediate()
        layer.begin(painter, {width: width, height: height})
        with painter
        {
            .pushTransform()
            .translateTransform(FormShadowMargin - bounds.x * scale, FormShadowMargin - bounds.y * scale)
            var cxt: FormPaintContext
            cxt.z         = scale
            cxt.quickMode = quickMode
            f.paint(painter, cxt)
            .popTransform()
        }

        layer.end()
        layer.blur(Math.max((quickMode ? 4.0'f32 : FormShadowRadius) * scale * painter.contentScale(), 0.5))
        return scale
    }

    // Places the blurred mask from its capture-space bake. The shadow's radius
    // and offset therefore grow with the form, even while the sharp content is
    // temporarily stretched during a zoom gesture.
    func drawFormShadow(layer: *Layer, formRect: Math.Rectangle, zoom, shadowScale: f32, base: *BaseForm, color: Color, releaseAfterDraw, writeAlpha: bool)
    {
        let factor = zoom / shadowScale
        let x      = formRect.x + (base.shadowOffsetX * zoom) - (FormShadowMargin * factor)
        let y      = formRect.y + (base.shadowOffsetY * zoom) - (FormShadowMargin * factor)
        layer.draw({dstRect: {x, y, layer.width * factor, layer.height * factor},
                    color: Color.fromArgb(cast(u8, 150'u32 * color.a / 255), Argb.Black),
                    interpolationMode: .Linear,
                    releaseAfterDraw: releaseAfterDraw,
                    writeAlpha: writeAlpha})
    }

    // Paints one form through its retained rendering, or returns false to use the
    // direct path.
    //
    // The direct path re-renders the form on every repaint. Here sharp content
    // and its small shadow mask live across frames: zoom can stretch the content
    // immediately, then [MaxFormCacheRefresh] forms per repaint sharpen at rest.
    // Only a content change rebuilds the shadow. Large unrotated content layers
    // retain the portion around the visible editor, bounded by [MaxFormCacheDim].
    mtd paintFormCached(painter: *Painter, clip, rect: Math.Rectangle, f: IForm, zoom: f32)->bool
    {
        let base: *BaseForm = f

        // The geometry of the direct path, without its view clip: the cache keeps the
        // whole form, so scrolling never invalidates it.
        var boundRect = f.boundRect()
        boundRect.width  = Math.max(boundRect.width, 1)
        boundRect.height = Math.max(boundRect.height, 1)
        boundRect.inflate(BaseForm.paintOverdraw(f, false))

        var pos = boundRect * zoom
        pos.offset(rect.x, rect.y)

        let noClipPos = pos
        pos.width  += pos.x - Math.round(pos.x)
        pos.height += pos.y - Math.round(pos.y)
        pos.round()

        // The retained rendering is the whole point of this. A form whose supersampled extent
        // passes the layer limit would otherwise leave the cache entirely and re-render —
        // supersampling, shadow blur and all — on every frame, which is exactly a text form on a
        // large capture at a readable zoom. Lower the sampling until the layer fits instead, and
        // give the form up only when one sample per pixel still does not: a slightly softer glyph
        // is a better answer than repainting the whole form for every mouse move.
        func layerFits(width, height: s32, scale: f32, samples: s32)->bool
        {
            let limit = cast(s32, MaxFormCacheDim / (scale * samples))
            return width <= limit and height <= limit
        }

        let scale = painter.contentScale()

        // A large form's sharp content needs only the part around the visible
        // editor. Its separate shadow mask covers the complete form at a lower
        // resolution. The editor clip includes room for forms crossing the edge.
        var cachePos = pos
        let clipped  = not base.isRotated() and
                       (not layerFits(cast(s32, pos.width), cast(s32, pos.height), scale, 1) or
                        pos.width * pos.height > clip.width * clip.height * 2)
        if clipped do
            cachePos.intersect(clip)

        let wt2 = cast(s32, cachePos.width)
        let ht2 = cast(s32, cachePos.height)
        if wt2 <= 0 or ht2 <= 0 do
            return false

        var textSuperSample = Swag.kindOf(f) == FormText ? TextFormSuperSample : 1
        while textSuperSample > 1 and not layerFits(wt2, ht2, scale, textSuperSample) do
            textSuperSample -= 1
        if not layerFits(wt2, ht2, scale, textSuperSample) do
            return false

        let origin = Math.Vector2{cachePos.x - rect.x, cachePos.y - rect.y}

        var entry = .findFormCache(f)
        if not entry
        {
            entry      = .formCaches.addNew()
            entry.form = f
        }

        let shadowDirty = entry.dirty or
                          entry.shadow.contentTarget == null or
                          entry.scale != scale or
                          not formContentFresh(f)

        let fresh = not entry.dirty and
                    entry.scale == scale and
                    entry.samples == textSuperSample and
                    entry.clipped == clipped and
                    (not clipped or
                     (entry.zoom == zoom and
                      entry.origin.x == origin.x and
                      entry.origin.y == origin.y and
                      entry.layer.width == wt2 and
                      entry.layer.height == ht2)) and
                    entry.layer.contentTarget != null and
                    formContentFresh(f)
        var sharp = fresh and entry.zoom == zoom and entry.layer.width == wt2 and entry.layer.height == ht2

        // A zoom gesture can stretch an existing layer immediately. A clipped
        // content layer remains usable while it covers the visible editor. The
        // timer rebuilds it once the gesture settles.
        let view      = unwrap .editView
        let zooming   = view.zoomTimer != null
        var reuseZoom = false
        var paintRect = cachePos
        if zooming and
           not fresh and
           not entry.dirty and
           entry.scale == scale and
           entry.layer.contentTarget != null and
           formContentFresh(f)
        {
            let ratio   = zoom / entry.zoom
            let oldRect = Math.Rectangle{rect.x + entry.origin.x * ratio,
                                         rect.y + entry.origin.y * ratio,
                                         entry.layer.width * ratio,
                                         entry.layer.height * ratio}
            var needed = view.clientRect()
            needed.offset(view.scrollPos)
            needed.inflate(32)
            needed.intersect(pos)

            // The cache was baked on whole pixel edges. Scaling those edges to
            // another zoom can leave a subpixel mismatch with the new rounded
            // form bounds; the separate blurred mask already covers that edge.
            var covered = oldRect
            covered.inflate(2)
            if covered.contains(needed)
            {
                reuseZoom = true
                paintRect = oldRect
            }
        }

        var renderNow = not fresh and not reuseZoom
        if fresh and not sharp
        {
            // The content is right but baked at another zoom: re-render a few forms
            // per repaint, and draw the rest scaled until their turn comes.
            if zooming
            {
                // The refinement timer will request the final sharp frame.
            }
            elif .cacheRefreshLeft > 0
            {
                .cacheRefreshLeft -= 1
                renderNow         = true
            }
            else
            {
                .cacheNeedsRefine = true
            }
        }

        if renderNow
        {
            entry.layer.releaseImmediate()
            entry.layer.begin(painter, {width: wt2, height: ht2, renderScale: textSuperSample})
            with painter
            {
                .pushTransform()
                if clipped do
                    .translateTransform(-origin.x * textSuperSample, -origin.y * textSuperSample)
                else do
                    .translateTransform(-boundRect.x * zoom * textSuperSample, -boundRect.y * zoom * textSuperSample)
                var cxt: FormPaintContext
                cxt.z = zoom
                cxt.renderScale = cast(textSuperSample)
                f.paint(painter, cxt)
                .popTransform()
            }

            entry.layer.end()
            entry.zoom    = zoom
            entry.scale   = scale
            entry.samples = textSuperSample
            entry.dirty   = false
            entry.clipped = clipped
            entry.origin  = origin
            sharp         = true
        }

        if base.paintShadow and shadowDirty do
            entry.shadowScale = bakeFormShadow(&entry.shadow, painter, f, boundRect)
        elif not base.paintShadow and entry.shadow.contentTarget != null do
            entry.shadow.releaseImmediate()

        let colForm = Color.fromArgb(cast(u8, Math.map(cast(f32, base.alpha), 0, 100, 0, 255)), Argb.White)
        painter.pushTransform()
        var shadowRect = pos
        if base.isRotated()
        {
            turnAbout(painter, noClipPos, &paintRect, base.rotate)
            shadowRect.offset(-noClipPos.horzCenter(), -noClipPos.vertCenter())
        }

        if base.paintShadow do
            drawFormShadow(&entry.shadow, shadowRect, zoom, entry.shadowScale, base, colForm, releaseAfterDraw: false, writeAlpha: false)

        with var drawInfo: LayerDrawInfo
        {
            .dstRect           = paintRect
            .color             = colForm
            .interpolationMode = (base.paintShadow or not sharp) ? .Linear : .Pixel
            .releaseAfterDraw  = false

            // The editor painted an opaque ground before reaching any form.
            .writeAlpha = false
        }

        entry.layer.draw(drawInfo)
        painter.popTransform()
        restorePaintState(painter)

        base.paintPos = pos
        return true
    }

    // Paints `f` directly through a temporary layer, clipped to `clip`. `quickMode`, for previews,
    // skips text supersampling and rotation and narrows the shadow; `snapMode`, for an export,
    // leaves untouched the screen position the editor recorded for the form.
    func paintForm(painter: *Painter, clip, rect: Math.Rectangle, f: IForm, zoom: f32, quickMode = false, snapMode = false, writeAlpha = true)
    {
        var boundRect = f.boundRect()
        boundRect.width  = Math.max(boundRect.width, 1)
        boundRect.height = Math.max(boundRect.height, 1)
        boundRect.inflate(BaseForm.paintOverdraw(f, quickMode))

        var clipOffset:    Math.Vector2
        var savePaintPos:  Math.Rectangle
        var saveNoClipPos: Math.Rectangle
        var wt2, ht2:      s32

        with let base: *BaseForm = f
        {
            savePaintPos = .paintPos

            .paintPos.x      = rect.x + (boundRect.x * zoom)
            .paintPos.y      = rect.y + (boundRect.y * zoom)
            .paintPos.width  = boundRect.width * zoom
            .paintPos.height = boundRect.height * zoom

            saveNoClipPos = .paintPos

            if not quickMode and not clip.isEmpty()
            {
                if .paintPos.x >= clip.right() do
                    return
                if .paintPos.y >= clip.bottom() do
                    return
                if .paintPos.x < clip.x do
                    clipOffset.x = clip.x - .paintPos.x
                if .paintPos.y < clip.y do
                    clipOffset.y = clip.y - .paintPos.y
                if .paintPos.right() > clip.right() do
                    .paintPos.setRight(clip.right())
                if .paintPos.bottom() > clip.bottom() do
                    .paintPos.setBottom(clip.bottom())
            }

            .paintPos.width  += .paintPos.x - Math.round(.paintPos.x)
            .paintPos.height += .paintPos.y - Math.round(.paintPos.y)
            .paintPos.round()

            wt2 = cast(s32, .paintPos.width - clipOffset.x)
            ht2 = cast(s32, .paintPos.height - clipOffset.y)
        }

        let textSuperSample = (not quickMode and Swag.kindOf(f) == FormText) ? TextFormSuperSample : 1
        var layer: Layer
        layer.begin(painter, {width: wt2, height: ht2, renderScale: textSuperSample})

        with painter
        {
            .pushTransform()
            .translateTransform(((-boundRect.x * zoom) - clipOffset.x) * textSuperSample, ((-boundRect.y * zoom) - clipOffset.y) * textSuperSample)
            var cxt: FormPaintContext
            cxt.z           = zoom
            cxt.renderScale = cast(textSuperSample)
            cxt.quickMode   = quickMode
            f.paint(painter, cxt)
            .popTransform()
        }

        layer.end()

        var shadow:      Layer
        var shadowScale: f32
        if base.paintShadow do
            shadowScale = bakeFormShadow(&shadow, painter, f, boundRect, quickMode)

        var colForm: Color
        if quickMode and (base.subKind == .Highlight or base.subKind == .PixSel) do
            colForm = Argb.White
        else do
            colForm = Color.fromArgb(cast(u8, Math.map(cast(f32, base.alpha), 0, 100, 0, 255)), Argb.White)

        var paintRect: Math.Rectangle
        paintRect.x      = base.paintPos.x + clipOffset.x
        paintRect.y      = base.paintPos.y + clipOffset.y
        paintRect.width  = wt2
        paintRect.height = ht2

        painter.pushTransform()

        var shadowRect = saveNoClipPos
        if not quickMode and base.isRotated()
        {
            turnAbout(painter, saveNoClipPos, &paintRect, base.rotate)
            shadowRect.offset(-saveNoClipPos.horzCenter(), -saveNoClipPos.vertCenter())
        }

        defer painter.popTransform()

        if base.paintShadow do
            drawFormShadow(&shadow, shadowRect, zoom, shadowScale, base, colForm, releaseAfterDraw: true, writeAlpha: writeAlpha)

        with var drawInfo: LayerDrawInfo
        {
            .dstRect           = paintRect
            .color             = colForm
            .interpolationMode = base.paintShadow ? .Linear : .Pixel
            .writeAlpha        = writeAlpha
        }

        layer.draw(drawInfo)
        restorePaintState(painter)

        if snapMode do
            base.paintPos = savePaintPos
    }

    // Paints the background image at `x, y` and zoom `z`, uploading it again first when it changed
    // since the last frame.
    mtd paintBackImage(painter: *Painter, x, y: f32, z: f32)
    {
        let editView = unwrap .editView
        let renderer = editView.app().renderer

        if not .backTexture.isValid() and .backImg.width > 0
        {
            .backTexture       = renderer.addImage(.backImg)
            .serialBackTexture += 1
        }

        if .backTexture.isValid()
        {
            // Re-upload the texture after a background edit.
            if .dirtyBackImg
            {
                renderer.removeTexture(&.backTexture)
                .backTexture       = renderer.addImage(.backImg)
                .dirtyBackImg      = false
                .serialBackTexture += 1
            }

            var backRect: Math.Rectangle
            if .inPlaceEdit
            {
                backRect.x      = 0
                backRect.y      = 0
                backRect.width  = editView.position.width
                backRect.height = editView.position.height
            }
            else
            {
                backRect.x      = (.backImagePos.x * z) + x
                backRect.y      = (.backImagePos.y * z) + y
                backRect.width  = .backImg.width * z
                backRect.height = .backImg.height * z
            }

            painter.setInterpolationMode(.Linear)
            painter.drawTexture(backRect, .backTexture)
        }
    }

    // Invalidates only the region a just-moved/resized form occupied before (`oldRect`,
    // in capture coordinates) and now occupies, so a single-form drag re-renders just
    // that form rather than every form.
    mtd invalidateAfterMove(iform: IForm, oldRect: Math.Rectangle)
    {
        .invalidateMovedRegion(oldRect, iform.boundRect())
    }

    // Region form of the above, shared with the body drag and the create drag, which
    // move a whole selection rather than one form: repaint the union of where the
    // content stood (`oldRect`) and where it stands now (`newRect`), both in capture
    // coordinates. Falls back to a full repaint while snap guides are (or just were)
    // visible, since those lines span the whole capture.
    mtd invalidateMovedRegion(oldRect, newRect: Math.Rectangle)
    {
        let view = .editView
        if not view do
            return

        let snapNow = .snapX != -1 or .snapY != -1
        defer me.prevSnapActive = snapNow
        if snapNow or .prevSnapActive
        {
            view.invalidate()
            return
        }

        let minx = Math.min(oldRect.x, newRect.x)
        let miny = Math.min(oldRect.y, newRect.y)
        let maxx = Math.max(oldRect.right(), newRect.right())
        let maxy = Math.max(oldRect.bottom(), newRect.bottom())

        // Union of old + new bound, padded for the drop shadow / stroke extent.
        var r = Math.Rectangle{minx, miny, maxx - minx, maxy - miny}
        r.inflate(48)

        // To view-local pixels, then pad for the gizmo handles / rotation knob.
        var local = r * view.zoom
        local.offset(.paintRect.x, .paintRect.y)
        local.inflate(56, 56)
        view.invalidateRect(local)
    }

    // Draws a dashed box around every group with a selected member.
    mtd paintGroupOutlines(painter: *Painter, rect: Math.Rectangle, zoom: f32)
    {
        var ids: Array'u64
        for s in .selection
        {
            let g = formOuterGroup(.forms[s])
            if g != 0 and not ids.contains(g) do
                ids.add(g)
        }

        for gid in ids
        {
            var bound = Math.Rectangle{Swag.F32.Max, Swag.F32.Max, 0, 0}
            for f in .forms where formOuterGroup(f) == gid
            {
                let br = f.boundRect()
                bound.x = Math.min(bound.x, br.x)
                bound.y = Math.min(bound.y, br.y)
                bound.setRight(Math.max(bound.right(), br.right()))
                bound.setBottom(Math.max(bound.bottom(), br.bottom()))
            }

            var vr = bound * zoom
            vr.offset(rect.x, rect.y)
            vr.inflate(6)
            painter.drawRect(vr, Pen.createDash(.Dash, Argb.DarkGray, 3))
            painter.drawRect(vr, Pen.createDash(.Dash, Argb.White, 1))
        }
    }

    // Paints the whole capture into `rect`: the transparency checkerboard, the background image,
    // then every form that meets `clip`, from its cache when it can.
    mtd paint(painter: *Painter, clip, rect: Math.Rectangle)
    {
        painter.fillRect(rect, Argb.LightGray)
        painter.fillRect(rect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
        painter.setParams(.Antialiased)

        .paintRect        = rect
        .cacheRefreshLeft = MaxFormCacheRefresh
        .cacheNeedsRefine = false
        let zoom = rect.width / .width

        // Cull forms against the real invalidated region, not just the full view clip.
        // When a single form is dragged we only invalidate its rectangle (see
        // GizmoRect.apply), so the surface clips the painter to that region; testing
        // each form against it lets the static forms be skipped entirely instead of
        // re-rendering all of them (with their supersampled layers + shadow blur) every
        // frame. On a full repaint the painter clip is the whole view, so nothing changes.
        var cullClip = clip
        if painter.hasClippingRect()
        {
            var pc        = painter.clippingRect()
            let transform = painter.transform()
            pc.offset(-transform.tx, -transform.ty)
            cullClip.intersect(pc)
        }

        painter.setAntialiased(false)
        .paintBackImage(painter, rect.x, rect.y, zoom)

        // A timed capture shows a form only inside its time span.
        for f in .forms where .isFormShown(f)
        {
            // Cull against the form's actual painted extent. `paintForm` inflates the bound by its
            // rendered geometry (arrow caps and thick strokes can reach beyond the tight
            // `boundRect`) and draws it offset by `rect`. Testing the raw, un-offset bound wrongly
            // hid forms whose tight bound fell just outside the clip, such as a thin arrow.
            var cull = f.boundRect()
            cull.width  = Math.max(cull.width, 1)
            cull.height = Math.max(cull.height, 1)
            cull.inflate(BaseForm.paintOverdraw(f, false))
            cull *= zoom
            cull.offset(rect.x, rect.y)
            if not cull.intersects(cullClip) do
                continue

            let clipped = f.mustClipToBound()
            if clipped
            {
                var pp = f.boundRect() * zoom
                pp.offset(rect.x, rect.y)
                painter.pushClippingRect(pp)
            }

            if not .paintFormCached(painter, clip, rect, f, zoom) do
                paintForm(painter, clip, rect, f, zoom, writeAlpha: false)
            if clipped do
                painter.popClippingRect()
        }

        for f, i in .forms where .isFormShown(f)
        {
            var flags = FormFlags.Zero
            if i == .hotForm do
                flags.add(.Hot)
            if .selection.contains(i) do
                flags.add(.Selected)

            painter.pushTransform()
            painter.translateTransform(rect.x, rect.y)
            f.paintGizmo(painter, zoom, flags)
            painter.popTransform()
        }

        // Group outline: a dashed, embossed box around each selected group communicates
        // that its forms move as one unit (the individual member gizmos still show).
        .paintGroupOutlines(painter, rect, zoom)

        if .drawSelRect
        {
            var r = Math.Rectangle{.movingStart.x, .movingStart.y, .movingEnd.x - .movingStart.x, .movingEnd.y - .movingStart.y}
            r.offset(.paintRect.x, .paintRect.y)
            painter.fillRect(r, Color.fromArgb(0x1F, Argb.Cyan))
            painter.drawRect(r, Argb.Cyan, 2)
        }

        if .snapX != -1 do
            painter.drawLine(rect.x + .snapX * zoom, rect.y, rect.x + .snapX * zoom, rect.bottom(), Argb.Purple, 2)
        if .snapY != -1 do
            painter.drawLine(rect.x, rect.y + .snapY * zoom, rect.right(), rect.y + .snapY * zoom, Argb.Purple, 2)

        // Forms drawn scaled while the zoom-refresh budget was spent sharpen over the
        // following frames: keep repainting until none is left stale.
        if .cacheNeedsRefine do
            .editView?.invalidate()
    }
}

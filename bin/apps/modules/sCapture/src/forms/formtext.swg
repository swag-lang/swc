enum FormTextAlign
{
    LeftTop
    RightBottom
    Center
}

// Field order below is the display order of the generated properties panel;
// serialization matches fields by name, so it is free to follow the UI.
#[Swag.Using(Properties)]
struct FormText
{
    using base: BaseForm

    // What the form says comes before how it is set: the reader types the words first, then
    // dresses them. A face picked above an empty box asks a question in the wrong order.
    #[Name("Text"), MultiLine]
    text: String
    #[Name("Font"), FontName, After("alignVert")]
    fontName: String
    #[Name("Font Style")]
    fontStyle = FontFamilyStyle.Regular
    #[Name("Align")]
    alignHorz = FormTextAlign.Center
    #[Name("Vertical Align")]
    alignVert = FormTextAlign.Center
    #[Name("Size"), SliderMinMax(MinFontSize, MaxFontSize)]
    fontSize: f32 = 48
    #[Name("Strength"), SliderMinMax(MinBoldSize, MaxBoldSize)]
    boldSize: f32 = 0
    lineSpacing   = 14.0

    #[Serialization.NoSerialize]
    {
        gizmo:       GizmoRect
        isDirty:     bool
        isDirtyFont: bool
        typeFace:    #null *TypeFace

        cacheFace:    #null *TypeFace
        cachebSize:   f32
        cachesSize:   f32
        cachefSize:   f32
        cacheStyle:   JoinStyle
        cacheFontN:   String
        cacheFontS:   FontFamilyStyle
        cacheBColorA: u8

        totalY:      f32
        paths:       Array'LinePathList
        borderPaths: Array'LinePathList
    }
}

impl FormText
{
    // The outline one line of text is measured and placed by.
    //
    // A form with an outline is laid out on the offset path, because that is what the reader
    // sees the edges of. Without one the border path stays empty, and the glyph path is both
    // what is painted and what answers for the extent.
    mtd measuredPath(idx: u64)->*LinePathList
    {
        let borderPath = &.borderPaths[idx]
        if borderPath.count() do
            return borderPath
        return &.paths[idx]
    }
}

impl IForm for FormText
{
    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = cast(*FormText) ptr
        return .isSameBase(ptr) and
               .fontSize == other.fontSize and
               .boldSize == other.boldSize and
               .fontName == other.fontName and
               .fontStyle == other.fontStyle and
               .joinStyle == other.joinStyle
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let dstf = cast(*FormText) dst
        let srcf = cast(*FormText) src
        dstf.fontSize  = srcf.fontSize
        dstf.boldSize  = srcf.boldSize
        dstf.joinStyle = srcf.joinStyle
        dstf.fontName  = srcf.fontName
        dstf.fontStyle = srcf.fontStyle
        dstf.scale     = srcf.scale
    }

    mtd impl mustClipToBound()->bool
    {
        return true
    }

    mtd impl canRotate()->bool
    {
        return .subKind == .None
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        let xa = cast(s32) (movingStart.x / zoom)
        let ya = cast(s32) (movingStart.y / zoom)
        let xb = cast(s32) (localPos.x / zoom)
        let yb = cast(s32) (localPos.y / zoom)
        .setBaseForm(xa, ya, xb - xa, yb - ya)
        if evt.kind == .Released and evt.button == .Left do
            return false
        return true
    }

    mtd impl moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .moveRectForm(newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl scaleBaseForm(scale: f32)
    {
        .x = cast(s32) (.x * scale)
        .y = cast(s32) (.y * scale)
        .w = cast(s32) (.w * scale)
        .h = cast(s32) (.h * scale)
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .setRectForm(newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        .x += newPosX
        .y += newPosY
    }

    mtd impl movePoint(pt: u32, newPosX, newPosY: s32) {}

    mtd impl boundRect()->Math.Rectangle
    {
        return .rectFormBound()
    }

    mtd impl mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        return .gizmo.mouse(view, pos, evt)
    }

    mtd impl paintGizmo(painter: *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            .gizmo.rect          = .boundRect() * z
            .gizmo.rotateEnabled = .canRotate()
            .gizmo.rotateValue   = .rotate
            .gizmo.paint(painter, !flags.has(.Selected))
        }
    }

    mtd impl isInside(pt: Math.Point)->bool
    {
        return false
    }

    mtd impl hitTest(pt: Math.Point, z: f32)->bool
    {
        let pp = .boundRect() * z
        return pp.contains(pt)
    }

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        var cxtCpy = cxt
        cxtCpy.z = 1

        // The preview range is what the sample cell can hold, outline included: a glyph set at
        // the size the document uses fills its cell edge to edge and is cut by it, which reads
        // as a broken preset rather than as a big one.
        let bSize = BaseForm.adaptSize(.borderSize, MinTextBorderSize, MaxTextBorderSize, cxtCpy, 2, 4)
        let fSize = BaseForm.adaptSize(.fontSize, MinFontSize, MaxFontSize, cxtCpy, 16, 28)
        let sSize = BaseForm.adaptSize(.boldSize, MinBoldSize, MaxBoldSize, cxtCpy, 1, 2)
        let z     = cxt.z

        let boundRect = .boundRect() * z
        var pp        = boundRect
        pp.inflate(-bSize * 0.5)

        // Paint is a render path and must not mutate serialized document state: writing
        // back into .text fights in-place editing and desyncs undo/serialization. Use a
        // local fallback for drawing/measuring only, leaving .text untouched.
        var renderText = .text
        if renderText.isEmpty()
        {
            renderText = "A"
            .isDirty   = true
        }

        // Font
        if !.typeFace or .isDirtyFont
        {
            .isDirtyFont = false
            if !.fontName.length do
                .typeFace = null
            else
            {
                let en = FontFamily.findSystemFont(.fontName)
                .typeFace = catch FontFamily.createTypeFace(en, .fontStyle)
            }
        }

        var face = .typeFace
        if !face
        {
            switch .fontStyle
            {
            case .Regular:    face = g_App.theme.res.defaultTypeFaceR
            case .Bold:       face = g_App.theme.res.defaultTypeFaceB
            case .Italic:     face = g_App.theme.res.defaultTypeFaceI
            case .BoldItalic: face = g_App.theme.res.defaultTypeFaceBI
            }
        }

        if face != .cacheFace or
           bSize != .cachebSize or
           fSize != .cachefSize or
           sSize != .cachesSize or
           .joinStyle != .cacheStyle or
           .fontName != .cacheFontN or
           .fontStyle != .cacheFontS or
           .cacheBColorA != .borderColor.a
        {
            .isDirty = true
        }

        let tokens = Tokenize.split(renderText, '\n'rune)
        if .isDirty
        {
            .isDirty      = false
            .cacheFace    = face
            .cachesSize   = sSize
            .cachebSize   = bSize
            .cachefSize   = fSize
            .cacheStyle   = .joinStyle
            .cacheFontN   = .fontName
            .cacheFontS   = .fontStyle
            .cacheBColorA = .borderColor.a

            .paths.clear()
            .borderPaths.clear()
            .paths.resize(tokens.count)
            .borderPaths.resize(tokens.count)

            .totalY = 0
            for t, idx in tokens
            {
                let pathl = &.paths[idx]
                pathl[] = expect face!.buildStringOutline(t, cast() fSize, cast() sSize)
                pathl.flatten(.High)
                pathl.clean()

                let borderPath = &.borderPaths[idx]
                if !Math.isZeroEpsilon(bSize) and .borderColor.a
                {
                    borderPath[] = expect face!.buildStringOutline(t, cast() fSize, cast() sSize)
                    borderPath.flatten(.Normal)
                    borderPath.clean()
                    borderPath.offset(bSize, .joinStyle, 0.25)
                    borderPath.clean()
                }

                // With no border, the line is as tall as the glyph outline itself.
                if borderPath.count() do
                    .totalY += (borderPath.maxBounds.y - borderPath.minBounds.y)
                else do
                    .totalY += (pathl.maxBounds.y - pathl.minBounds.y)
            }
        }

        let zscale  = z * (cxt.quickMode ? 1 : Math.map(.scale, 0, 100, 1'f32, 2'f32))
        let rscale  = cxt.renderScale
        let pscale  = zscale * rscale
        var y0      = 0'f32
        let addSize = (bSize + sSize) * zscale

        let count = .paths.count

        // A line is placed by the outline that is actually painted. With no border to offset,
        // the border path is empty and its bounds are zero, so measuring it alone put every
        // line of a plain text form at zero height and started the glyph at the middle of the
        // box instead of centering it there.
        var totalYZ = 0'f32
        for &pathl, idx in .paths
        {
            let mp = .measuredPath(idx)
            totalYZ += (mp.maxBounds.y - mp.minBounds.y) * zscale
        }

        if count > 1 do
            totalYZ += cast(f32) (count - 1) * (.lineSpacing * zscale)

        let aV = cxt.quickMode ? FormTextAlign.Center : .alignVert
        let aH = cxt.quickMode ? FormTextAlign.Center : .alignHorz
        switch aV
        {
        case .LeftTop:     y0 = pp.y + addSize
        case .Center:      y0 = pp.vertCenter() - (totalYZ * 0.5)
        case .RightBottom: y0 = pp.bottom() - addSize - totalYZ
        }

        for &pathl, idx in .paths
        {
            let borderPath = &.borderPaths[idx]
            let mp         = .measuredPath(idx)
            let wt         = (mp.maxBounds.x - mp.minBounds.x) * zscale
            let ht         = (mp.maxBounds.y - mp.minBounds.y) * zscale

            var x0 = 0'f32
            switch aH
            {
            case .LeftTop:     x0 = pp.x + addSize
            case .Center:      x0 = pp.horzCenter() - (wt * 0.5)
            case .RightBottom: x0 = pp.right() - (wt + addSize)
            }

            let tt    = painter.transform()
            let drawX = x0 - (mp.minBounds.x * zscale)
            let drawY = y0 - (mp.minBounds.y * zscale)

            painter.pushTransform()
            var localTransform = tt
            localTransform.tx = 0
            localTransform.ty = 0
            painter.setTransform(localTransform)
            painter.scaleTransform(pscale, pscale)
            painter.translateTransform(tt.tx, tt.ty)
            painter.translateTransform(drawX * rscale, drawY * rscale)

            if !Math.isZeroEpsilon(bSize) and .borderColor.a do
                painter.fillPath(borderPath, .borderColor)

            if .backColor.a do
                painter.fillPath(pathl, .backColor)

            painter.popTransform()

            // Next line
            y0 += ht + (.lineSpacing * zscale)
        }
    }

    mtd impl setup(capt: *Capture)
    {
        .capture = capt
        .gizmo.setupForForm(me)
    }
}

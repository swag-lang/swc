enum FormTextAlign
{
    LeftTop
    RightBottom
    Center
}

struct FormText
{
    using base:     BaseForm
    fontSize:       f32 = 48
    boldSize:       f32 = 0
    text:           String
    alignHorz       = FormTextAlign.Center
    alignVert       = FormTextAlign.Center
    lineSpacing     = 14.0
    fontStyle       = FontFamilyStyle.Regular
    fontName:       String

    #[Serialization.NoSerialize]
    {
        gizmo:            GizmoRect
        isDirty:          bool
        isDirtyFont:      bool
        typeFace:         *TypeFace

        cacheFace:        *TypeFace
        cachebSize:       f32
        cachesSize:       f32
        cachefSize:       f32
        cacheStyle:       JoinStyle
        cacheFontN:       String
        cacheFontS:       FontFamilyStyle
        cacheBColorA:     u8

        totalY:           f32
        paths:            Array'LinePathList
        borderPaths:      Array'LinePathList
    }
}

impl IForm for FormText
{
    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = cast(*FormText) ptr
        return .borderColor == other.borderColor and
               .borderSize == other.borderSize and
               .backColor == other.backColor and
               .alpha == other.alpha and
               .fontSize == other.fontSize and
               .boldSize == other.boldSize and
               .paintShadow == other.paintShadow and
               .fontName == other.fontName and
               .fontStyle == other.fontStyle and
               .joinStyle == other.joinStyle
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        let dstf = cast(*FormText) dst
        let srcf = cast(*FormText) src
        dstf.borderColor = srcf.borderColor
        dstf.borderSize  = srcf.borderSize
        dstf.backColor   = srcf.backColor
        dstf.alpha       = srcf.alpha
        dstf.fontSize    = srcf.fontSize
        dstf.boldSize    = srcf.boldSize
        dstf.paintShadow = srcf.paintShadow
        dstf.joinStyle   = srcf.joinStyle
        dstf.fontName    = srcf.fontName
        dstf.fontStyle   = srcf.fontStyle
        dstf.scale       = srcf.scale
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
        if evt.kind == .MouseReleased and evt.button == .Left do
            return false
        return true
    }

    mtd impl moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .x += newPosX
        .y += newPosY
        .w += newSizeX
        .h += newSizeY
    }

    mtd impl scaleBaseForm(val: f32)
    {
        .x = cast(s32) (.x * val)
        .y = cast(s32) (.y * val)
        .w = cast(s32) (.w * val)
        .h = cast(s32) (.h * val)
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        if newSizeX < 0
        {
            .x = newPosX + newSizeX
            .w = -newSizeX
        }
        else
        {
            .x = newPosX
            .w = newSizeX
        }

        if newSizeY < 0
        {
            .y = newPosY + newSizeY
            .h = -newSizeY
        }
        else
        {
            .y = newPosY
            .h = newSizeY
        }
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        .x += newPosX
        .y += newPosY
    }

    mtd impl movePoint(pt: u32, newPosX, newPosY: s32) {}

    mtd impl boundRect()->Math.Rectangle
    {
        return Math.Rectangle{.x, .y, .w, .h}
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

        let bSize = BaseForm.adaptSize(.borderSize, MinTextBorderSize, MaxTextBorderSize, cxtCpy, 2, 4)
        let fSize = BaseForm.adaptSize(.fontSize, MinFontSize, MaxFontSize, cxtCpy, 20, 48)
        let sSize = BaseForm.adaptSize(.boldSize, MinBoldSize, MaxBoldSize, cxtCpy, 1, 2)
        let z     = cxt.z

        let boundRect = .boundRect() * z
        var pp        = boundRect
        pp.inflate(-bSize * 0.5)

        if .text.isEmpty()
        {
            .text    = "A"
            .isDirty = true
        }

        // Font
        if !.typeFace or .isDirtyFont
        {
            .isDirtyFont = false
            if !.fontName.length do
                .typeFace = null
            else
            {
                let en = FontFamily.getFromOs(.fontName)
                .typeFace = catch FontFamily.createTypeFace(en, .fontStyle)
            }
        }

        var face = .typeFace
        if !face
        {
            switch .fontStyle
            {
            case Regular:
                face = g_App.theme.res.defaultTypeFaceR
            case Bold:
                face = g_App.theme.res.defaultTypeFaceB
            case Italic:
                face = g_App.theme.res.defaultTypeFaceI
            case BoldItalic:
                face = g_App.theme.res.defaultTypeFaceBI
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

        let tokens = Tokenize.split(.text, '\n''rune)
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
            foreach t, idx in tokens
            {
                let pathl = &.paths[idx]
                assume face.getStringOutline(pathl, t, cast() fSize, cast() sSize)
                pathl.flatten(.High)
                pathl.clean()
                if !pathl.paths.count
                {
                    pathl.bvMin = {0, 0}
                    pathl.bvMax = {0, 0}
                }

                let borderPath = &.borderPaths[idx]
                if !Math.isZeroEpsilon(bSize) and .borderColor.a
                {
                    assume face.getStringOutline(borderPath, t, cast() fSize, cast() sSize)
                    borderPath.flatten(.Normal)
                    borderPath.clean()
                    borderPath.offset(bSize, .joinStyle, 0.25)
                    borderPath.clean()
                }

                if !borderPath.paths.count
                {
                    borderPath.bvMin = pathl.bvMin
                    borderPath.bvMax = pathl.bvMax
                }

                .totalY += (borderPath.bvMax.y - borderPath.bvMin.y)
            }
        }

        let zscale  = z * (cxt.quickMode ? 1 : Math.map(.scale, 0, 100, 1'f32, 2'f32))
        let rscale  = cxt.renderScale
        let pscale  = zscale * rscale
        var y0      = 0'f32
        let addSize = (bSize + sSize) * zscale

        let count = .paths.count

        var totalYZ = 0'f32
        foreach &pathl in .borderPaths
        {
            totalYZ += (pathl.bvMax.y - pathl.bvMin.y) * zscale
        }
        if count > 1 do
            totalYZ += cast(f32) (count - 1) * (.lineSpacing * zscale)

        let aV = cxt.quickMode ? FormTextAlign.Center : .alignVert
        let aH = cxt.quickMode ? FormTextAlign.Center : .alignHorz
        switch aV
        {
        case LeftTop:
            y0 = pp.y + addSize
        case Center:
            y0 = pp.vertCenter() - (totalYZ * 0.5)
        case RightBottom:
            y0 = pp.bottom() - addSize - totalYZ
        }

        foreach &pathl, idx in .paths
        {
            let borderPath = &.borderPaths[idx]
            let wt         = (borderPath.bvMax.x - borderPath.bvMin.x) * zscale
            let ht         = (borderPath.bvMax.y - borderPath.bvMin.y) * zscale

            var x0 = 0'f32
            switch aH
            {
            case LeftTop:
                x0 = pp.x + addSize
            case Center:
                x0 = pp.horzCenter() - (wt * 0.5)
            case RightBottom:
                x0 = pp.right() - (wt + addSize)
            }

            let tt  = painter.curState.transform
            let drawX = x0 - (borderPath.bvMin.x * zscale)
            let drawY = y0 - (borderPath.bvMin.y * zscale)

            painter.pushTransform()
            painter.curState.transform.tx = 0
            painter.curState.transform.ty = 0
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

        with me.gizmo
        {
            .roundShape        = true
            .anchorSize        = 10
            .trackChange       = true
            .paintSimpleBorder = false
            .paintBigBorder    = true
        }

        let form = me
        .gizmo.sigChanged = func|form|(g, first, hitMove)
        {
            g.apply(form, first, hitMove)
        }
        .gizmo.sigRotate = func|form|(g, first, last, angle)
        {
            g.applyRotate(form, first, last, angle)
        }
    }
}

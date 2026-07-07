enum FormShapeKind
{
    Ellipse
    Rectangle
    RoundRectangle
}

const MinRoundSize = 10.0
const MaxRoundSize = 50.0

struct FormShape
{
    using base:     BaseForm
    kind:           FormShapeKind = Ellipse
    roundSize:      f32 = 10

    #[Serialization.NoSerialize]
    {
        gizmo: GizmoRect
    }
}

impl IForm for FormShape
{
    mtd impl canRotate()->bool
    {
        return .subKind == .None
    }

    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = cast(*FormShape) ptr
        return .isSameBase(ptr) and
               .kind == other.kind and
               .roundSize == other.roundSize
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let dstf = cast(*FormShape) dst
        let srcf = cast(*FormShape) src
        dstf.kind      = srcf.kind
        dstf.roundSize = srcf.roundSize
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        let xa = cast(s32) (movingStart.x / zoom)
        let ya = cast(s32) (movingStart.y / zoom)
        var xb = cast(s32) (localPos.x / zoom)
        var yb = cast(s32) (localPos.y / zoom)
        .setBaseForm(xa, ya, xb - xa, yb - ya)

        var xbu = 0
        var ybu = 0
        .capture.snap(&xbu, &ybu, true, true, 0, cast(IForm) me)
        xb += xbu
        yb += ybu

        // Same size
        let shiftPressed = cast(bool) (evt.modifiers & .Shift)
        if shiftPressed
        {
            let ww = xb - xa
            let hh = yb - ya
            if ww > hh do
                yb = ya + ww
            else do
                xb = xa + hh
        }

        .setBaseForm(xa, ya, xb - xa, yb - ya)

        if evt.kind == .MouseReleased and evt.button == .Left do
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
            let col = .subKind == .PixSel ? Argb.Yellow : Argb.White
            .gizmo.paint(painter, !flags.has(.Selected), col)
        }
    }

    mtd impl isInside(pt: Math.Point)->bool
    {
        switch .kind
        {
        case Ellipse:
            let br  = .boundRect()
            let pos = Math.Vector2{pt.x, pt.y}
            let cen = Math.Vector2{br.horzCenter(), br.vertCenter()}
            return Math.Geometry.isInEllipse(pos, cen, br.width * 0.5, br.height * 0.5)
        default:
            return true
        }
    }

    mtd impl hitTest(pt: Math.Point, z: f32)->bool
    {
        return BaseForm.drawHitTest(me, pt, z)
    }

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        var dash  = .dashStyle
        var bSize = cxt.hitTest ? Math.max(.borderSize, 5) : .borderSize
        bSize = BaseForm.adaptSize(bSize, MinBorderSize, MaxBorderSize, cxt)
        let rSize = BaseForm.adaptSize(.roundSize, MinRoundSize, MaxRoundSize, cxt)
        var bk    = .backColor

        if .subKind == .PixSel
        {
            (bSize, dash) = .applyPixSelStyle(painter, cxt)
            bk.a = 5
        }

        let z   = cxt.z
        let pp  = .boundRect() * z
        var pen = Pen.createDash(dash, .borderColor, bSize)
        pen.borderPos = .Inside
        let backBrush = Brush.createHatch(.CheckBoardLarge, Argb.DarkGray)

        if cxt.quickMode and .alpha != 100 and .subKind == .Highlight do
            bk.a = .highlightAlpha()

        #[Swag.Complete]
        switch .kind
        {
        case Ellipse:
            let sizeX = pp.width * 0.5
            let sizeY = pp.height * 0.5
            if cxt.quickMode and .alpha != 100 and .subKind == .Highlight do
                painter.fillEllipse(pp.x + sizeX, pp.y + sizeY, sizeX, sizeY, backBrush)
            painter.fillEllipse(pp.x + sizeX, pp.y + sizeY, sizeX, sizeY, bk)
            painter.drawEllipse(pp.x + sizeX, pp.y + sizeY, sizeX, sizeY, pen)

        case Rectangle:
            if .borderColor.a and (pp.width <= 2 * bSize or pp.height < 2 * bSize) do
                painter.fillRect(pp, .borderColor)
            else
            {
                if cxt.quickMode and .alpha != 100 and .subKind == .Highlight do
                    painter.fillRect(pp, backBrush)
                painter.fillRect(pp, bk)
                painter.drawRect(pp, pen)
            }

        case RoundRectangle:
            var pp1 = pp
            pp1.inflate(-bSize * 0.5)
            if cxt.quickMode and .alpha != 100 and .subKind == .Highlight do
                painter.fillRoundRect(pp1, rSize, rSize, backBrush)
            painter.fillRoundRect(pp1, rSize, rSize, bk)
            painter.drawRoundRect(pp, rSize, rSize, pen)
        }
    }

    mtd impl setup(capt: *Capture)
    {
        .capture = capt
        .gizmo.setupForForm(cast(IForm) me)
    }
}

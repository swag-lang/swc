#global #[Swag.ExplicitNullability]
struct FormPaintContext
{
    z:             f32
    renderScale:   f32 = 1
    quickMode:     bool
    hitTest:       bool
}

#[Swag.EnumFlags]
enum FormFlags
{
    Zero
    Hot
    Selected
}

enum FormSubKind
{
    None
    Highlight
    PixSel
}

interface IForm
{
    mtd paintGizmo(painter: #nonull *Painter, z: f32, flags: FormFlags);
    mtd paint(painter: #nonull *Painter, cxt: FormPaintContext);
    mtd mouse(view: #nonull *EditView, pos: Math.Point, evt: #nonull *MouseEvent)->bool;
    mtd isInside(pt: Math.Point)->bool;
    mtd hitTest(pt: Math.Point, z: f32)->bool;
    mtd boundRect()->Math.Rectangle;
    mtd moveForm(newPosX, newPosY: s32);
    mtd moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32);
    mtd scaleBaseForm(scale: f32);
    mtd setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32);
    mtd movePoint(pt: u32, newPosX, newPosY: s32);
    mtd edit(evt: #nonull *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool;
    mtd setup(capt: #null *Capture);
    mtd isSame(ptr: #nonull *BaseForm)->bool;
    mtd copy(dst, src: #nonull *BaseForm);
    mtd mustClipToBound()->bool { return false; }
    mtd canRotate()->bool { return false; }
}

// The property panel is generated from the fields carrying a Properties.Name attribute
// (see PropWnd): the attribute set declares the editor (slider, checkbox, min/max box)
// and the panel builds itself by reflection, undo included. Field order below is the
// display order of the generated panel; serialization matches fields by name, so it is
// free to follow the UI. A Category paints as a thin separator above its field.
#[Swag.Using(Properties)]
struct BaseForm
{
    // x/y/w/h carry no grid attribute: the panel appends its own compact x/y and w/h
    // rows right after the generated content (PropWnd.propXY).
    x, y:                s32 = 0
    w, h:                s32 = 32

    // The text forms edit this as "Outline" with a thinner range (PropWnd.bindGrid)
    #[Name("Tickness"), SliderMinMax(MinBorderSize, MaxBorderSize)]
    borderSize:          f32 = 5
    #[Name("Joins")]
    joinStyle            = JoinStyle.Round
    #[Name("Line"), BoolCombo("Straight", "Bezier")]
    bezier:              bool
    #[Category("Effects"), Name("Scale"), SliderMinMax(0, 100), Unit("%")]
    scale:               f32 = 0
    #[Name("Rotate"), SliderMinMax(0, 360), Unit("°")]
    rotate:              f32 = 0
    #[Name("Opacity"), SliderMinMax(0, 100), Unit("%")]
    alpha:               u8 = 100
    #[Name("Shadow"), BoolCombo("No Shadow", "Small")]
    paintShadow:         bool = true

    shadowOffsetX:       f32 = 2
    shadowOffsetY:       f32 = 2
    borderColor:         Color = Argb.White
    backColor:           Color = Argb.Red
    dashStyle:           DashStyle = None
    // Unused, kept because it is serialized: removing it would fail the decoding of
    // existing capture files and of the quick styles saved in the application config.
    quickModeOpaque:     bool
    subKind:             FormSubKind = None

    // Group membership as a path of group ids, outermost first (empty = ungrouped).
    // Grouping prepends a fresh id shared by every member; ungrouping pops the front,
    // so nested groups collapse one level at a time. Ids are minted by Capture and
    // remapped on paste; the field is style-agnostic (copyBase/isSameBase ignore it).
    groups:              Array'u64

    #[Serialization.NoSerialize]
    {
        capture:      #null *Capture
        paintPos:     Math.Rectangle
        freeze:       bool
    }
}

impl BaseForm
{
    func adaptSize(size: f32, minSize, maxSize: f32, cxt: FormPaintContext, dstMin: f32 = 4, dstMax: f32 = 8)->f32
    {
        if !cxt.quickMode do
            return size * cxt.z
        return Math.map(size * cxt.z, minSize, maxSize, dstMin, dstMax)
    }

    // Style fields shared by every form type. Each form's isSame/copy compares and
    // copies these through the two helpers below, then handles its own fields.
    // FormImage opts out of the backColor comparison for its processed kinds.
    mtd isSameBase(other: #nonull *BaseForm, compareBackColor = true)->bool
    {
        if compareBackColor and .backColor != other.backColor do
            return false
        return .borderColor == other.borderColor and
               .borderSize == other.borderSize and
               .alpha == other.alpha and
               .subKind == other.subKind and
               .dashStyle == other.dashStyle and
               .paintShadow == other.paintShadow
    }

    func copyBase(dst, src: #nonull *BaseForm)
    {
        dst.borderColor = src.borderColor
        dst.borderSize  = src.borderSize
        dst.backColor   = src.backColor
        dst.alpha       = src.alpha
        dst.subKind     = src.subKind
        dst.dashStyle   = src.dashStyle
        dst.paintShadow = src.paintShadow
    }

    // Default geometry of the axis-aligned box forms (shape, step, text, image).
    mtd moveRectForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .x += newPosX
        .y += newPosY
        .w += newSizeX
        .h += newSizeY
    }

    // Assign the box, normalizing a negative size so width/height stay positive.
    mtd setRectForm(newPosX, newPosY, newSizeX, newSizeY: s32)
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

    mtd rectFormBound()->Math.Rectangle
    {
        return Math.Rectangle{.x, .y, .w, .h}
    }

    // PixSel forms share one look: an almost transparent fill and a thin dashed
    // outline, widened when hit-testing so the outline stays clickable.
    mtd applyPixSelStyle(painter: #nonull *Painter, cxt: FormPaintContext)->{ bSize: f32, dash: DashStyle }
    {
        var result: retval
        if cxt.hitTest
        {
            result.bSize = 10
            result.dash  = .None
        }
        else
        {
            result.bSize = 2
            result.dash  = .Dash
        }

        .borderColor = g_App.theme.colors.btnIcon_Icon
        painter.removeParams(.Antialiased)
        return result
    }

    // In quick mode a translucent highlight is previewed by remapping its alpha to
    // the full range (a checkerboard brush behind it shows the transparency).
    mtd highlightAlpha()->u8
    {
        return cast(u8) Math.map(cast(f32) .alpha, 0, 100, 0, 255)
    }

    func drawHitTest(itf: IForm, pt: Math.Point, z: f32)->bool
    {
        // The form paints into an un-rotated buffer (rotation is applied around the
        // center at draw time), so un-rotate the test point to match.
        let base = cast(#nonull *BaseForm) @dataof(itf)
        var pos  = Math.Vector2{pt.x, pt.y}
        if base.subKind != .Highlight and base.subKind != .PixSel and !Math.isZeroEpsilon(base.rotate)
        {
            let br  = itf.boundRect()
            let cx  = br.horzCenter() * z
            let cy  = br.vertCenter() * z
            let ang = -Math.toRadians(base.rotate)
            let c   = Math.cos(ang)
            let s   = Math.sin(ang)
            let dx  = pos.x - cx
            let dy  = pos.y - cy
            pos.x = cx + (c * dx - s * dy)
            pos.y = cy + (s * dx + c * dy)
        }

        // Cheap rejection before tessellating the whole form: nothing is painted
        // beyond the overdraw pad around the bound (strokes, caps, shadows).
        var bound = itf.boundRect() * z
        bound.inflate(FormPaintOverdraw)
        if !bound.contains(pos.x, pos.y) do
            return false

        var painter: Painter{fake: true}
        painter.begin()

        var cxt: FormPaintContext
        cxt.z       = z
        cxt.hitTest = true
        itf.paint(&painter, cxt)

        painter.end()

        for cmd in painter.commandBuffer
        {
            if cmd.id != .DrawTriangles do
                continue
            for var i = 0; i < cmd.drawTriangles.count; i += 3
            {
                let tri = cmd.drawTriangles.start + i
                let xx0 = painter.vertexBuffer[tri].pos
                let xx1 = painter.vertexBuffer[tri + 1].pos
                let xx2 = painter.vertexBuffer[tri + 2].pos
                if Math.Geometry.isInTriangle(pos, xx0, xx1, xx2) do
                    return true
            }
        }

        return false
    }
}

// Shared geometry of the forms defined by a cloud of points (FormDraw & FormPolygon)
func offsetPoints(points: #nonull *Array'Math.Vector2, newPosX, newPosY: s32)
{
    for &pt in dref points
    {
        pt.x += newPosX
        pt.y += newPosY
    }
}

func scalePointsBy(points: #nonull *Array'Math.Vector2, scale: f32)
{
    for &pt in dref points do
        pt.x, pt.y *= scale
}

// Rescale all the points from the given bound to the given box.
// Guard against a near-zero divisor (colinear/degenerate shapes): a zero width
// or height would yield inf/NaN and destroy every point, so keep scale at 1.
func scalePointsTo(points: #nonull *Array'Math.Vector2, bound: Math.Rectangle, newPosX, newPosY, newSizeX, newSizeY: s32)
{
    let fx = Math.isZeroEpsilon(bound.width) ? 1'f32 : newSizeX / bound.width
    let fy = Math.isZeroEpsilon(bound.height) ? 1'f32 : newSizeY / bound.height

    for &pt in dref points
    {
        pt.x = ((pt.x - bound.x) * fx) + newPosX
        pt.y = ((pt.y - bound.y) * fy) + newPosY
    }
}

// Bounding rectangle of the points, optionally padded (half border size)
func boundOfPoints(points: #nonull *Array'Math.Vector2, pad: f32 = 0)->Math.Rectangle
{
    var result: retval

    var x0 = Swag.F32.Max
    var y0 = Swag.F32.Max
    // Max accumulators must start at -F32.Max (not 0), else shapes entirely in
    // negative coordinates stay clamped at 0 and produce oversized/misplaced bounds.
    var x1 = -Swag.F32.Max
    var y1 = -Swag.F32.Max
    for &pt in dref points
    {
        x0 = Math.min(x0, pt.x - pad)
        y0 = Math.min(y0, pt.y - pad)
        x1 = Math.max(x1, pt.x + pad)
        y1 = Math.max(y1, pt.y + pad)
    }

    result.x      = x0
    result.y      = y0
    result.width  = x1 - x0
    result.height = y1 - y0
    return result
}

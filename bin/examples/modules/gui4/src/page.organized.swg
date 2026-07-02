using Core, Gui, Pixel
using Properties

enum SurfaceShadow
{
    None
    Hard
    Soft
}

// Showcase struct for the grouping & decorator features: nested "A/B" categories become indented
// subgroups, and the Heading / Gap / HelpBox attributes inject divider / spacer / note rows.
#[Swag.Using(Gui.Properties)]
struct Gui4Organized
{
    // "Transform" is a top-level group; "Transform/Advanced" nests a subgroup indented under it.
    #[Category("Transform"), Description("World position of the object.")]
    position: Math.Point = {120, 80}

    #[SliderMinMax(0.25, 4.0), EditSize(280), Description("Uniform scale factor.")]
    scale: f32 = 1.0

    #[Category("Transform/Advanced"), Description("Shear applied after scaling.")]
    skew: f32 = 0

    #[Description("Rotation pivot, relative to the object origin.")]
    pivot: Math.Point = {0, 0}

    // "Material" opens with a HelpBox note, then later a Gap + Heading sub-divider ("Lighting").
    #[Category("Material"), HelpBox("These settings drive how the surface is shaded in the viewport."), Properties.Opaque, Description("Base albedo color.")]
    baseColor: Color = Argb.CornflowerBlue

    #[SliderMinMax(0, 1), EditSize(280), Description("0 = mirror, 1 = fully matte.")]
    roughness: f32 = 0.5

    #[SliderMinMax(0, 1), EditSize(280), Description("Metallic reflectance.")]
    metallic: f32 = 0.1

    #[Gap(16), Heading("Lighting"), Description("Cast shadows onto other objects.")]
    castShadows: bool = true

    #[Description("Receive shadows cast by other objects.")]
    receiveShadows: bool = true

    // A second nested subgroup: "Material/Advanced".
    #[Category("Material/Advanced"), Description("Render both facings of the surface.")]
    doubleSided: bool = false

    #[Description("Shadow filtering quality.")]
    shadowMode: SurfaceShadow = SurfaceShadow.Soft
}

func createOrganizedPage(parent: *Wnd)
{
    g_Inspector = PropertiesCtrl.create(parent, {0, 0, InspectorWidth, 10}, .Grid, .FindBar)
    g_Inspector.dockStyle = .Left
    g_Inspector.margin.z  = SplitGap
    g_Inspector.prop.sizeEditValue = 300
    g_Inspector.prop.setColumnSize(180)
    g_Inspector.addStruct(g_Organized, "Object")
    g_Inspector.prop.sigChanged += &onPropertiesChanged

    let frame = createPanel(parent, "Live preview",
        "The object below reflects every field: position, scale, skew, color, roughness gloss, metallic tint, shadow and outline.", {})
    frame.dockStyle = .Center
    g_Preview = frame.view
    g_Preview.hookOnEvent = &onOrganizedPreviewEvent
}

// A single "object" whose look is driven by the Gui4Organized fields, so editing the grid on the
// left is immediately visible on the right (like the other pages).
func drawOrganizedPreview(painter: *Painter, canvas: Math.Rectangle)
{
    painter.setParams(.Antialiased)
    let o = &g_Organized

    // Scaled base size, clamped so it always fits the canvas.
    let pad = 26.0
    var w = Math.min(200.0 * o.scale, canvas.width  - 2 * pad)
    var h = Math.min(130.0 * o.scale, canvas.height - 2 * pad - 24)

    let x = canvas.x + Math.clamp(cast(f32) o.position.x, pad, Math.max(canvas.width  - w - pad, pad))
    let y = canvas.y + Math.clamp(cast(f32) o.position.y, pad, Math.max(canvas.height - h - pad - 24, pad))

    // 'skew' shears the top edge relative to the bottom.
    let shear = Math.clamp(o.skew, -h, h)
    let topL  = Math.Vector2{x + shear,     y}
    let topR  = Math.Vector2{x + w + shear, y}
    let botR  = Math.Vector2{x + w,         y + h}
    let botL  = Math.Vector2{x,             y + h}

    // Ground contact shadow (receiveShadows).
    if o.receiveShadows do
        painter.fillRoundRect({x + 12, y + h + 6, Math.max(w - 24, 1.0), 10}, 5, 5, Color.fromArgb(55'u8, Argb.Black))

    // Cast shadow, its softness set by the shadow mode.
    if o.castShadows and o.shadowMode != .None
    {
        let off   = o.shadowMode == .Soft ? 18.0 : 9.0
        let alpha = o.shadowMode == .Soft ? 60'u8 : 120'u8
        var sh: Array'Math.Vector2
        sh.add({topL.x + off, topL.y + off})
        sh.add({topR.x + off, topR.y + off})
        sh.add({botR.x + off, botR.y + off})
        sh.add({botL.x + off, botL.y + off})
        painter.fillPolygon(sh.toSlice(), Brush{color: Color.fromArgb(alpha, Argb.Black)})
    }

    // Body fill: base color blended toward a cool grey by 'metallic'.
    let fillCol = Color.getBlendKeepAlpha(o.baseColor, Color.fromArgb(0xFFC8C8D0), o.metallic * 0.5)
    var body: Array'Math.Vector2
    body.add(topL)
    body.add(topR)
    body.add(botR)
    body.add(botL)
    painter.fillPolygon(body.toSlice(), Brush{color: fillCol})

    // Gloss on the upper half: stronger as roughness drops (a shiny surface).
    let gloss = Math.clamp(1.0 - o.roughness, 0.0, 1.0)
    if gloss > 0.02
    {
        let midL = Math.Vector2{(topL.x + botL.x) * 0.5, (topL.y + botL.y) * 0.5}
        let midR = Math.Vector2{(topR.x + botR.x) * 0.5, (topR.y + botR.y) * 0.5}
        var hi: Array'Math.Vector2
        hi.add(topL)
        hi.add(topR)
        hi.add(midR)
        hi.add(midL)
        painter.fillPolygon(hi.toSlice(), Brush{color: Color.fromArgb(cast(u8) (gloss * 120), Argb.White)})
    }

    // Outline: a subtle edge, or a bold accent when double-sided.
    let borderCol = o.doubleSided ? Color.fromArgb(Argb.Orange) : Color.getBlendKeepAlpha(fillCol, Argb.Black, 0.32)
    let bw        = o.doubleSided ? 3.0 : 1.0
    painter.drawLine(topL.x, topL.y, topR.x, topR.y, borderCol, bw)
    painter.drawLine(topR.x, topR.y, botR.x, botR.y, borderCol, bw)
    painter.drawLine(botR.x, botR.y, botL.x, botL.y, borderCol, bw)
    painter.drawLine(botL.x, botL.y, topL.x, topL.y, borderCol, bw)

    // Pivot marker (relative to the object origin).
    let px = x + cast(f32) o.pivot.x
    let py = y + cast(f32) o.pivot.y
    painter.fillCircle(px, py, 4, Color.fromArgb(Argb.OrangeRed))
    painter.drawLine(px - 9, py, px + 9, py, Color.fromArgb(Argb.OrangeRed), 1)
    painter.drawLine(px, py - 9, px, py + 9, Color.fromArgb(Argb.OrangeRed), 1)
}

func onOrganizedPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.bc.painter
        let rect    = view.getClientRect()
        painter.fillRect(rect, view.getThemeColors().view_Bk)

        // Leave room at the top for the panel caption drawn by createPanel.
        var canvas = rect
        canvas.y      += 74
        canvas.height  = Math.max(canvas.height - 74, 1.0)
        drawOrganizedPreview(painter, canvas)
    }

    return false
}

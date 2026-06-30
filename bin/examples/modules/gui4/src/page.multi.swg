using Core, Gui, Pixel
using Properties

enum TileStyle
{
    Flat
    Raised
    Outline
}

// A simple struct edited several at a time by the multi-selection page.
#[Swag.Using(Gui.Properties)]
struct TileData
{
    #[Description("Caption drawn on the tile.")]
    label: String

    #[Category("Look"), Description("Fill color of the tile.")]
    fill: Color

    #[Description("Corner radius in pixels."), SliderMinMax(0, 40)]
    radius: f32

    #[Description("Tile height in pixels."), SliderMinMax(48, 150)]
    height: f32

    #[Description("Draw a drop shadow under the tile.")]
    shadow: bool

    #[Description("Edge rendering style.")]
    style: TileStyle
}

// Per-field validation, surfaced by the grid as an accent bar + badge + tooltip.
impl IPropertyNotify for TileData
{
    mtd impl validateItem(_list: *Properties, item: *PropertiesItem)->PropValidationResult
    {
        switch item.nameCrc
        {
        case Hash.Crc32.compute(#nameof(TileData.label)):
            if .label.length == 0 do
                return {.Error, "A tile label is required."}

        case Hash.Crc32.compute(#nameof(TileData.radius)):
            if .radius > 30 do
                return {.Warning, "A large radius can clip the tile content."}

        case Hash.Crc32.compute(#nameof(TileData.height)):
            if .height < 60 do
                return {.Info, "Short tiles hide the secondary line."}
        }

        return {}
    }
}

// (Re)bind the grid to the first g_TileCount tiles. Changing the count rebuilds the grid
// (the bound instance set changes), so we destroy and recreate the Properties widget.
func rebuildMultiGrid()
{
    if !g_MultiHost do
        return

    if g_MultiProps do
        g_MultiProps.destroy()

    g_MultiProps           = Properties.create(g_MultiHost, {}, .List)
    g_MultiProps.dockStyle = .Center
    g_MultiProps.sizeEditValue = 240

    var bases: Array'(*u8)
    for i in g_TileCount do
        bases.add(cast(*u8) &g_Tiles[i])
    g_MultiProps.addStructMulti(TileData, bases.toSlice(), Format.toString("Editing % tile%", g_TileCount, g_TileCount > 1 ? "s" : ""))

    g_MultiProps.sigChanged += func(_list, _item)
    {
        if g_Preview do
            g_Preview.invalidate()
    }

    g_MultiHost.applyLayout()
}

func setTileCount(count: s32)
{
    if g_TileCount == count do
        return
    g_TileCount = count

    for i in 3 do
        if g_MultiRadios[i] do
            g_MultiRadios[i].setChecked(cast(s32) i + 1 == count)

    rebuildMultiGrid()
    if g_Preview do
        g_Preview.invalidate()
}

func createMultiPage(parent: *Wnd)
{
    // Left column: the radio selector on top, the multi-edit grid below.
    g_MultiHost           = Wnd.create'Wnd(parent, {0, 0, 360, 10})
    g_MultiHost.dockStyle = .Left
    g_MultiHost.margin.z  = SplitGap

    let radioRow           = Wnd.create'Wnd(g_MultiHost, {0, 0, 0, 44})
    radioRow.dockStyle     = .Top
    radioRow.margin.w      = 8

    discard createText(radioRow, "Edit:", {0, 0, 48, 44})

    for i in 3
    {
        let label = Format.toString("% tile%", i + 1, i > 0 ? "s" : "")
        with let rb = RadioButton.create(radioRow, label, {56 + cast(f32) i * 110, 0, 108, 44})
        {
            .setChecked(cast(s32) i + 1 == g_TileCount)
            .sigChanged += func|i|(_rb)
            {
                setTileCount(cast(s32) i + 1)
            }
        }
        g_MultiRadios[i] = rb
    }

    rebuildMultiGrid()

    // Right: the live tiles.
    let frame      = createPanel(parent, "Tiles", "The first N tiles are bound to the grid. Selected tiles are outlined; editing a field changes all of them.", {})
    frame.dockStyle = .Center
    g_Preview       = frame.view
    g_Preview.hookOnEvent = &onTilesPreviewEvent
}

func tileStyleName(style: TileStyle)->string
{
    switch style
    {
    case Flat:
        return "Flat"
    case Raised:
        return "Raised"
    case Outline:
        return "Outline"
    }
    unreachable
}

func drawTile(painter: *Painter, slot: Math.Rectangle, tile: *TileData, selected: bool)
{
    let theme   = g_View.getTheme()
    // Map the editable height onto the slot so changes are visible without overflowing.
    let frac    = Math.clamp((tile.height - 48.0) / (150.0 - 48.0), 0.0, 1.0)
    let h       = Math.clamp(slot.height * (0.45 + 0.5 * frac), 24.0, slot.height - 8)
    let w       = Math.min(slot.width, 360.0)
    var body    = Math.Rectangle{slot.horzCenter() - w * 0.5, slot.vertCenter() - h * 0.5, w, h}

    if tile.shadow
    {
        let shadow = Math.Rectangle{body.x + 6, body.y + 8, body.width, body.height}
        painter.fillRoundRect(shadow, tile.radius, tile.radius, Color.fromArgb(70'u8, Argb.Black))
    }

    if tile.style == .Outline
    {
        painter.fillRoundRect(body, tile.radius, tile.radius, theme.colors.view_Bk)
        painter.drawRoundRect(body, tile.radius, tile.radius, tile.fill, 3.0)
    }
    else
    {
        painter.fillRoundRect(body, tile.radius, tile.radius, tile.fill)
        if tile.style == .Raised do
            painter.drawRoundRect(body, tile.radius, tile.radius, Color.getBlendKeepAlpha(tile.fill, Argb.White, 0.35), 1.0)
    }

    // Selection outline around the whole slot.
    if selected
    {
        var sel = Math.Rectangle{body.x - 8, slot.y + 2, body.width + 16, slot.height - 4}
        painter.drawRoundRect(sel, 10, 10, theme.colors.prop_FocusBorder, 2.0)
    }

    let titleFont = theme.createDefaultFont(15, .Bold)
    let infoFont  = theme.createDefaultFont(12)
    let textCol   = tile.style == .Outline ? theme.colors.label_Text : Color.getBlendKeepAlpha(tile.fill, Argb.Black, 0.72)
    painter.drawStringCenter(body.horzCenter(), body.vertCenter() - 9, tile.label.toString(), titleFont, textCol)
    painter.drawStringCenter(body.horzCenter(), body.vertCenter() + 12, tileStyleName(tile.style), infoFont, textCol.withAlpha(210'u8))
}

func onTilesPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.bc.painter
        let rect    = view.getClientRect()
        painter.fillRect(rect, view.getThemeColors().view_Bk)

        // Stack the tiles vertically so all three are always visible regardless of the
        // panel width.
        const TopReserve = 70.0          // leave room for the panel title/subtitle
        const Gap        = 16.0
        let count        = @countof(g_Tiles)
        let avail        = Math.max(rect.height - TopReserve - Gap, 1.0)
        let slotH        = (avail - cast(f32) (count - 1) * Gap) / cast(f32) count
        var y            = rect.y + TopReserve
        for i in count
        {
            let slot = Math.Rectangle{rect.x + Gap, y, rect.width - 2 * Gap, slotH}
            drawTile(painter, slot, &g_Tiles[i], cast(s32) i < g_TileCount)
            y += slotH + Gap
        }
    }

    return false
}

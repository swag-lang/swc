// The scrolling sheet the inspector reports a whole theme structure in.
//
// Every row is built from reflection over `ThemeColors` or `ThemeMetrics`, so a value
// added to either struct appears here without this file being touched. That is the
// point: a sheet listing a hand-written set of names would be wrong the first time
// somebody adds a color, which is exactly when a reader most needs it.

using Core, Gui, Pixel

// What one sheet reports.
enum SheetKind
{
    Colors       // Every color of the active palette, over the grounds it is drawn on.
    Palettes     // Every color of the four shipped palettes, side by side.
    Metrics      // Every measurement of the active theme.
}

const RowHeight    = 22.0
const GroupHeight  = 36.0
const SheetPadding = 10.0
const NameWidth    = 300.0
const SwatchWidth  = 128.0
const SwatchGap    = 10.0
const HexWidth     = 108.0
const FlagWidth    = 96.0
const SwatchInset  = 3.0

// One line of a sheet: either the head of a family, or one value of it.
struct SheetRow
{
    group: bool     // Whether the row opens a family instead of carrying a value.

    name: String     // Reflected field name, or the family name on a group row.
    text: String     // The value as text: the hexadecimal color, or the measurement.

    colors: [5] Color     // One color per palette; only the first is filled outside the palette sheet.

    // Whether the dark and the light variant of the Swag palette resolve this color to the
    // same value. A handful legitimately do — the close button, the notice chips, the
    // rich-text slots, anything that means one thing on any ground — and every other one is
    // a part that did not follow the reader into the other mode.
    shared: bool
}

// The content of the sheet, painted directly rather than built out of widgets.
//
// Three hundred and thirty colors is three hundred and thirty windows, each with a style,
// a layout entry and an event path, to show what four rectangles and a string say.
struct SheetView
{
    using wnd: Wnd

    #[Swag.Late]
    host: *SheetWnd

    kind:       SheetKind
    filter:     String
    issuesOnly: bool     // Whether the palette sheet keeps only the rows it flags.
    rows:       Array'SheetRow

    // Ground each palette column is drawn over, so a swatch is judged against the surface
    // its own theme would put it on. Cached with the rows: building a palette is cheap,
    // building one per swatch per frame is not.
    grounds: [5] Color

    fontName: #null *Font     // Face the names are listed in.
    fontMono: #null *Font     // Face the values are listed in, so digits line up.
    fontHead: #null *Font     // Face a family head is set in.
}

impl SheetView
{
    // Rebuilds the rows and repaints. Cheap enough to run on every keystroke of the filter.
    mtd rebuild()
    {
        .rows.clear()

        switch #complete .kind
        {
        case .Colors:   .buildColors()
        case .Palettes: .buildPalettes()
        case .Metrics:  .buildMetrics()
        }

        .invalidate()
    }

    mtd setKind(kind: SheetKind)
    {
        .kind = kind
        .host.setScrollPos(0, 0)
        .rebuild()
    }

    mtd setFilter(filter: string)
    {
        .filter = String.toLower(filter)
        .host.setScrollPos(0, 0)
        .rebuild()
    }

    mtd setIssuesOnly(issuesOnly: bool)
    {
        .issuesOnly = issuesOnly
        .host.setScrollPos(0, 0)
        .rebuild()
    }

    // Whether `name` survives the filter, which matches anywhere in the name and ignores case.
    mtd const keeps(name: string)->bool
    {
        if .filter.length == 0 do
            return true
        return String.toLower(name).contains(.filter.toString())
    }

    // The family a reflected name belongs to: everything before the underscore, or the
    // shared roots that carry no prefix at all.
    func familyOf(name: string)->string
    {
        var length = 0'u64
        while length < @countof(name) and name[length] != '_' do
            length += 1

        if length == @countof(name) do
            return "shared"
        return @mkstring(@dataof(name), length)
    }

    // Adds the head of a family when the previous row belonged to another one.
    mtd openFamily(family: string)
    {
        if .rows.count and .rows.back().group and .rows.back().name == family do
            return
        if .rows.count and !.rows.back().group and familyOf(.rows.back().name.toString()) == family do
            return

        with var row: SheetRow
        {
            .group = true
            .name  = family
        }

        .rows.add(row)
    }

    private mtd buildColors()
    {
        let colors = &app.theme.colors
        let type   = cast(const *Swag.TypeInfoStruct) #typeof(ThemeColors)

        for field in type.fields
        {
            let name = field.name!
            if !.keeps(name) do
                continue
            .openFamily(familyOf(name))

            let value = dref cast(const *Color) (cast([*] u8) colors + field.offset)

            with var row: SheetRow
            {
                .name      = name
                .text      = Format.toString("%{X8}", value.argb)
                .colors[0] = value
            }

            .rows.add(row)
        }
    }

    private mtd buildPalettes()
    {
        var palettes: [5] ThemeColors
        for i in ThemeVariantCount
        {
            palettes[i] = variantColors(cast(ThemeVariant) cast(s32) i)
            .grounds[i] = palettes[i].bk
        }

        let type = cast(const *Swag.TypeInfoStruct) #typeof(ThemeColors)
        for field in type.fields
        {
            let name = field.name!
            if !.keeps(name) do
                continue

            var row: SheetRow
            row.name = name
            for i in ThemeVariantCount do
                row.colors[i] = dref cast(const *Color) (cast([*] u8) &palettes[i] + field.offset)

            let swagDark  = row.colors[cast(s32) ThemeVariant.SwagDark]
            let swagLight = row.colors[cast(s32) ThemeVariant.SwagLight]
            row.shared = swagDark.a != 0 and swagLight.a != 0 and swagDark == swagLight
            row.text   = row.shared ? "both modes" : ""

            if .issuesOnly and !row.shared do
                continue

            .openFamily(familyOf(name))
            .rows.add(row)
        }
    }

    private mtd buildMetrics()
    {
        let metrics = &app.theme.metrics
        let type    = cast(const *Swag.TypeInfoStruct) #typeof(ThemeMetrics)

        for field in type.fields
        {
            let name = field.name!
            if !.keeps(name) do
                continue
            .openFamily(familyOf(name))

            let raw = cast([*] u8) metrics + field.offset

            with var row: SheetRow
            {
                .name = name
                if field.pointedType == #typeof(f32) do
                    .text = Format.toString("%", dref cast(const *f32) raw)
                elif field.pointedType == #typeof(u32) do
                    .text = Format.toString("%", dref cast(const *u32) raw)
                else
                {
                    let vec = dref cast(const *Math.Vector4) raw
                    .text = Format.toString("% % % %", vec.x, vec.y, vec.z, vec.w)
                }
            }

            .rows.add(row)
        }
    }

    // Resolves the three faces the sheet is set in, once per theme.
    private mtd ensureFonts()
    {
        .fontName = app.theme.createDefaultFont(13)
        .fontMono = app.theme.createDefaultFontFS(13)
        .fontHead = app.theme.createDefaultFont(15, .Bold)
    }

    // Draws `text` left-aligned inside `rect`, on the vertical center of the row.
    func drawCell(painter: *Painter, rect: Math.Rectangle, text: string, font: *Font, color: Color)
    {
        let ms = Painter.measureString(text, font)
        painter.drawString(rect.x, rect.vertCenter() - (ms.height * 0.5) - (font.ascent - ms.ascent), text, font, color)
    }

    // Draws one color over `ground`, and over a checkerboard when it is not opaque.
    //
    // A translucent color painted on one ground only reports the blend, not the value:
    // the checkerboard is what tells a reader that `0x5FFFFFFF` is a veil and not a gray.
    mtd drawSwatch(painter: *Painter, rect: Math.Rectangle, color: Color, ground: Color)
    {
        painter.fillRect(rect, ground)
        if !color.isOpaque()
        {
            var checker = rect
            checker.width *= 0.5
            painter.fillRect(checker, Argb.LightGray)
            painter.fillRect(checker, Brush.createHatch(.CheckBoard, Argb.DarkGray))
        }

        painter.fillRect(rect, color)
        painter.drawRect(rect, app.theme.colors.border, 1)
    }
}

impl IWnd for SheetView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .ensureFonts()

        let painter = evt.paintContext.painter
        let colors  = &app.theme.colors
        let client  = .paddedClientRect()
        let width   = Math.max(client.width - 2 * SheetPadding, 1.0)

        var y = client.y + SheetPadding
        for &row in .rows
        {
            let height = row.group ? GroupHeight : RowHeight
            let rect   = Math.Rectangle{client.x + SheetPadding, y, width, height}
            y += height

            if row.group
            {
                let head = Math.Rectangle{rect.x, rect.y + 12, rect.width, rect.height - 12}
                drawCell(painter, head, row.name.toString(), .fontHead!, colors.label_Text)

                // The palette sheet repeats its column captions on every family head: with
                // three hundred rows scrolling under a single caption row, a reader four
                // screens down has no way to tell which column is which.
                if .kind == .Palettes
                {
                    var captionX = rect.x + NameWidth
                    for i in ThemeVariantCount
                    {
                        drawCell(painter, {captionX + 2, head.y, SwatchWidth, head.height}, variantName(cast(ThemeVariant) cast(s32) i), .fontName!, colors.label_TextFaint)
                        captionX += SwatchWidth + SwatchGap
                    }
                }

                painter.drawLine(rect.x, rect.bottom() - 3, rect.right(), rect.bottom() - 3, colors.listItem_Line)
                continue
            }

            drawCell(painter, {rect.x, rect.y, NameWidth, height}, row.name.toString(), .fontName!, colors.label_Text)

            var x = rect.x + NameWidth
            switch #complete .kind
            {
            case .Colors:
                let swatch = Math.Rectangle{x, rect.y + SwatchInset, SwatchWidth, height - 2 * SwatchInset}
                .drawSwatch(painter, swatch, row.colors[0], colors.bk)
                .drawSwatch(painter, {swatch.x + SwatchWidth + SwatchGap, swatch.y, SwatchWidth, swatch.height}, row.colors[0], colors.view_Bk)
                x += 2 * SwatchWidth + 2 * SwatchGap
                drawCell(painter, {x, rect.y, HexWidth, height}, row.text.toString(), .fontMono!, colors.label_TextLight)

            case .Palettes:
                for i in ThemeVariantCount
                {
                    let swatch = Math.Rectangle{x, rect.y + SwatchInset, SwatchWidth, height - 2 * SwatchInset}
                    .drawSwatch(painter, swatch, row.colors[i], .grounds[i])
                    x += SwatchWidth + SwatchGap
                }

                if row.shared
                {
                    let flag = Math.Rectangle{x, rect.y, FlagWidth, height}
                    painter.fillRect({flag.x, flag.y + SwatchInset, FlagWidth, height - 2 * SwatchInset}, colors.embInfo_CriticalBk)
                    drawCell(painter, {flag.x + 6, flag.y, FlagWidth - 12, height}, row.text.toString(), .fontMono!, colors.embInfo_CriticalText)
                }

            case .Metrics:
                drawCell(painter, {x, rect.y, HexWidth, height}, row.text.toString(), .fontMono!, colors.label_TextLight)
            }
        }

        .host.setScrollSize(0, y - client.y + SheetPadding)
    }
}

// Scrolling host of the sheet, and the only window the page layout has to place.
struct SheetWnd
{
    using scrollWnd: ScrollWnd

    #[Swag.Late]
    view: *SheetView
}

impl SheetWnd
{
    func create(parent: *Wnd)->*SheetWnd
    {
        let result = Wnd.create'SheetWnd(parent, {})
        result.setFrameForm(.Square)
        result.setFrameFlags(.Borders)
        result.view      = result.createView'SheetView()
        result.view.host = result
        result.view.rebuild()
        return result
    }
}

impl IWnd for SheetWnd
{
    // A palette switch changes every swatch and every hexadecimal string on the sheet.
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged and @isset(.view) do
            .view.rebuild()
    }
}

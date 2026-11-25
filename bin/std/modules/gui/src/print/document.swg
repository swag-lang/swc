#global internal
#global namespace Print

using Core, Core.Math, Pixel

enum Paper
{
    A4
    Letter
    Legal
}

enum Placement
{
    Fit
    Center
    Actual
}

enum Failure
{
    InvalidPage
    InvalidRange
    UnsupportedPaper
    PrinterUnavailable
    PrinterFailed
    Cancelled
}

struct PrintError
{
    kind: Failure
}

struct PageSetup
{
    paper:     Paper
    landscape: bool
    margin:    f32 = 36
    placement: Placement
}

struct Sheet
{
    size:      Point
    imageable: Rectangle
}

struct Printer
{
    name:      String
    id:        String
    instance:  String
    isDefault: bool
}

struct JobOptions
{
    setup:  PageSetup
    first:  u64
    end:    u64
    copies: u32 = 1
}

enum ContentKind
{
    Image
    Pdf
    Text
}

struct Document
{
    kind:     ContentKind
    name:     String
    image:    Image
    imageDpi: f32 = 96
    pdf:      Pdf.Reader
    text:     String
    tabWidth: u32 = 4
}

struct TextRow
{
    start: u64
    end:   u64
}

struct Layout
{
    late document: *Document
    sheet:         Sheet
    content:       Rectangle
    placement:     Placement
    rows:          Array'TextRow
    face:          *TypeFace?
    rowHeight:     f32
    rowsPerPage:   u64
    pageCount:     u64
}

const PointsPerInch      = 72.0'f32
const MillimetersPerInch = 25.4'f32
const OutputDpi          = 300.0'f32
const TextSize           = 10'u32

func paperSize(paper: Paper)->Point
{
    switch paper
    {
    case .A4:     return {210 * PointsPerInch / MillimetersPerInch, 297 * PointsPerInch / MillimetersPerInch}
    case .Letter: return {612, 792}
    case .Legal:  return {612, 1008}
    }
}

func pdfSheet(setup: PageSetup)->Sheet
{
    var size = paperSize(setup.paper)
    if setup.landscape do
        size = {size.y, size.x}
    return {size, {0, 0, size.x, size.y}}
}

func checkCancelled() fail
{
    if Swag.isCancelled() do
        fail PrintError{.Cancelled}
}

func prepare(document: *Document, sheet: Sheet, setup: PageSetup)->Layout fail
{
    let content = Rectangle.intersect({setup.margin, setup.margin, sheet.size.x - 2 * setup.margin, sheet.size.y - 2 * setup.margin}, sheet.imageable)
    if not Math.isFinite(content.width) or
       not Math.isFinite(content.height) or
       content.width <= 0 or
       content.height <= 0 do
        fail PrintError{.UnsupportedPaper}

    var result: #returntype
    result.document  = document
    result.sheet     = sheet
    result.content   = content
    result.placement = setup.placement

    switch document.kind
    {
    case .Image:
        if not document.image.isValid() or
           document.imageDpi <= 0 or
           not Math.isFinite(document.imageDpi) do
            fail PrintError{.InvalidPage}
        result.pageCount = 1

    case .Pdf:
        result.pageCount = document.pdf.pageCount()

    case .Text:
        try result.paginateText()
    }

    if not result.pageCount do
        fail PrintError{.InvalidPage}
    return result
}

impl Layout
{
    mtd const sourceSize(index: u64)->Point fail
    {
        if index >= .pageCount do
            fail PrintError{.InvalidRange}
        if .document.kind == .Pdf do
            return try .document.pdf.pageSize(index)
        let scale = PointsPerInch / .document.imageDpi
        return {.document.image.width * scale, .document.image.height * scale}
    }

    mtd const pagePlacement(size: Point)->Rectangle
    {
        var scale = Math.min(.content.width / size.x, .content.height / size.y)
        switch .placement
        {
        case .Fit:    break
        case .Center: scale = Math.min(1.0, scale)
        case .Actual: scale = 1
        }

        let width  = size.x * scale
        let height = size.y * scale
        return {.content.horzCenter() - width * 0.5, .content.vertCenter() - height * 0.5, width, height}
    }

    mtd const clips(first, end: u64)->bool fail
    {
        if .document.kind == .Text or .placement != .Actual do
            return false
        for index in first until end
        {
            let size = try .sourceSize(index)
            if size.x > .content.width or size.y > .content.height do
                return true
        }

        return false
    }

    mtd paginateText() fail
    {
        .face = try embeddedTypeFace(true, .Regular)
        var cache: FontCache
        let font = cache.createFont(.face, TextSize, .Msdf)
        .rowHeight   = Math.ceil(font.height * 1.2)
        .rowsPerPage = cast(u64, Math.floor(.content.height / .rowHeight))
        if not .rowsPerPage do
            fail PrintError{.UnsupportedPaper}

        let text    = .document.text.toSlice()
        let tab     = font.getGlyphDesc(' ').advanceX * font.scale() * cast(f32, .document.tabWidth)
        var start   = 0'u64
        var offset  = 0'u64
        var breakAt = 0'u64
        var width   = 0.0'f32
        while offset < text.count
        {
            let {c, eat} = Utf8.decodeRune(text[offset until text.count])
            if not eat do
                fail PrintError{.InvalidPage}
            if c == '\r' or c == '\n'
            {
                .rows.add({start, offset})
                offset += eat
                if c == '\r' and offset < text.count and text[offset] == '\n' do
                    offset += 1
                start   = offset
                breakAt = offset
                width   = 0
                try checkCancelled()
                continue
            }

            let glyphAdvance = c == '\t' ? (Math.floor(width / tab) + 1) * tab - width : font.getGlyphDesc(c).advanceX * font.scale()
            if width + glyphAdvance > .content.width and offset > start and glyphAdvance > 0
            {
                let end = breakAt > start ? breakAt : offset
                .rows.add({start, end})
                start   = end
                offset  = end
                breakAt = end
                width   = 0
                try checkCancelled()
                continue
            }

            offset += eat
            width  += glyphAdvance
            if c == ' ' or c == '\t' do
                breakAt = offset
        }

        if start < offset or .rows.isEmpty() do
            .rows.add({start, offset})
        .pageCount = (.rows.count - 1) / .rowsPerPage + 1
    }

    mtd const drawText(painter: *Painter, index: u64)
    {
        let font  = painter.renderer().fontCache().createFont(unwrap .face, TextSize, .Msdf)
        let first = index * .rowsPerPage
        let end   = Math.min(first + .rowsPerPage, .rows.count)
        var run: ShapedRun
        let ink   = Brush.createSolid(Color.fromArgb(Argb.Black))
        for row in first until end
        {
            let span = .rows[row]
            let line = .document.text.toString()[span.start until span.end]
            Painter.shapeRunInto(&run, line, font, .document.tabWidth)
            painter.drawShapedRun(.content.x, .content.y + cast(f32, row - first) * .rowHeight, &run, font, ink)
        }
    }

    mtd const render(index: u64, dpi: f32)->Image fail
    {
        if index >= .pageCount or dpi <= 0 or not Math.isFinite(dpi) do
            fail PrintError{.InvalidPage}
        try checkCancelled()

        let scale  = dpi / PointsPerInch
        let width  = cast(s32, Math.ceil(.sheet.size.x * scale))
        let height = cast(s32, Math.ceil(.sheet.size.y * scale))
        var picture: Image
        var place:   Rectangle
        if .document.kind != .Text
        {
            let size = try .sourceSize(index)
            if size.x <= 0 or size.y <= 0 do
                fail PrintError{.InvalidPage}
            place = .pagePlacement(size)
            if .document.kind == .Pdf
            {
                // Decode only the part of a large actual-size page that can reach the sheet.
                let visible   = Rectangle.intersect(place, .content)
                let pageScale = place.width / size.x
                let region    = Rectangle{(visible.x - place.x) / pageScale, (visible.y - place.y) / pageScale,
                                          visible.width / pageScale, visible.height / pageScale}
                let page = try .document.pdf.loadPage(index)
                picture = try page.render({scale: scale * pageScale, sourceRect: region})
                place   = visible
            }
        }

        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        var context = #move try renderer.createContext(null, width, height)
        defer renderer.deleteContext(&context)

        renderer.begin(context)
        renderer.init()
        var target = renderer.createRenderTarget(width, height)
        if not target.colorBuffer.isValid()
        {
            renderer.end()
            fail PrintError{.InvalidPage}
        }

        var texture: Texture
        if .document.kind == .Image do
            texture = renderer.addImage(.document.image)
        elif .document.kind == .Pdf do
            texture = renderer.addImage(picture)
        renderer.end()

        var painter = Painter.create(renderer)
        painter.setContentScale(scale)
        painter.begin()
        painter.bindRenderTarget(&target, false)
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.White))
        painter.setColorMaskColor()
        painter.pushClippingRect(.content)
        if .document.kind == .Text do
            .drawText(&painter, index)
        elif texture.isValid() do
            painter.drawTexture(place, texture)
        painter.popClippingRect()
        painter.unbindRenderTarget()
        painter.end()

        renderer.begin(context)
        defer
        {
            if texture.isValid() do
                renderer.removeTexture(&texture)
            renderer.deleteRenderTarget(&target)
            renderer.end()
        }

        if .document.kind != .Text and not texture.isValid() do
            fail PrintError{.InvalidPage}
        try painter.render()
        var result: #returntype = renderer.readRenderTarget(&target, 0, 0, width, height)
        if not result.isValid() do
            fail PrintError{.InvalidPage}
        return result
    }
}

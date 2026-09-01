#global public
#global namespace Svg

using Core, Core.Math

private const RasterSampleTileSide = 1024's32

// Controls resources that SVG parsing may resolve outside the document text.
//
// Data-image URIs are accepted up to `maxImageBytes`. A non-empty
// `externalResourceRoot` additionally permits relative raster-image references whose
// canonical path remains inside that directory; absolute paths and escaping `..`
// references are rejected.
//
// The three typeface names select what `font-family` resolves to. A document names
// faces the machine may not carry, so a family list is reduced to the class it asks
// for — serif, monospace, or anything else — exactly as the HTML view reduces it, and
// the class selects one of these files. Each may be a file path or a filename from the
// system font directory; a name that fails to load falls back to `fontFileName`.
struct ParseOptions
{
    public
    {
        externalResourceRoot: string = ""                   // Canonical containment root for relative image references; empty disables them.
        fontFileName:         string = "segoeui.ttf"        // Typeface used by text with no recognized or no serif/monospace family.
        serifFontFileName:    string = "georgia.ttf"        // Typeface used by a `serif` family; empty selects `fontFileName`.
        monoFontFileName:     string = "consola.ttf"        // Typeface used by a `monospace` family; empty selects `fontFileName`.
        maxImageBytes:        u64    = 16 * 1024 * 1024     // Maximum encoded bytes accepted for each embedded or external image.
    }
}

// One filled and/or stroked shape of a parsed [[Svg.Drawing]].
//
// The contours are stored in the drawing's user units, already transformed by the
// group transforms they were parsed under.
#[Swag.Opaque]
struct Shape
{
    internal
    {
        pathList: LinePathList     // Contours, in drawing user units.

        fillBrush:   Brush       // Resolved fill paint.
        fillColor:   Color       // Inherited solid fill before paint-server resolution.
        fillPaintId: String      // Referenced gradient identifier, if any.
        fillOpacity: f32 = 1     // Fill-only opacity multiplier.
        hasFill:     bool        // Whether the shape is filled.
        evenOdd:     bool        // Whether the fill uses the even-odd rule.

        hidden: bool     // Whether the shape is a reusable definition, not painted directly.

        strokeBrush:   Brush                    // Resolved stroke paint.
        strokeColor:   Color                    // Inherited solid stroke before paint-server resolution.
        strokePaintId: String                   // Referenced gradient identifier, if any.
        strokeOpacity: f32          = 1         // Stroke-only opacity multiplier.
        strokeWidth:   f32          = 1         // Stroke width, in user units.
        strokePattern: Array'f32                // Alternating dash and gap lengths, in user units.
        strokeOffset:  f32                      // Offset into the dash sequence, in user units.
        strokeMiter:   f32          = 3         // Maximum miter length relative to stroke width.
        hasStroke:     bool                     // Whether the shape is stroked.
        capStyle:      LineCapStyle = None      // Cap applied to open subpath ends.
        joinStyle:     JoinStyle    = Miter     // Join between stroke segments.

        paintTransform: Math.Transform2 = Math.Transform2.Identity     // Element transform retained for user-space paint servers.

        filterId: String     // Referenced filter definition, if any.
    }
}

// A parsed vector document, ready to paint at any scale.
//
// [[Pixel.Svg.Drawing.parse]] reads the SVG subset used by standalone artwork and the
// standard themes: basic shapes and paths, groups, definitions, uses, symbols and their
// viewports, clipping paths, start/mid/end markers, linear and centered radial gradients
// with their inheritance chains, repeating patterns, text runs with letter and word
// spacing, bounded raster images, a Gaussian blur followed by offsets or a standalone drop
// shadow, CSS Color 3 solid paints, opacity, path-length-calibrated stroke dashes, the
// complete affine `transform` list, and simple element/class/id style rules.
//
// Masks, radial focal points, arbitrary font fallback and the remaining SVG filter
// primitives are out of contract; a `font-family` list is reduced to serif, monospace or
// the default face rather than resolved against installed fonts. Because vector geometry
// is not rasterized at parse time, the same drawing renders sharply at any size.
struct Drawing
{
    public
    {
        width:  f32     // View-box width, in user units.
        height: f32     // View-box height, in user units.
    }

    shapes: Array'Shape     // Parsed vector shapes, including hidden definitions.

    public
    {
        texts:    Array'SvgText                     // Parsed text blocks referenced by the paint-order list.
        images:   Array'SvgImage                    // Decoded raster images referenced by the paint-order list.
        items:    Array'DrawingItem                 // Visible elements in paint order.
        patterns: HashTable'(String, Pattern)       // Resolved repeating paint servers by SVG identifier.
        filters:  HashTable'(String, SvgFilter)     // Resolved filter primitive chains by SVG identifier.
    }
}

private enum DrawingItemKind
{
    Shape
    Text
    Image
}

#[Swag.Opaque, Swag.NoDoc]
struct DrawingItem
{
    kind:  DrawingItemKind
    index: u64

    // Shapes the item is clipped by, as a range of the drawing's hidden shapes.
    //
    // A `clip-path` is instantiated once per element it applies to, under the transform of the
    // element that named it, so a group's clip stays where the group put it however its
    // children are transformed. An empty range is an unclipped item.
    clipFirst, clipCount: u64

    // Drawing-space rectangle outside which the item cannot lay ink, already reduced by the
    // clip it is drawn under.
    //
    // A painter whose clipping rectangle misses it skips the item whole, which is what keeps
    // a pan or a zoom proportional to what a window shows rather than to what the document
    // holds. The rectangle is never narrower than the ink and may be wider.
    bounds: Rectangle

    // Whether `bounds` has been established.
    //
    // A shape or a picture is measured once the document is parsed. Text is measured the
    // first time it is painted, because where a run lands depends on the shaping of the runs
    // before it, and shaping needs the painter's font cache.
    hasBounds: bool
}

private enum TextAnchor
{
    Start
    Middle
    End
}

// The families a host can be expected to carry, which a `font-family` list reduces to.
private enum FontFamilyKind
{
    Sans
    Serif
    Mono
}

private struct SvgTextRun
{
    text:          String
    typeFace:      *TypeFace = undefined
    x, y:          f32
    dx, dy:        f32
    fontSize:      f32
    letterSpacing: f32
    wordSpacing:   f32
    rotation:      f32     // Direction the baseline runs in, from the element transform.
    color:         Color
    opacity:       f32       = 1
    anchor:        TextAnchor
    forceBold:     bool
    forceItalic:   bool
    hasX, hasY:    bool
}

#[Swag.Opaque, Swag.NoDoc]
struct SvgText
{
    runs: Array'SvgTextRun
}

#[Swag.Opaque, Swag.NoDoc]
struct SvgImage
{
    image:   Image
    rect:    Rectangle
    opacity: f32 = 1
}

#[Swag.Opaque, Swag.NoDoc]
struct Pattern
{
    first, count:        u64
    x, y, width, height: SvgLength
    userSpace:           bool
}

private enum FilterPrimitiveKind
{
    GaussianBlur
    Offset
    DropShadow
}

private struct FilterPrimitive
{
    kind:   FilterPrimitiveKind
    x, y:   f32
    radius: f32
    color:  Color = Color.fromArgb(Argb.Black)
}

#[Swag.Opaque, Swag.NoDoc]
struct SvgFilter
{
    primitives: Array'FilterPrimitive
}

// Attribute state inherited through `svg` and `g` elements.
private struct GroupState
{
    // User space to drawing space, composed down the element tree.
    //
    // It is a full affine matrix rather than a translation and a scale, because that is what
    // `transform` states: a rotated label, a `matrix(...)` from a drawing tool, and a skewed
    // shadow are ordinary authored content, and reducing them to a scale places their geometry
    // somewhere it was never meant to be.
    transform: Math.Transform2 = Math.Transform2.Identity

    fillColor:   Color = Color.fromArgb(Argb.Black)     // Inherited fill color.
    fillPaintId: String                                 // Inherited fill paint server.
    fillOpacity: f32   = 1                              // Inherited fill-only opacity.
    hasFill:     bool  = true                           // Whether fill is enabled.
    evenOdd:     bool                                   // Inherited fill rule.

    strokeColor:   Color                    // Inherited stroke color.
    strokePaintId: String                   // Inherited stroke paint server.
    strokeOpacity: f32          = 1         // Inherited stroke-only opacity.
    strokeWidth:   f32          = 1         // Inherited stroke width, in user units.
    strokePattern: Array'SvgLength          // Inherited alternating dash and gap lengths.
    strokeOffset:  SvgLength                // Inherited offset into the dash sequence.
    strokeMiter:   f32          = 3         // Inherited miter limit.
    hasStroke:     bool                     // Whether stroke is enabled.
    capStyle:      LineCapStyle = None      // Inherited stroke cap.
    joinStyle:     JoinStyle    = Miter     // Inherited stroke join.

    markerStartId: String     // Inherited `marker-start` reference.
    markerMidId:   String     // Inherited `marker-mid` reference.
    markerEndId:   String     // Inherited `marker-end` reference.

    clipPathId:    String                                         // Inherited `clip-path` reference.
    clipTransform: Math.Transform2 = Math.Transform2.Identity     // Transform of the element that named the clip.

    currentColor: Color = Color.fromArgb(Argb.Black)     // Inherited `currentColor` value.

    isDisplayed: bool = true     // Whether an ancestor selected `display:none`.
    isVisible:   bool = true     // Inherited visibility state.

    opacity: f32 = 1     // Accumulated group opacity.
    inDefs:  bool        // Whether the element sits inside a `defs` scope.

    fontSize:      f32 = 16
    fontFamily:    FontFamilyKind
    letterSpacing: f32     // Extra space between glyphs, in the user units of this scope.
    wordSpacing:   f32     // Extra space added to each blank, in the user units of this scope.
    textAnchor:    TextAnchor
    forceBold:     bool
    forceItalic:   bool
    filterId:      String
}

private impl GroupState
{
    // Reports whether this element draws markers, so a path that draws none never pays for
    // collecting the vertices they would sit on.
    mtd const hasMarkers()->bool => !.markerStartId.isEmpty() or !.markerMidId.isEmpty() or !.markerEndId.isEmpty()
}

private struct Parser
{
    text:    string     // Whole document.
    pos:     u64        // Read position.
    drawing: *Drawing = undefined

    // Shapes defined inside `defs`, by id, instantiated by `use` elements. The
    // ranges index the drawing's shape array: defs shapes are parsed in place and
    // withheld from painting.
    defs:      HashTable'(String, { first: u64, count: u64 })
    clipPaths: HashTable'(String, { first: u64, count: u64 })
    symbols:   HashTable'(String, SymbolViewport)
    markers:   HashTable'(String, MarkerDefinition)
    gradients: HashTable'(String, Gradient)
    patterns:  HashTable'(String, Pattern)
    filters:   HashTable'(String, SvgFilter)
    styles:    Array'StyleRule
    options:   ParseOptions
    typeFaces: [FontFamilyKind.count] #null *TypeFace
    svgDepth:  u32
    inDefs:    bool     // Whether parsing currently sits inside a `defs` element.
}

private struct StyleRule
{
    selector:     String
    declarations: String
}

// A marker definition: the shapes it draws, the viewport they are drawn in, and how each
// placement is turned and sized.
private struct MarkerDefinition
{
    first, count: u64     // Shapes of the definition, in the drawing's hidden range.

    refX, refY:     f32             // Point of the marker placed on the vertex.
    width:          f32  = 3        // Marker viewport width.
    height:         f32  = 3        // Marker viewport height.
    scaleWithWidth: bool = true     // `markerUnits` is `strokeWidth` rather than user space.

    hasViewBox: bool
    viewX, viewY, viewWidth, viewHeight: f32

    orientAuto:         bool     // `orient="auto"` or `auto-start-reverse`.
    orientStartReverse: bool     // `orient="auto-start-reverse"`.
    angle:              f32      // Fixed rotation, in radians, when the orientation is not automatic.
}

// The viewport a `symbol` establishes for the elements that instantiate it.
private struct SymbolViewport
{
    hasViewBox: bool
    viewX, viewY, viewWidth, viewHeight: f32
}

private struct SvgLength
{
    value:     f32
    isPercent: bool
}

private enum GradientKind
{
    Linear
    Radial
}

// Which of a gradient's own attributes the document stated, so inheritance fills in only the
// rest. Without it a default is indistinguishable from an authored value and would overwrite the
// referenced gradient's.
private struct GradientSpecified
{
    x1, y1, x2, y2:        bool
    cx, cy, r, fx, fy, fr: bool
    units, spread:         bool
    transform, stops:      bool
}

private struct Gradient
{
    kind: GradientKind = Linear

    href:      String                // Gradient this one inherits from, without its `#`.
    specified: GradientSpecified     // Attributes this gradient states itself.

    x1: SvgLength = {0, true}
    y1: SvgLength = {0, true}
    x2: SvgLength = {1, true}
    y2: SvgLength = {0, true}

    cx: SvgLength = {0.5, true}
    cy: SvgLength = {0.5, true}
    r:  SvgLength = {0.5, true}
    fx: SvgLength = {0.5, true}
    fy: SvgLength = {0.5, true}
    fr: SvgLength

    userSpace: bool
    spread:    GradientSpread  = Clamp
    transform: Math.Transform2 = Math.Transform2.Identity
    stops:     Array'GradientStop
}

// Numeric scanning /////////////////////////////////////////////////////////////

private func isNumberStart(c: u8)->bool
{
    return (c >= '0' and c <= '9') or c == '-' or c == '+' or c == '.'
}

// Scans one floating-point number of a path or attribute value.
private func scanNumber(s: string, pos: *u64)->f32
{
    let len = s.count
    var i   = pos[]
    while i < len and (s[i] == ' ' or s[i] == ',' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r') do
        i += 1

    let start = i
    if i < len and (s[i] == '-' or s[i] == '+') do
        i += 1
    while i < len and s[i] >= '0' and s[i] <= '9' do
        i += 1
    if i < len and s[i] == '.'
    {
        i += 1
        while i < len and s[i] >= '0' and s[i] <= '9' do
            i += 1
    }

    // An exponent needs its digits: `0.5em` is a length in `em`, not a number cut short at
    // `0.5e`, and reading it as one loses the value entirely.
    if i < len and (s[i] == 'e' or s[i] == 'E')
    {
        var look = i + 1
        if look < len and (s[look] == '-' or s[look] == '+') do
            look += 1
        if look < len and s[look] >= '0' and s[look] <= '9'
        {
            i = look
            while i < len and s[i] >= '0' and s[i] <= '9' do
                i += 1
        }
    }

    pos[] = i
    if i == start do
        return 0
    return catch StrConv.toF32(cast(string) Swag.makeSlice(s.buffer + start, i - start))
}

private func parseLength(value: string, defaultValue: SvgLength = {})->SvgLength
{
    var pos = 0'u64
    while pos < value.count and (value[pos] == ' ' or value[pos] == '\t' or value[pos] == '\n' or value[pos] == '\r') do
        pos += 1
    if pos >= value.count or !isNumberStart(value[pos]) do
        return defaultValue

    var result: retval
    result.value = scanNumber(value, &pos)
    while pos < value.count and value[pos] == ' ' do
        pos += 1
    if pos < value.count and value[pos] == '%'
    {
        result.value     *= 0.01
        result.isPercent = true
    }

    return result
}

private func parsePaintId(value: string)->String
{
    var result: retval
    let trimmed = Latin1.trim(value)
    if trimmed.count < 7 or Latin1.compare(cast(string) Swag.makeSlice(trimmed.buffer, 5), "url(#", ignoreCase: true) do
        return result

    var end = 5'u64
    while end < trimmed.count and trimmed[end] != ')' do
        end += 1
    if end > 5 do
        result = cast(string) Swag.makeSlice(trimmed.buffer + 5, end - 5)
    return result
}

// Reduces a `font-family` list to the class a host can honour.
//
// A list is a preference order over faces the machine may or may not carry, so the
// first recognized name decides and an unrecognized one is skipped. The table is the
// one [[Gui.HtmlView]] reads, for the same reason: a themed application answers with a
// class, not with a face.
private func parseFontFamily(value: string)->{ kind: FontFamilyKind, matched: bool }
{
    var result: retval

    var scan = value
    while scan.count
    {
        var stop = 0'u64
        while stop < scan.count and scan[stop] != ',' do
            stop += 1

        var name = Latin1.trim(cast(string) Swag.makeSlice(scan.buffer, stop))
        if name.count >= 2 and (name[0] == '"' or name[0] == '\'') do
            name = Latin1.trim(cast(string) Swag.makeSlice(name.buffer + 1, name.count - 2))

        var lowered = String.from(name)
        lowered = lowered.toLower()
        switch lowered.toString()
        {
        case "monospace", "ui-monospace", "consolas", "menlo", "courier", "courier new",
             "cascadia mono", "cascadia code", "sfmono-regular", "dejavu sans mono", "liberation mono":
            result.kind    = .Mono
            result.matched = true
            return result

        case "serif", "ui-serif", "georgia", "times", "times new roman", "cambria", "garamond":
            result.kind    = .Serif
            result.matched = true
            return result

        case "sans-serif", "ui-sans-serif", "system-ui", "-apple-system", "segoe ui", "roboto",
             "arial", "helvetica", "helvetica neue", "inter", "noto sans":
            result.kind    = .Sans
            result.matched = true
            return result
        }

        if stop == scan.count do
            break
        scan = cast(string) Swag.makeSlice(scan.buffer + stop + 1, scan.count - stop - 1)
    }

    return result
}

// Parses a `letter-spacing` or `word-spacing` value into user units.
//
// `normal` states the absence of extra spacing. A percentage and the `em` unit both
// resolve against the current font size, the only relative reference these properties
// have; every other unit is read as a plain user-unit length.
private func spacingLength(value: string, fontSize: f32)->f32
{
    let text = Latin1.trim(value)
    if !Latin1.compare(text, "normal", ignoreCase: true) do
        return 0

    var pos = 0'u64
    if text.count == 0 or !isNumberStart(text[0]) do
        return 0

    let amount = scanNumber(text, &pos)
    while pos < text.count and text[pos] == ' ' do
        pos += 1
    if pos >= text.count do
        return amount

    let unit = cast(string) Swag.makeSlice(text.buffer + pos, text.count - pos)
    if unit[0] == '%' do
        return amount * 0.01 * fontSize
    if !Latin1.compare(unit, "em", ignoreCase: true) or !Latin1.compare(unit, "rem", ignoreCase: true) do
        return amount * fontSize
    return amount
}

private func normalizedText(value: string)->String
{
    var result: retval
    var pendingSpace = false
    for c in value
    {
        if c == ' ' or c == '\t' or c == '\r' or c == '\n'
        {
            pendingSpace = !result.isEmpty()
            continue
        }

        if pendingSpace do
            result += ' '
        pendingSpace = false
        result       += c
    }

    return result
}

// Colors ///////////////////////////////////////////////////////////////////////

private func hexNibble(c: u8)->u8
{
    if c >= '0' and c <= '9' do
        return c - '0'
    if c >= 'a' and c <= 'f' do
        return c - 'a' + 10
    if c >= 'A' and c <= 'F' do
        return c - 'A' + 10
    return 0
}

private func scanCssComponent(value: string, pos: *u64, scale: f32)->f32
{
    var result = scanNumber(value, pos)
    if pos[] < value.count and value[pos[]] == '%'
    {
        result *= 0.01 * scale
        pos[]  += 1
    }

    return Math.clamp(result, 0, scale)
}

// Parses a solid paint value. Returns the color and whether painting is enabled.
private func parseColor(value: string)->{ color: Color, enabled: bool }
{
    var result: retval
    result.color   = Color.fromArgb(Argb.Black)
    result.enabled = true

    let text = Latin1.trim(value)

    if !Latin1.compare(text, "none", ignoreCase: true)
    {
        result.enabled = false
        return result
    }

    if !Latin1.compare(text, "transparent", ignoreCase: true)
    {
        result.color = Color.fromArgb(Argb.Zero)
        return result
    }

    let len = text.count
    if len and text[0] == '#'
    {
        if len == 4 or len == 5
        {
            let r = hexNibble(text[1]) * 17
            let g = hexNibble(text[2]) * 17
            let b = hexNibble(text[3]) * 17
            let a = len == 5 ? hexNibble(text[4]) * 17 : 255'u8
            result.color = Color.fromArgb(a, r, g, b)
            return result
        }

        if len == 7 or len == 9
        {
            let r = hexNibble(text[1]) * 16 + hexNibble(text[2])
            let g = hexNibble(text[3]) * 16 + hexNibble(text[4])
            let b = hexNibble(text[5]) * 16 + hexNibble(text[6])
            let a = len == 9 ? hexNibble(text[7]) * 16 + hexNibble(text[8]) : 255'u8
            result.color = Color.fromArgb(a, r, g, b)
            return result
        }
    }

    let isRgb  = len > 4 and !Latin1.compare(cast(string) Swag.makeSlice(text.buffer, 4), "rgb(", ignoreCase: true)
    let isRgba = len > 5 and !Latin1.compare(cast(string) Swag.makeSlice(text.buffer, 5), "rgba(", ignoreCase: true)
    if isRgb or isRgba
    {
        var pos = isRgba ? 5'u64 : 4'u64
        let r   = scanCssComponent(text, &pos, 255)
        let g   = scanCssComponent(text, &pos, 255)
        let b   = scanCssComponent(text, &pos, 255)
        let a   = isRgba ? scanCssComponent(text, &pos, 1) : 1.0
        result.color = Color.fromArgb(cast(u8) Math.round(a * 255), cast(u8) Math.round(r), cast(u8) Math.round(g), cast(u8) Math.round(b))
        return result
    }

    let isHsl  = len > 4 and !Latin1.compare(cast(string) Swag.makeSlice(text.buffer, 4), "hsl(", ignoreCase: true)
    let isHsla = len > 5 and !Latin1.compare(cast(string) Swag.makeSlice(text.buffer, 5), "hsla(", ignoreCase: true)
    if isHsl or isHsla
    {
        var pos = isHsla ? 5'u64 : 4'u64
        var hue = scanNumber(text, &pos)
        hue -= Math.floor(hue / 360) * 360
        let saturation = scanCssComponent(text, &pos, 1)
        let lightness  = scanCssComponent(text, &pos, 1)
        let alpha      = isHsla ? scanCssComponent(text, &pos, 1) : 1.0
        result.color   = Color.fromHsl(hue / 360, saturation, lightness)
        result.color.a = cast(u8) Math.round(alpha * 255)
        return result
    }

    // SVG uses the CSS named-color table. The enum preserves its canonical
    // UpperCamelCase spellings, while authored values are compared case-insensitively.
    let type = #typeof(Argb)
    for it in type.values
    {
        if it.name and !Latin1.compare(it.name!, text, ignoreCase: true)
        {
            result.color = Color.fromArgb(it.value![as Argb])
            return result
        }
    }

    return result
}

private func parseDashPattern(value: string)->Array'SvgLength
{
    var result: retval
    var total:  f32
    let text = Latin1.trim(value)
    if !Latin1.compare(text, "none", ignoreCase: true) do
        return result

    var pos = 0'u64
    while pos < text.count
    {
        while pos < text.count and (text[pos] == ' ' or text[pos] == ',' or text[pos] == '\t' or text[pos] == '\n' or text[pos] == '\r') do
            pos += 1
        if pos >= text.count or !isNumberStart(text[pos]) do
            break

        var length = SvgLength{value: scanNumber(text, &pos)}
        if pos < text.count and text[pos] == '%'
        {
            length.value     *= 0.01
            length.isPercent = true
            pos              += 1
        }

        if length.value < 0 do
            return {}
        result.add(length)
        total += length.value
    }

    if total == 0 do
        return {}

    if result.count & 1
    {
        let count = result.count
        for i in count do
            result.add(result[i])
    }

    return result
}

// Group attributes /////////////////////////////////////////////////////////////

private func applyStyleProperty(state: *GroupState, name, value: string)
{
    switch name
    {
    case "fill":
        let paintId = parsePaintId(value)
        if !paintId.isEmpty()
        {
            state.fillPaintId = #move paintId
            state.hasFill     = true
        }
        else
        {
            state.fillPaintId.clear()
            if !Latin1.compare(Latin1.trim(value), "currentColor", ignoreCase: true)
            {
                state.fillColor = state.currentColor
                state.hasFill   = true
            }
            else
            {
                let {color, enabled} = parseColor(value)
                state.hasFill = enabled
                if enabled do
                    state.fillColor = color
            }
        }

    case "stroke":
        let paintId = parsePaintId(value)
        if !paintId.isEmpty()
        {
            state.strokePaintId = #move paintId
            state.hasStroke     = true
        }
        else
        {
            state.strokePaintId.clear()
            if !Latin1.compare(Latin1.trim(value), "currentColor", ignoreCase: true)
            {
                state.strokeColor = state.currentColor
                state.hasStroke   = true
            }
            else
            {
                let {color, enabled} = parseColor(value)
                state.hasStroke = enabled
                if enabled do
                    state.strokeColor = color
            }
        }

    case "color":
        state.currentColor = parseColor(value).color

    case "display":
        if !Latin1.compare(Latin1.trim(value), "none", ignoreCase: true) do
            state.isDisplayed = false

    case "visibility":
        let visible = Latin1.compare(Latin1.trim(value), "hidden", ignoreCase: true) != 0 and Latin1.compare(Latin1.trim(value), "collapse", ignoreCase: true) != 0
        state.isVisible = visible

    case "fill-opacity":
        state.fillOpacity = Math.saturate(parseLength(value).value)

    case "stroke-opacity":
        state.strokeOpacity = Math.saturate(parseLength(value).value)

    case "opacity":
        state.opacity *= Math.saturate(parseLength(value).value)

    case "filter":
        state.filterId = parsePaintId(value)

    case "clip-path":
        state.clipPathId = parsePaintId(value)

    // The shorthand sets all three positions, and a specific property overrides it.
    case "marker":
        let all = parsePaintId(value)
        state.markerStartId = all
        state.markerMidId   = all
        state.markerEndId   = all

    case "marker-start":
        state.markerStartId = parsePaintId(value)

    case "marker-mid":
        state.markerMidId = parsePaintId(value)

    case "marker-end":
        state.markerEndId = parsePaintId(value)

    case "font-family":
        let family = parseFontFamily(value)
        if family.matched do
            state.fontFamily = family.kind

    case "font-size":
        state.fontSize = Math.max(parseLength(value, {state.fontSize, false}).value, 1)

    // `normal` is the absence of extra spacing, and a percentage is relative to the
    // font size, which is what `em` already resolves against here.
    case "letter-spacing":
        state.letterSpacing = spacingLength(value, state.fontSize)

    case "word-spacing":
        state.wordSpacing = spacingLength(value, state.fontSize)

    case "font-weight":
        let weight = Latin1.trim(value)
        var pos    = 0'u64
        let number = scanNumber(weight, &pos)
        state.forceBold = !Latin1.compare(weight, "bold", ignoreCase: true) or number >= 600

    case "font-style":
        let style = Latin1.trim(value)
        state.forceItalic = !Latin1.compare(style, "italic", ignoreCase: true) or !Latin1.compare(style, "oblique", ignoreCase: true)

    case "text-anchor":
        switch Latin1.trim(value)
        {
        case "middle": state.textAnchor = .Middle
        case "end":    state.textAnchor = .End
        default:       state.textAnchor = .Start
        }

    case "stroke-width":
        var pos = 0'u64
        state.strokeWidth = scanNumber(value, &pos)

    case "stroke-dasharray":
        state.strokePattern = parseDashPattern(value)

    case "stroke-dashoffset":
        state.strokeOffset = parseLength(value)

    case "stroke-miterlimit":
        var pos = 0'u64
        state.strokeMiter = Math.max(scanNumber(value, &pos), 1)

    case "fill-rule":
        state.evenOdd = value == "evenodd"

    case "stroke-linecap":
        switch value
        {
        case "round":  state.capStyle = .Round
        case "square": state.capStyle = .Square
        default:       state.capStyle = .None
        }

    case "stroke-linejoin":
        switch value
        {
        case "round": state.joinStyle = .Round
        case "bevel": state.joinStyle = .Bevel
        default:      state.joinStyle = .Miter
        }

    case "transform":
        state.transform = composeTransformList(value, state.transform)
    }
}

// Composes a `transform` list onto the transform it is written under.
//
// The list is read left to right and each function applies to what the ones after it produce,
// which is what makes `translate(60,120) scale(0.6)` place a scaled drawing at that corner
// rather than scale a translation.
private func composeTransformList(value: string, parent: Math.Transform2)->Math.Transform2
{
    var result = parent

    var pos = 0'u64
    let len = value.count
    while pos < len
    {
        while pos < len and (value[pos] == ' ' or value[pos] == ',' or value[pos] == '\t' or value[pos] == '\n' or value[pos] == '\r') do
            pos += 1

        let nameStart = pos
        while pos < len and ((value[pos] >= 'a' and value[pos] <= 'z') or (value[pos] >= 'A' and value[pos] <= 'Z')) do
            pos += 1
        let name = cast(string) Swag.makeSlice(value.buffer + nameStart, pos - nameStart)
        if name.count == 0 do
            break

        while pos < len and value[pos] != '(' do
            pos += 1
        if pos >= len do
            break
        pos += 1

        // Every function takes a bounded list of numbers; read what is there and let the
        // defaults of the shorter forms stand.
        var arguments: [6] f32
        var count = 0'u64
        while count < 6
        {
            var look = pos
            while look < len and (value[look] == ' ' or value[look] == ',' or value[look] == '\t' or value[look] == '\n' or value[look] == '\r') do
                look += 1
            if look >= len or !isNumberStart(value[look]) do
                break
            arguments[count] = scanNumber(value, &pos)
            count            += 1
        }

        while pos < len and value[pos] != ')' do
            pos += 1
        pos += 1

        var step = Math.Transform2.Identity
        switch name
        {
        case "translate":
            step = Math.Transform2.createTranslation(arguments[0], count > 1 ? arguments[1] : 0)

        case "scale":
            step = Math.Transform2.createScale(arguments[0], count > 1 ? arguments[1] : arguments[0], 0, 0)

        case "rotate":
            let angle = Math.toRadians(arguments[0])
            step = count > 2 ? Math.Transform2.createRotation(angle, arguments[1], arguments[2]) : Math.Transform2.createRotation(angle, 0, 0)

        case "skewX":
            step.m21 = Math.tan(Math.toRadians(arguments[0]))

        case "skewY":
            step.m12 = Math.tan(Math.toRadians(arguments[0]))

        case "matrix":
            step = Math.Transform2{arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5]}

        default:

            // An unknown function leaves the transform alone rather than dropping the rest of
            // the list, so one unsupported spelling cannot displace the whole subtree.
            continue
        }

        step.multiply(result)
        result = step
    }

    return result
}

private func applyAttribute(state: *GroupState, name, value: string)
{
    if name == "style"
    {
        // Inline declarations: name:value pairs separated by ';'.
        var scan = value
        while scan.count
        {
            var stop = 0'u64
            while stop < scan.count and scan[stop] != ';' do
                stop += 1
            let decl = Swag.makeSlice(scan.buffer, stop)

            var sep = 0'u64
            while sep < decl.count and decl[sep] != ':' do
                sep += 1
            if sep < decl.count
            {
                var n = cast(string) Swag.makeSlice(decl.buffer, sep)
                var v = cast(string) Swag.makeSlice(decl.buffer + sep + 1, decl.count - sep - 1)
                n = Latin1.trim(n)
                v = Latin1.trim(v)
                applyStyleProperty(state, n, v)
            }

            if stop == scan.count do
                break
            scan = cast(string) Swag.makeSlice(scan.buffer + stop + 1, scan.count - stop - 1)
        }

        return
    }

    applyStyleProperty(state, name, value)
}

private func styleValue(style, property: string)->String
{
    var result: retval
    var scan = style
    while scan.count
    {
        var stop = 0'u64
        while stop < scan.count and scan[stop] != ';' do
            stop += 1
        let declaration = Swag.makeSlice(scan.buffer, stop)

        var sep = 0'u64
        while sep < declaration.count and declaration[sep] != ':' do
            sep += 1
        if sep < declaration.count
        {
            let name = Latin1.trim(cast(string) Swag.makeSlice(declaration.buffer, sep))
            if !Latin1.compare(name, property, ignoreCase: true)
            {
                result = Latin1.trim(cast(string) Swag.makeSlice(declaration.buffer + sep + 1, declaration.count - sep - 1))
                return result
            }
        }

        if stop == scan.count do
            break
        scan = cast(string) Swag.makeSlice(scan.buffer + stop + 1, scan.count - stop - 1)
    }

    return result
}

// Geometry /////////////////////////////////////////////////////////////////////

// Returns `transform` with a translation applied before it, which is what a viewport origin
// and a `use` offset both state: a shift of the space the children are written in.
private func prependTranslation(transform: Math.Transform2, x, y: f32)->Math.Transform2
{
    var result = Math.Transform2.createTranslation(x, y)
    result.multiply(transform)
    return result
}

// Maps one user-space point into drawing space.
#[Swag.Inline]
private func mapPoint(state: *GroupState, x, y: f32)->Vector2 => state.transform.transformPoint({x, y})

// Maps one user-space direction into drawing space, without the translation.
#[Swag.Inline]
private func mapVector(transform: Math.Transform2, x, y: f32)->Vector2
    =>
{x * transform.m11 + y * transform.m21, x * transform.m12 + y * transform.m22}

// Length of the transformed unit vector of each axis.
#[Swag.Inline]
private func transformScaleX(transform: Math.Transform2)->f32 => Math.sqrt(transform.m11 * transform.m11 + transform.m12 * transform.m12)

#[Swag.Inline]
private func transformScaleY(transform: Math.Transform2)->f32 => Math.sqrt(transform.m21 * transform.m21 + transform.m22 * transform.m22)

// The single length scale a transform applies, as the square root of the area it multiplies.
//
// A stroke width, a dash length and a dash offset are one number in user units, and an
// anisotropic transform has no exact answer for them; this is the value SVG's own
// `stroke-width` resolves to under such a transform, and it reduces to the plain factor
// whenever the transform is uniform.
private func transformScale(transform: Math.Transform2)->f32
    => Math.sqrt(Math.abs(transform.m11 * transform.m22 - transform.m12 * transform.m21))

// Reports whether a transform keeps the axes, so a shape can be built from its raw
// axis-aligned primitive instead of from curves.
#[Swag.Inline]
private func isAxisAligned(transform: Math.Transform2)->bool
    => Math.isZeroEpsilon(transform.m12) and Math.isZeroEpsilon(transform.m21)

// The angle a transform turns the horizontal axis by, which is the direction text runs in.
#[Swag.Inline]
private func transformRotation(transform: Math.Transform2)->f32 => Math.atan2(transform.m12, transform.m11)

// Circular-arc control-point distance for a quarter turn, as a fraction of the radius.
private const ArcKappa = 0.5522847498'f32

// Appends a rectangle contour, rounded corners included, transformed into drawing space.
//
// A transform that turns or shears the axes has no axis-aligned rectangle to state, so the
// contour is written out corner by corner and every point goes through the transform.
private func appendRectContour(path: *LinePath, state: *GroupState, x, y, w, h, rx, ry: f32)
{
    let right  = x + w
    let bottom = y + h
    if rx <= 0 or ry <= 0
    {
        var corner = mapPoint(state, x, y)
        path.start(corner.x, corner.y)
        corner = mapPoint(state, right, y)
        path.lineTo(corner.x, corner.y)
        corner = mapPoint(state, right, bottom)
        path.lineTo(corner.x, corner.y)
        corner = mapPoint(state, x, bottom)
        path.lineTo(corner.x, corner.y)
        path.close()
        return
    }

    let kx = rx * ArcKappa
    let ky = ry * ArcKappa

    var point = mapPoint(state, x + rx, y)
    path.start(point.x, point.y)

    point = mapPoint(state, right - rx, y)
    path.lineTo(point.x, point.y)
    appendEllipseQuarter(path, state, right - rx + kx, y, right, y + ry - ky, right, y + ry)

    point = mapPoint(state, right, bottom - ry)
    path.lineTo(point.x, point.y)
    appendEllipseQuarter(path, state, right, bottom - ry + ky, right - rx + kx, bottom, right - rx, bottom)

    point = mapPoint(state, x + rx, bottom)
    path.lineTo(point.x, point.y)
    appendEllipseQuarter(path, state, x + rx - kx, bottom, x, bottom - ry + ky, x, bottom - ry)

    point = mapPoint(state, x, y + ry)
    path.lineTo(point.x, point.y)
    appendEllipseQuarter(path, state, x, y + ry - ky, x + rx - kx, y, x + rx, y)
    path.close()
}

// Appends one arc element of a definition, transformed into drawing space.
//
// An arc states an axis-aligned ellipse, which a transform that turns or shears the axes cannot
// carry; there the arc is written out as the curves it stands for, sampled the same way an
// authored arc is.
private func appendArcElement(path: *LinePath, state: *GroupState, center, angles, radii: Vector2)
{
    let cx = center.x
    let cy = center.y
    if isAxisAligned(state.transform)
    {
        let mapped = mapPoint(state, cx, cy)
        path.arcTo(mapped.x, mapped.y, radii.x * transformScaleX(state.transform), radii.y * transformScaleY(state.transform), Math.Angle.fromRadians(angles.x), Math.Angle.fromRadians(angles.y))
        return
    }

    // The stored parameterization runs clockwise from the top of the ellipse.
    let sweepAngle = angles.y - angles.x
    let segCount   = cast(s32) Math.max(Math.ceil(Math.abs(sweepAngle) / (Math.ConstF32.Pi * 0.5)), 1.0)
    let segAngle   = sweepAngle / cast(f32) segCount
    let k          = 4.0 / 3.0 * Math.tan(segAngle * 0.25)

    var angle = angles.x
    for i in segCount
    {
        let a0 = angle
        let a1 = angle + segAngle

        let p0x = cx + Math.sin(a0) * radii.x
        let p0y = cy - Math.cos(a0) * radii.y
        let p1x = cx + Math.sin(a1) * radii.x
        let p1y = cy - Math.cos(a1) * radii.y

        let control0 = mapPoint(state, p0x + k * Math.cos(a0) * radii.x, p0y + k * Math.sin(a0) * radii.y)
        let control1 = mapPoint(state, p1x - k * Math.cos(a1) * radii.x, p1y - k * Math.sin(a1) * radii.y)
        let end      = mapPoint(state, p1x, p1y)
        path.bezierTo(end.x, end.y, control0.x, control0.y, control1.x, control1.y)
        angle = a1
    }
}

// Appends the four cubic segments of an ellipse, transformed into drawing space.
//
// A transform that turns or shears the axes has no axis-aligned ellipse to state, so the
// contour is written as curves whose control points go through the transform like any other
// point. The raw primitive stays the path for an axis-preserving transform, where it is both
// cheaper and exact.
private func appendEllipse(path: *LinePath, state: *GroupState, cx, cy, rx, ry: f32)
{
    if isAxisAligned(state.transform)
    {
        let center = mapPoint(state, cx, cy)
        path.setEllipseRaw(center.x, center.y, rx * transformScaleX(state.transform), ry * transformScaleY(state.transform))
        return
    }

    let kx = rx * ArcKappa
    let ky = ry * ArcKappa

    var start = mapPoint(state, cx + rx, cy)
    path.start(start.x, start.y)
    appendEllipseQuarter(path, state, cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
    appendEllipseQuarter(path, state, cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
    appendEllipseQuarter(path, state, cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
    appendEllipseQuarter(path, state, cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
    path.close()
}

private func appendEllipseQuarter(path: *LinePath, state: *GroupState, c0x, c0y, c1x, c1y, ex, ey: f32)
{
    let control0 = mapPoint(state, c0x, c0y)
    let control1 = mapPoint(state, c1x, c1y)
    let end      = mapPoint(state, ex, ey)
    path.bezierTo(end.x, end.y, control0.x, control0.y, control1.x, control1.y)
}

// Places one point of an arc's own frame into drawing space.
private func placeArcPoint(state: *GroupState, cx, cy, cosPhi, sinPhi, lx, ly: f32)->Vector2
    => mapPoint(state, cx + lx * cosPhi - ly * sinPhi, cy + lx * sinPhi + ly * cosPhi)

// Appends one endpoint-parameterized elliptical arc as cubic Beziers, in drawing space.
//
// The arc is solved in the user space it was authored in, x-axis rotation included, and every
// point it produces goes through `state`. That is what keeps an arc under a turned or sheared
// transform an arc of the ellipse the document named, instead of an axis-aligned stand-in.
private func appendArc(path: *LinePath, state: *GroupState, x0, y0: f32, rxIn, ryIn, xAxisRotation: f32, largeArc, sweep: bool, x1, y1: f32)
{
    var rx = Math.abs(rxIn)
    var ry = Math.abs(ryIn)
    if rx <= 0.000001 or ry <= 0.000001 or (x0 == x1 and y0 == y1)
    {
        let end = mapPoint(state, x1, y1)
        path.lineTo(end.x, end.y)
        return
    }

    let phi    = Math.toRadians(xAxisRotation)
    let cosPhi = Math.cos(phi)
    let sinPhi = Math.sin(phi)

    // Endpoint to center parameterization (SVG specification appendix), in the frame the
    // ellipse's own axes define.
    let dx = (x0 - x1) * 0.5
    let dy = (y0 - y1) * 0.5
    let px = cosPhi * dx + sinPhi * dy
    let py = -sinPhi * dx + cosPhi * dy

    var lambda = (px * px) / (rx * rx) + (py * py) / (ry * ry)
    if lambda > 1
    {
        lambda = Math.sqrt(lambda)
        rx     *= lambda
        ry     *= lambda
    }

    let rx2 = rx * rx
    let ry2 = ry * ry
    var num = rx2 * ry2 - rx2 * py * py - ry2 * px * px
    if num < 0 do
        num = 0
    let den  = rx2 * py * py + ry2 * px * px
    var coef = Math.sqrt(num / Math.max(den, 0.000001))
    if largeArc == sweep do
        coef = -coef

    let cxp = coef * rx * py / ry
    let cyp = -coef * ry * px / rx
    let cx  = cosPhi * cxp - sinPhi * cyp + (x0 + x1) * 0.5
    let cy  = sinPhi * cxp + cosPhi * cyp + (y0 + y1) * 0.5

    let startAngle = Math.atan2((py - cyp) / ry, (px - cxp) / rx)
    let endAngle   = Math.atan2((-py - cyp) / ry, (-px - cxp) / rx)

    var sweepAngle = endAngle - startAngle
    if sweep and sweepAngle < 0 do
        sweepAngle += 2 * Math.ConstF32.Pi
    elif !sweep and sweepAngle > 0 do
        sweepAngle -= 2 * Math.ConstF32.Pi

    // Split into segments no larger than a quarter turn and emit each as a cubic.
    let segCount = cast(s32) Math.max(Math.ceil(Math.abs(sweepAngle) / (Math.ConstF32.Pi * 0.5)), 1.0)
    let segAngle = sweepAngle / cast(f32) segCount
    let k        = 4.0 / 3.0 * Math.tan(segAngle * 0.25)

    var angle = startAngle
    for i in segCount
    {
        let a0  = angle
        let a1  = angle + segAngle
        let p1x = rx * Math.cos(a1)
        let p1y = ry * Math.sin(a1)
        let c0x = rx * Math.cos(a0) - k * rx * Math.sin(a0)
        let c0y = ry * Math.sin(a0) + k * ry * Math.cos(a0)
        let c1x = p1x + k * rx * Math.sin(a1)
        let c1y = p1y - k * ry * Math.cos(a1)

        let end      = placeArcPoint(state, cx, cy, cosPhi, sinPhi, p1x, p1y)
        let control0 = placeArcPoint(state, cx, cy, cosPhi, sinPhi, c0x, c0y)
        let control1 = placeArcPoint(state, cx, cy, cosPhi, sinPhi, c1x, c1y)
        path.bezierTo(end.x, end.y, control0.x, control0.y, control1.x, control1.y)
        angle = a1
    }
}

// One place a marker can be drawn: a vertex of an authored contour, in user units.
//
// The two directions are the ones the outline arrives and leaves along. A vertex that ends a
// contour has no outgoing direction and one that begins it has no incoming one, which is what
// makes a start marker point forward and an end marker point back along the last segment.
private struct MarkerVertex
{
    point:         Vector2
    inDir, outDir: Vector2
}

// Returns the marker vertices of a `points` list, or nothing when the element carries none.
private func polyVertices(points: string, wanted: bool)->Array'MarkerVertex
{
    var result: retval
    if !wanted do
        return result

    var pos = 0'u64
    while pos < points.count
    {
        var look = pos
        while look < points.count and (points[look] == ' ' or points[look] == ',') do
            look += 1
        if look >= points.count or !isNumberStart(points[look]) do
            break

        let x = scanNumber(points, &pos)
        let y = scanNumber(points, &pos)
        if result.count
        {
            let previous  = result[result.count - 1].point
            let direction = Vector2{x - previous.x, y - previous.y}
            result[result.count - 1].outDir = direction
            result.add(MarkerVertex{{x, y}, direction, {}})
        }
        else do
            result.add(MarkerVertex{{x, y}, {}, {}})
    }

    return result
}

// Records the vertex a segment just reached, and the direction it left the previous one along.
private func addMarkerVertex(vertices: #null *Array'MarkerVertex, point, inDir, previousOutDir: Vector2)
{
    if !vertices do
        return
    if vertices.count and (previousOutDir.x != 0 or previousOutDir.y != 0) do
        vertices[vertices.count - 1].outDir = previousOutDir
    vertices.add(MarkerVertex{point, inDir, {}})
}

// Parses one `d` attribute into subpath contours, transformed by `state`.
//
// `vertices` collects the authored vertices markers are placed on; pass null when the element
// carries none, which is the common case and skips the bookkeeping entirely.
private func parsePathData(list: *LinePathList, data: string, state: *GroupState, vertices: #null *Array'MarkerVertex = null)
{
    let len = data.count
    var pos = 0'u64

    var cmd:        u8
    var curX, curY: f32     // Current point, user units.
    var begX, begY: f32     // Subpath start, user units.
    var ctlX, ctlY: f32     // Last cubic/quadratic control point, for S/T reflection.
    var lastCurve:  u8      // 'c' when the previous command was cubic-ish, 'q' for quadratic.

    var path:    #null *LinePath
    var started: bool

    func number(data: string, pos: *u64, valid: *bool)->f32
    {
        if !valid[] do
            return 0

        var look = pos[]
        while look < data.count and (data[look] == ' ' or data[look] == ',' or data[look] == '\t' or data[look] == '\n' or data[look] == '\r') do
            look += 1
        if look >= data.count or !isNumberStart(data[look])
        {
            valid[] = false
            return 0
        }

        return scanNumber(data, pos)
    }

    func flag(data: string, pos: *u64, valid: *bool)->bool
    {
        if !valid[] do
            return false

        while pos[] < data.count and (data[pos[]] == ' ' or data[pos[]] == ',' or data[pos[]] == '\t' or data[pos[]] == '\n' or data[pos[]] == '\r') do
            pos[] += 1
        if pos[] >= data.count or (data[pos[]] != '0' and data[pos[]] != '1')
        {
            valid[] = false
            return false
        }

        let f = data[pos[]] == '1'
        pos[] += 1
        return f
    }

    while pos < len
    {
        let c = data[pos]
        if c == ' ' or c == ',' or c == '\t' or c == '\n' or c == '\r'
        {
            pos += 1
            continue
        }

        if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')
        {
            switch c
            {
            case 'M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c', 'S', 's', 'Q', 'q', 'T', 't', 'A', 'a', 'Z', 'z': discard c
            default: return
            }

            cmd = c
            pos += 1
            if cmd == 'Z' or cmd == 'z'
            {
                if !path do
                    return
                if started do
                    path.close()
                curX      = begX
                curY      = begY
                started   = false
                lastCurve = 0
                continue
            }
        }
        elif !isNumberStart(c) do
            return

        if !path and cmd != 'M' and cmd != 'm' do
            return

        let rel   = cmd >= 'a'
        var valid = true
        switch cmd
        {
        case 'M', 'm':
            var x = number(data, &pos, &valid)
            var y = number(data, &pos, &valid)
            if !valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            let start = mapPoint(state, x, y)
            path = list.newPath()
            path.start(start.x, start.y)
            addMarkerVertex(vertices, {x, y}, {}, {})
            started = true
            curX    = x
            curY    = y
            begX    = x
            begY    = y

            // Following coordinate pairs are implicit line-to commands.
            cmd = rel ? cast(u8) 'l' : cast(u8) 'L'

        case 'L', 'l':
            var x = number(data, &pos, &valid)
            var y = number(data, &pos, &valid)
            if !valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            // A zero-length segment adds a duplicate point, which degenerates the
            // fill tessellation; authored paths hit this when a radius equals half
            // the shape size.
            if Math.abs(x - curX) > 0.0005 or Math.abs(y - curY) > 0.0005
            {
                let target = mapPoint(state, x, y)
                path!.lineTo(target.x, target.y)
                addMarkerVertex(vertices, {x, y}, {x - curX, y - curY}, {x - curX, y - curY})
            }

            curX = x
            curY = y

        case 'H', 'h':
            var x = number(data, &pos, &valid)
            if !valid do
                return
            if rel do
                x += curX
            let target = mapPoint(state, x, curY)
            path!.lineTo(target.x, target.y)
            addMarkerVertex(vertices, {x, curY}, {x - curX, 0}, {x - curX, 0})
            curX = x

        case 'V', 'v':
            var y = number(data, &pos, &valid)
            if !valid do
                return
            if rel do
                y += curY
            let target = mapPoint(state, curX, y)
            path!.lineTo(target.x, target.y)
            addMarkerVertex(vertices, {curX, y}, {0, y - curY}, {0, y - curY})
            curY = y

        case 'C', 'c', 'S', 's':
            var c1x, c1y: f32
            if cmd == 'C' or cmd == 'c'
            {
                c1x = number(data, &pos, &valid)
                c1y = number(data, &pos, &valid)
                if rel
                {
                    c1x += curX
                    c1y += curY
                }
            }
            else
            {
                // Reflect the previous cubic control point, or reuse the current point.
                c1x = curX
                c1y = curY
                if lastCurve == 'c'
                {
                    c1x = 2 * curX - ctlX
                    c1y = 2 * curY - ctlY
                }
            }

            var c2x = number(data, &pos, &valid)
            var c2y = number(data, &pos, &valid)
            var x   = number(data, &pos, &valid)
            var y   = number(data, &pos, &valid)
            if !valid do
                return
            if rel
            {
                c2x += curX
                c2y += curY
                x   += curX
                y   += curY
            }

            let target   = mapPoint(state, x, y)
            let control1 = mapPoint(state, c1x, c1y)
            let control2 = mapPoint(state, c2x, c2y)
            path!.bezierTo(target.x, target.y, control1.x, control1.y, control2.x, control2.y)
            addMarkerVertex(vertices, {x, y}, {x - c2x, y - c2y}, {c1x - curX, c1y - curY})
            ctlX      = c2x
            ctlY      = c2y
            curX      = x
            curY      = y
            lastCurve = 'c'
            continue

        case 'Q', 'q', 'T', 't':
            var c1x, c1y: f32
            if cmd == 'Q' or cmd == 'q'
            {
                c1x = number(data, &pos, &valid)
                c1y = number(data, &pos, &valid)
                if rel
                {
                    c1x += curX
                    c1y += curY
                }
            }
            else
            {
                c1x = curX
                c1y = curY
                if lastCurve == 'q'
                {
                    c1x = 2 * curX - ctlX
                    c1y = 2 * curY - ctlY
                }
            }

            var x = number(data, &pos, &valid)
            var y = number(data, &pos, &valid)
            if !valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            let target  = mapPoint(state, x, y)
            let control = mapPoint(state, c1x, c1y)
            path!.bezierTo(target.x, target.y, control.x, control.y)
            addMarkerVertex(vertices, {x, y}, {x - c1x, y - c1y}, {c1x - curX, c1y - curY})
            ctlX      = c1x
            ctlY      = c1y
            curX      = x
            curY      = y
            lastCurve = 'q'
            continue

        case 'A', 'a':
            let rx       = number(data, &pos, &valid)
            let ry       = number(data, &pos, &valid)
            let rotation = number(data, &pos, &valid)
            let largeArc = flag(data, &pos, &valid)
            let sweepF   = flag(data, &pos, &valid)
            var x        = number(data, &pos, &valid)
            var y        = number(data, &pos, &valid)
            if !valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            appendArc(path!, state, curX, curY, rx, ry, rotation, largeArc, sweepF, x, y)
            addMarkerVertex(vertices, {x, y}, {x - curX, y - curY}, {x - curX, y - curY})
            curX = x
            curY = y

        default:
            return
        }

        lastCurve = 0
    }
}

// Elements /////////////////////////////////////////////////////////////////////

private func emitShape(drawing: *Drawing, list: LinePathList, state: *GroupState)
{
    if list.paths.isEmpty() do
        return
    if !state.isDisplayed or !state.isVisible or (!state.hasFill and !state.hasStroke) do
        return

    // The triangulated fill treats every extra contour of a list as a hole cut into
    // the first, so a path whose contours are DISJOINT unions (an arrow above a bar)
    // would lose all but one region. Decompose by containment depth: every even-depth
    // contour roots its own shape and odd-depth contours join their root as holes.
    if state.hasFill and list.paths.count > 1
    {
        var work = #move list
        let n    = work.paths.count
        for p in work.paths do
            p.flatten(.Normal)

        var depth: Array's32
        depth.resize(n)
        for i in n
        {
            let pi = work.paths[i]
            if pi.polygon.points.count == 0 do
                continue
            let probe = pi.polygon.points[0]
            for j in n where j != i
            {
                if work.paths[j].polygon.contains(probe) do
                    depth[i] += 1
            }
        }

        var roots = 0
        for i in n where depth[i] % 2 == 0 do
            roots += 1

        if roots > 1
        {
            for i in n
            {
                if depth[i] % 2 != 0 do
                    continue

                var group: LinePathList
                group.paths.add(work.paths[i])
                let rootPoly = &work.paths[i].polygon

                // Attach this root's immediate holes.
                for j in n
                {
                    if depth[j] != depth[i] + 1 do
                        continue
                    let pj = work.paths[j]
                    if pj.polygon.points.count and rootPoly.contains(pj.polygon.points[0]) do
                        group.paths.add(pj)
                }

                emitShape(drawing, #move group, state)
            }

            // Every path pointer now belongs to a group list; forget them here.
            work.paths.clear()
            return
        }

        // Single root: emit as one shape below.
        emitShapeOne(drawing, #move work, state)
        return
    }

    emitShapeOne(drawing, #move list, state)
}

private func emitShapeOne(drawing: *Drawing, list: LinePathList, state: *GroupState)
{
    let shapeIndex = drawing.shapes.count
    let shape      = drawing.shapes.emplaceInitAddress()
    shape.pathList = #move list
    shape.hidden   = state.inDefs

    shape.hasFill = state.hasFill
    if state.hasFill
    {
        shape.fillColor   = state.fillColor
        shape.fillPaintId = state.fillPaintId
        shape.fillOpacity = state.fillOpacity * state.opacity
        shape.evenOdd     = state.evenOdd
    }

    shape.hasStroke = state.hasStroke
    if state.hasStroke
    {
        shape.strokeColor   = state.strokeColor
        shape.strokePaintId = state.strokePaintId
        shape.strokeOpacity = state.strokeOpacity * state.opacity
        let geometryScale = transformScale(state.transform)
        shape.strokeWidth = state.strokeWidth * geometryScale
        let viewportDiagonal = Math.sqrt(drawing.width * drawing.width + drawing.height * drawing.height) / Math.ConstF32.Sqrt2
        shape.strokeOffset = (state.strokeOffset.isPercent ? state.strokeOffset.value * viewportDiagonal : state.strokeOffset.value) * geometryScale
        shape.strokeMiter  = state.strokeMiter
        for value in state.strokePattern
        {
            let length = value.isPercent ? value.value * viewportDiagonal : value.value
            shape.strokePattern.add(length * geometryScale)
        }

        shape.capStyle  = state.capStyle
        shape.joinStyle = state.joinStyle
    }

    shape.paintTransform = state.transform
    shape.filterId       = state.filterId

    if !shape.hidden do
        drawing.items.add(DrawingItem{.Shape, shapeIndex})
}

private func emitRect(drawing: *Drawing, state: *GroupState, x, y, w, h, rx, ry: f32)
{
    if w <= 0 or h <= 0 do
        return

    var list: LinePathList
    let path = list.newPath()
    let crx  = Math.min(rx, w * 0.5)
    let cry  = Math.min(ry, h * 0.5)

    if crx >= w * 0.5 - 0.001 and cry >= h * 0.5 - 0.001
    {
        // Full horizontal and vertical corner radii form an ellipse.
        appendEllipse(path, state, x + w * 0.5, y + h * 0.5, w * 0.5, h * 0.5)
    }
    elif isAxisAligned(state.transform)
    {
        let origin = mapPoint(state, x, y)
        let sx     = transformScaleX(state.transform)
        let sy     = transformScaleY(state.transform)
        if crx > 0 and cry > 0 do
            path.setRoundRectRaw(origin.x, origin.y, w * sx, h * sy, crx * sx, cry * sy)
        else do
            path.setRectRaw(origin.x, origin.y, w * sx, h * sy)
    }
    else do
        appendRectContour(path, state, x, y, w, h, crx, cry)
    emitShape(drawing, list, state)
}

private func emitEllipse(drawing: *Drawing, state: *GroupState, cx, cy, rx, ry: f32)
{
    if rx <= 0 or ry <= 0 do
        return

    var list: LinePathList
    let path = list.newPath()
    appendEllipse(path, state, cx, cy, rx, ry)
    emitShape(drawing, list, state)
}

private func emitPoly(drawing: *Drawing, state: *GroupState, points: string, closeIt: bool)
{
    var list: LinePathList
    let path = list.newPath()
    var pos  = 0'u64
    var idx  = 0

    while pos < points.count
    {
        var look = pos
        while look < points.count and (points[look] == ' ' or points[look] == ',') do
            look += 1
        if look >= points.count or !isNumberStart(points[look]) do
            break

        let x     = scanNumber(points, &pos)
        let y     = scanNumber(points, &pos)
        let point = mapPoint(state, x, y)
        if idx == 0 do
            path.start(point.x, point.y)
        else do
            path.lineTo(point.x, point.y)
        idx += 1
    }

    if idx < 2 do
        return
    if closeIt do
        path.close()
    emitShape(drawing, list, state)
}

private impl Parser
{
    mtd skipUntil(c: u8)
    {
        let len = (.text).count
        while .pos < len and .text[.pos] != c do
            .pos += 1
    }

    mtd parseStyleSheet()
    {
        let contentStart = .pos
        var contentEnd   = .pos
        while contentEnd + 7 < (.text).count
        {
            if .text[contentEnd] == '<' and .text[contentEnd + 1] == '/' and !Latin1.compare(cast(string) Swag.makeSlice((.text).buffer + contentEnd + 2, 5), "style", ignoreCase: true) do
                break
            contentEnd += 1
        }

        let content = cast(string) Swag.makeSlice((.text).buffer + contentStart, contentEnd - contentStart)
        var pos     = 0'u64
        while pos < content.count
        {
            while pos < content.count and content[pos] != '{' do
                pos += 1
            if pos >= content.count do
                break

            var selectorStart = pos
            while selectorStart and content[selectorStart - 1] != '}' do
                selectorStart -= 1
            let selector = Latin1.trim(cast(string) Swag.makeSlice(content.buffer + selectorStart, pos - selectorStart))
            pos += 1
            let declarationsStart = pos
            while pos < content.count and content[pos] != '}' do
                pos += 1
            if pos >= content.count do
                break

            if selector.count and selector[0] != '@' do
                .styles.add({String.from(selector), String.from(Latin1.trim(cast(string) Swag.makeSlice(content.buffer + declarationsStart, pos - declarationsStart)))})
            pos += 1
        }

        .pos = contentEnd
        .skipUntil('>')
        if .pos < (.text).count do
            .pos += 1
    }

    mtd applyStyleRules(elementName: string, geo: *HashTable'(String, String), state: *GroupState)
    {
        let idAttr    = geo.tryFind("id")
        let classAttr = geo.tryFind("class")

        // Apply increasing selector specificity, preserving source order within
        // each class. This deliberately supports the compact selectors common in
        // standalone artwork without pretending to be a complete CSS engine.
        for specificity in 3
        {
            for &rule in .styles
            {
                let selector = rule.selector.toString()
                var matches  = false
                switch specificity
                {
                case 0:
                    matches = selector.count and selector[0] != '.' and selector[0] != '#' and !Latin1.compare(selector, elementName, ignoreCase: true)

                case 1:
                    if selector.count > 1 and selector[0] == '.' and classAttr
                    {
                        let wanted  = cast(string) Swag.makeSlice(selector.buffer + 1, selector.count - 1)
                        var classes = classAttr.value.toString()
                        while classes.count
                        {
                            var end = 0'u64
                            while end < classes.count and classes[end] != ' ' and classes[end] != '\t' and classes[end] != '\n' and classes[end] != '\r' do
                                end += 1
                            if !Latin1.compare(cast(string) Swag.makeSlice(classes.buffer, end), wanted) do
                                matches = true
                            if matches or end == classes.count do
                                break
                            classes = Latin1.trim(cast(string) Swag.makeSlice(classes.buffer + end, classes.count - end))
                        }
                    }

                case 2:
                    if selector.count > 1 and selector[0] == '#' and idAttr do
                        matches = !Latin1.compare(cast(string) Swag.makeSlice(selector.buffer + 1, selector.count - 1), idAttr.value.toString())
                }

                if matches do
                    applyAttribute(state, "style", rule.declarations.toString())
            }
        }

        let inlineStyle = geo.tryFind("style")
        if inlineStyle do
            applyAttribute(state, "style", inlineStyle.value.toString())
    }

    // Scans the attributes of the current element into `state` and collects the
    // geometry attributes by name.
    mtd scanAttributes(state: *GroupState, geo: *HashTable'(String, String))->{ selfClosed: bool }
    {
        var result: retval
        let len = (.text).count

        while .pos < len
        {
            while .pos < len and (.text[.pos] == ' ' or .text[.pos] == '\t' or .text[.pos] == '\n' or .text[.pos] == '\r') do
                .pos += 1
            if .pos >= len do
                break

            if .text[.pos] == '/'
            {
                result.selfClosed = true
                .pos              += 1
                continue
            }

            if .text[.pos] == '>'
            {
                .pos += 1
                break
            }

            let nameStart = .pos
            while .pos < len and .text[.pos] != '=' and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' do
                .pos += 1
            let name = cast(string) Swag.makeSlice((.text).buffer + nameStart, .pos - nameStart)

            while .pos < len and .text[.pos] != '=' and .text[.pos] != '>' and .text[.pos] != '/' do
                .pos += 1
            if .pos >= len or .text[.pos] != '=' do
                continue
            .pos += 1

            while .pos < len and .text[.pos] != '"' and .text[.pos] != '\'' do
                .pos += 1
            if .pos >= len do
                break
            let quote = .text[.pos]
            .pos += 1
            let valueStart = .pos
            while .pos < len and .text[.pos] != quote do
                .pos += 1
            let value = cast(string) Swag.makeSlice((.text).buffer + valueStart, .pos - valueStart)
            .pos += 1

            switch name
            {
            case "d", "x", "y", "dx", "dy", "width", "height", "rx", "ry", "cx", "cy", "r", "fx", "fy", "fr", "points", "pathLength", "x1", "y1", "x2", "y2", "viewBox", "id", "class", "href", "xlink:href", "gradientUnits", "gradientTransform", "spreadMethod", "patternUnits", "patternContentUnits", "stdDeviation", "offset", "stop-color", "stop-opacity", "flood-color", "flood-opacity", "markerWidth", "markerHeight", "refX", "refY", "orient", "markerUnits":
                geo.add(name, value)

            case "style":
                geo.add(name, value)
                applyAttribute(state, name, value)

            default:
                applyAttribute(state, name, value)
            }
        }

        return result
    }

    mtd geoNumber(geo: *HashTable'(String, String), name: string, defaultValue = 0.0'f32)->f32
    {
        let here = geo.tryFind(name)
        if !here do
            return defaultValue
        var pos = 0'u64
        return scanNumber(here.value.toString(), &pos)
    }

    mtd geoLength(geo: *HashTable'(String, String), name: string, defaultValue: SvgLength)->SvgLength
    {
        let here = geo.tryFind(name)
        if !here do
            return defaultValue
        return parseLength(here.value.toString(), defaultValue)
    }

    mtd applyPathLength(first, count: u64, authoredLength, geometryScale: f32)
    {
        if authoredLength <= 0 or Math.abs(geometryScale) <= 0.000001 do
            return

        var actualLength: f32
        for i in count
        {
            let shape = &.drawing.shapes[first + i]
            shape.pathList.flatten(.Normal)
            for path in shape.pathList.paths
            {
                let pointCount = path.polygon.points.count
                for j in 1 until pointCount do
                    actualLength += path.polygon.points[j - 1].distanceTo(path.polygon.points[j])
                if path.isClosed and pointCount > 1 do
                    actualLength += path.polygon.points[pointCount - 1].distanceTo(path.polygon.points[0])
            }
        }

        if actualLength <= 0 do
            return
        let scale = actualLength / (authoredLength * Math.abs(geometryScale))
        for i in count
        {
            let shape = &.drawing.shapes[first + i]
            for &value in shape.strokePattern do
                value[] *= scale
            shape.strokeOffset *= scale
        }
    }

    mtd parseGradientStops(gradient: *Gradient) fail
    {
        let len = (.text).count
        while .pos < len
        {
            .skipUntil('<')
            if .pos >= len do
                return
            .pos += 1
            if .pos >= len do
                return

            if .text[.pos] == '/'
            {
                .skipUntil('>')
                .pos += 1
                return
            }

            if .text[.pos] == '?' or .text[.pos] == '!'
            {
                .skipUntil('>')
                .pos += 1
                continue
            }

            let nameStart = .pos
            while .pos < len and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' and .text[.pos] != '\t' and .text[.pos] != '\n' and .text[.pos] != '\r' do
                .pos += 1
            let name = cast(string) Swag.makeSlice((.text).buffer + nameStart, .pos - nameStart)

            var state: GroupState
            var geo:   HashTable'(String, String)
            let {selfClosed} = .scanAttributes(&state, &geo)
            if name == "stop"
            {
                var offset     = SvgLength{}
                let offsetAttr = geo.tryFind("offset")
                if offsetAttr do
                    offset = parseLength(offsetAttr.value.toString())

                var color     = Color.fromArgb(Argb.Black)
                var colorValue: String
                let colorAttr = geo.tryFind("stop-color")
                if colorAttr do
                    colorValue = colorAttr.value
                let style = geo.tryFind("style")
                if style
                {
                    let styled = styleValue(style.value.toString(), "stop-color")
                    if !styled.isEmpty() do
                        colorValue = #move styled
                }

                if !colorValue.isEmpty() do
                    color = parseColor(colorValue.toString()).color

                var opacity     = 1.0'f32
                let opacityAttr = geo.tryFind("stop-opacity")
                if opacityAttr
                {
                    let parsed = parseLength(opacityAttr.value.toString(), {1, false})
                    opacity = Math.saturate(parsed.value)
                }

                if style
                {
                    let styled = styleValue(style.value.toString(), "stop-opacity")
                    if !styled.isEmpty()
                    {
                        let parsed = parseLength(styled.toString(), {1, false})
                        opacity = Math.saturate(parsed.value)
                    }
                }

                color.a = cast(u8) Math.round(cast(f32) color.a * opacity)
                var normalizedOffset = Math.saturate(offset.value)
                if gradient.stops.count do
                    normalizedOffset = Math.max(normalizedOffset, gradient.stops.back().offset)
                gradient.stops.add({normalizedOffset, color})
            }

            if !selfClosed do
                try .parseGradientStops(gradient)
        }
    }

    mtd parseGradient(kind: GradientKind, geo: *HashTable'(String, String), selfClosed: bool) fail
    {
        var gradient: Gradient

        // The reference is kept rather than followed: a document may name a gradient defined
        // further down, and only the finished document knows every identifier.
        var href = geo.tryFind("href")
        if !href do
            href = geo.tryFind("xlink:href")
        if href
        {
            var baseId = href.value.toString()
            if baseId.count and baseId[0] == '#' do
                baseId = cast(string) Swag.makeSlice(baseId.buffer + 1, baseId.count - 1)
            gradient.href = String.from(baseId)
        }

        gradient.kind = kind
        switch kind
        {
        case .Linear:
            gradient.x1 = .geoLength(geo, "x1", gradient.x1)
            gradient.y1 = .geoLength(geo, "y1", gradient.y1)
            gradient.x2 = .geoLength(geo, "x2", gradient.x2)
            gradient.y2 = .geoLength(geo, "y2", gradient.y2)

            gradient.specified.x1 = geo.tryFind("x1") != null
            gradient.specified.y1 = geo.tryFind("y1") != null
            gradient.specified.x2 = geo.tryFind("x2") != null
            gradient.specified.y2 = geo.tryFind("y2") != null

        case .Radial:
            gradient.cx = .geoLength(geo, "cx", gradient.cx)
            gradient.cy = .geoLength(geo, "cy", gradient.cy)
            gradient.r  = .geoLength(geo, "r", gradient.r)
            gradient.fx = .geoLength(geo, "fx", gradient.cx)
            gradient.fy = .geoLength(geo, "fy", gradient.cy)
            gradient.fr = .geoLength(geo, "fr", gradient.fr)

            gradient.specified.cx = geo.tryFind("cx") != null
            gradient.specified.cy = geo.tryFind("cy") != null
            gradient.specified.r  = geo.tryFind("r") != null
            gradient.specified.fx = geo.tryFind("fx") != null
            gradient.specified.fy = geo.tryFind("fy") != null
            gradient.specified.fr = geo.tryFind("fr") != null
        }

        let units = geo.tryFind("gradientUnits")
        if units
        {
            gradient.userSpace       = units.value.toString() == "userSpaceOnUse"
            gradient.specified.units = true
        }

        let spread = geo.tryFind("spreadMethod")
        if spread
        {
            switch spread.value.toString()
            {
            case "repeat":  gradient.spread = .Repeat
            case "reflect": gradient.spread = .Mirror
            default:        gradient.spread = .Clamp
            }

            gradient.specified.spread = true
        }

        let transform = geo.tryFind("gradientTransform")
        if transform
        {
            gradient.transform           = composeTransformList(transform.value.toString(), Math.Transform2.Identity)
            gradient.specified.transform = true
        }

        if !selfClosed
        {
            gradient.stops.clear()
            try .parseGradientStops(&gradient)
            gradient.specified.stops = gradient.stops.count != 0
        }

        let id = geo.tryFind("id")
        if id do
            .gradients.add(id.value, #move gradient)
    }

    mtd loadImage(href: string)->Image fail
    {
        if Utf8.startsWith(href, "data:")
        {
            // The decoded size is bounded by the encoded length, so the byte budget is enforced
            // before anything is allocated.
            if (href.count / 4) * 3 > .options.maxImageBytes do
                fail Swag.SystemError{"embedded SVG image exceeds the configured byte limit"}
            return try Image.fromDataUri(href)
        }

        if (.options.externalResourceRoot).count == 0 do
            fail Swag.SystemError{"external SVG image references are disabled"}
        if Path.isRooted(href) do
            fail Swag.SystemError{"absolute SVG image references are not allowed"}

        let combined = Path.combine(.options.externalResourceRoot, href)
        let fullPath = try Path.absolute(combined.toString())
        if !Env.isInsideDirectory(.options.externalResourceRoot, fullPath.toString()) do
            fail Swag.SystemError{"SVG image reference escapes its configured resource root"}
        let info = try File.info(fullPath.toString())
        if info.size > .options.maxImageBytes do
            fail Swag.SystemError{"external SVG image exceeds the configured byte limit"}
        return try Image.load(fullPath.toString())
    }

    mtd emitImage(state: *GroupState, geo: *HashTable'(String, String)) fail
    {
        if !state.isDisplayed or !state.isVisible do
            return

        var href = geo.tryFind("href")
        if !href do
            href = geo.tryFind("xlink:href")
        if !href do
            return

        let width  = .geoNumber(geo, "width")
        let height = .geoNumber(geo, "height")
        if width <= 0 or height <= 0 do
            return

        let index = .drawing.images.count
        let item  = .drawing.images.emplaceInitAddress()
        item.image = try .loadImage(href.value.toString())

        // A raster rectangle has no rotated form here: the origin is transformed and the extents
        // take the axis scales, which is exact for every transform that keeps the axes.
        let origin = mapPoint(state, .geoNumber(geo, "x"), .geoNumber(geo, "y"))
        item.rect    = {origin.x, origin.y, width * transformScaleX(state.transform), height * transformScaleY(state.transform)}
        item.opacity = state.opacity
        if !state.inDefs do
            .drawing.items.add(DrawingItem{.Image, index})
    }

    // Loads, once per document, the typeface a family class resolves to.
    //
    // A machine that does not carry the configured serif or monospace file still has to
    // draw the text, so a family that cannot be loaded falls back to the default face
    // instead of failing the document; only a document with no usable face at all fails.
    mtd typeFaceFor(kind: FontFamilyKind)->*TypeFace fail
    {
        let slot = cast(u64) kind
        if .typeFaces[slot] do
            return .typeFaces[slot]!

        var fileName = .options.fontFileName
        switch kind
        {
        case .Serif: fileName = .options.serifFontFileName
        case .Mono:  fileName = .options.monoFontFileName
        }

        if fileName.count == 0 or !TypeFace.exists(fileName) do
            fileName = .options.fontFileName
        if fileName.count == 0 do
            fail Swag.SystemError{"SVG text requires a configured font file"}

        let face = try TypeFace.load(fileName)
        .typeFaces[slot] = face
        return face
    }

    mtd addTextRun(text: string, state: *GroupState, geo: *HashTable'(String, String), block: *SvgText, first: bool) fail
    {
        let normalized = normalizedText(text)
        if normalized.isEmpty() or !state.isDisplayed or !state.isVisible or !state.hasFill do
            return

        let typeFace = try .typeFaceFor(state.fontFamily)

        let x   = geo.tryFind("x")
        let y   = geo.tryFind("y")
        let dx  = .geoNumber(geo, "dx")
        let dy  = .geoNumber(geo, "dy")
        let run = block.runs.emplaceInitAddress()
        run.text     = #move normalized
        run.typeFace = typeFace
        run.hasX     = first or x != null
        run.hasY     = first or y != null
        let anchor = mapPoint(state, x ? .geoNumber(geo, "x") : 0, y ? .geoNumber(geo, "y") : 0)
        let offset = mapVector(state.transform, dx, dy)
        run.x             = anchor.x
        run.y             = anchor.y
        run.dx            = offset.x
        run.dy            = offset.y
        run.fontSize      = state.fontSize * transformScaleY(state.transform)
        run.letterSpacing = state.letterSpacing * transformScaleX(state.transform)
        run.wordSpacing   = state.wordSpacing * transformScaleX(state.transform)
        run.rotation      = transformRotation(state.transform)
        run.color         = state.fillColor
        run.opacity       = state.fillOpacity * state.opacity
        run.anchor        = state.textAnchor
        run.forceBold     = state.forceBold
        run.forceItalic   = state.forceItalic
    }

    mtd parseText(state: GroupState, geo: *HashTable'(String, String), selfClosed: bool) fail
    {
        let index = .drawing.texts.count
        let block = .drawing.texts.emplaceInitAddress()
        if selfClosed do
            return

        let len   = (.text).count
        var first = true
        while .pos < len
        {
            let textStart = .pos
            .skipUntil('<')
            if .pos > textStart
            {
                let content = cast(string) Swag.makeSlice((.text).buffer + textStart, .pos - textStart)
                try .addTextRun(content, &state, geo, block, first)
                first = false
            }

            if .pos >= len do
                break
            .pos += 1
            if .pos < len and .text[.pos] == '/'
            {
                .skipUntil('>')
                .pos += 1
                break
            }

            let nameStart = .pos
            while .pos < len and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' and .text[.pos] != '\t' and .text[.pos] != '\n' and .text[.pos] != '\r' do
                .pos += 1
            let name = cast(string) Swag.makeSlice((.text).buffer + nameStart, .pos - nameStart)

            var childState                = state
            var childGeo: HashTable'(String, String)
            let {selfClosed: childClosed} = .scanAttributes(&childState, &childGeo)
            .applyStyleRules(name, &childGeo, &childState)
            if name != "tspan"
            {
                if !childClosed do
                    try .parseContent(childState)
                continue
            }

            let childStart = .pos
            .skipUntil('<')
            let childText = cast(string) Swag.makeSlice((.text).buffer + childStart, .pos - childStart)
            try .addTextRun(childText, &childState, &childGeo, block, first)
            first = false
            if !childClosed
            {
                .skipUntil('>')
                .pos += 1
            }
        }

        if block.runs.count and !state.inDefs do
            .drawing.items.add(DrawingItem{.Text, index})
    }

    mtd parsePattern(state: GroupState, geo: *HashTable'(String, String), selfClosed: bool) fail
    {
        let first        = .drawing.shapes.count
        var contentState = state
        contentState.inDefs = true
        if !selfClosed do
            try .parseContent(contentState)

        let id = geo.tryFind("id")
        if !id do
            return

        var pattern: Pattern
        pattern.first  = first
        pattern.count  = .drawing.shapes.count - first
        pattern.x      = .geoLength(geo, "x", {})
        pattern.y      = .geoLength(geo, "y", {})
        pattern.width  = .geoLength(geo, "width", {})
        pattern.height = .geoLength(geo, "height", {})
        let units = geo.tryFind("patternUnits")
        pattern.userSpace = units != null and units.value.toString() == "userSpaceOnUse"
        .patterns.add(id.value, #move pattern)
    }

    mtd parseFilter(geo: *HashTable'(String, String), selfClosed: bool) fail
    {
        var filter: SvgFilter
        if !selfClosed
        {
            let len = (.text).count
            while .pos < len
            {
                .skipUntil('<')
                if .pos >= len do
                    break
                .pos += 1
                if .pos < len and .text[.pos] == '/'
                {
                    .skipUntil('>')
                    .pos += 1
                    break
                }

                let nameStart = .pos
                while .pos < len and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' and .text[.pos] != '\t' and .text[.pos] != '\n' and .text[.pos] != '\r' do
                    .pos += 1
                let name = cast(string) Swag.makeSlice((.text).buffer + nameStart, .pos - nameStart)
                var state: GroupState
                var attrs: HashTable'(String, String)
                let {selfClosed: childClosed} = .scanAttributes(&state, &attrs)

                var primitive: FilterPrimitive
                var keep = true
                switch name
                {
                case "feGaussianBlur":
                    primitive.kind   = .GaussianBlur
                    primitive.radius = Math.max(.geoNumber(&attrs, "stdDeviation"), 0)

                case "feOffset":
                    primitive.kind = .Offset
                    primitive.x    = .geoNumber(&attrs, "dx")
                    primitive.y    = .geoNumber(&attrs, "dy")

                case "feDropShadow":
                    primitive.kind   = .DropShadow
                    primitive.x      = .geoNumber(&attrs, "dx")
                    primitive.y      = .geoNumber(&attrs, "dy")
                    primitive.radius = Math.max(.geoNumber(&attrs, "stdDeviation"), 0)
                    let flood = attrs.tryFind("flood-color")
                    if flood do
                        primitive.color = parseColor(flood.value.toString()).color
                    let opacity = attrs.tryFind("flood-opacity")
                    if opacity do
                        primitive.color = primitive.color.withAlphaF32(Math.saturate(parseLength(opacity.value.toString()).value))

                default:
                    keep = false
                }

                if keep do
                    filter.primitives.add(primitive)
                if !childClosed do
                    try .parseContent(state)
            }
        }

        let id = geo.tryFind("id")
        if id do
            .filters.add(id.value, #move filter)
    }

    // Parses the elements between the current position and the parent's close tag.
    mtd parseContent(parent: GroupState) fail
    {
        let len = (.text).count
        while .pos < len
        {
            .skipUntil('<')
            if .pos >= len do
                return
            .pos += 1
            if .pos >= len do
                return

            // Closing tag of the parent scope.
            if .text[.pos] == '/'
            {
                .skipUntil('>')
                .pos += 1
                return
            }

            // Declarations and comments.
            if .text[.pos] == '?' or .text[.pos] == '!'
            {
                .skipUntil('>')
                .pos += 1
                continue
            }

            let nameStart = .pos
            while .pos < len and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' and .text[.pos] != '\t' and .text[.pos] != '\n' and .text[.pos] != '\r' do
                .pos += 1
            let name = cast(string) Swag.makeSlice((.text).buffer + nameStart, .pos - nameStart)

            var state        = parent
            var geo: HashTable'(String, String)
            let {selfClosed} = .scanAttributes(&state, &geo)
            .applyStyleRules(name, &geo, &state)

            // A clip is stated in the user space of the element that names it, and children may
            // add transforms of their own; remembering that space here is what keeps an
            // inherited clip where the group put it.
            if state.clipPathId != parent.clipPathId do
                state.clipTransform = state.transform

            let firstShape = .drawing.shapes.count
            let firstItem  = .drawing.items.count

            switch name
            {
            case "svg":
                let isRoot = .svgDepth == 0
                .svgDepth += 1
                if isRoot
                {
                    let vb = geo.tryFind("viewBox")
                    if vb
                    {
                        var pos   = 0'u64
                        let viewX = scanNumber(vb.value.toString(), &pos)
                        let viewY = scanNumber(vb.value.toString(), &pos)
                        .drawing.width  = scanNumber(vb.value.toString(), &pos)
                        .drawing.height = scanNumber(vb.value.toString(), &pos)
                        state.transform = prependTranslation(state.transform, -viewX, -viewY)
                    }
                    else
                    {
                        .drawing.width  = .geoNumber(&geo, "width", 0)
                        .drawing.height = .geoNumber(&geo, "height", 0)
                    }
                }
                else
                {
                    state.transform = prependTranslation(state.transform, .geoNumber(&geo, "x"), .geoNumber(&geo, "y"))
                }

                if !selfClosed do
                    try .parseContent(state)
                .svgDepth -= 1

            case "g":
                if !selfClosed do
                    try .parseContent(state)

            case "path":
                let d = geo.tryFind("d")
                if d
                {
                    var list:     LinePathList
                    var vertices: Array'MarkerVertex
                    parsePathData(&list, d.value.toString(), &state, state.hasMarkers() ? &vertices : null)
                    emitShape(.drawing, list, &state)
                    .applyMarkers(&state, vertices.toSlice())
                }

                if !selfClosed do
                    try .parseContent(state)

            case "rect":
                var rx = .geoNumber(&geo, "rx", -1)
                var ry = .geoNumber(&geo, "ry", -1)
                if rx < 0 do
                    rx = ry
                if ry < 0 do
                    ry = rx
                emitRect(.drawing, &state, .geoNumber(&geo, "x"), .geoNumber(&geo, "y"), .geoNumber(&geo, "width"), .geoNumber(&geo, "height"), Math.max(rx, 0), Math.max(ry, 0))
                if !selfClosed do
                    try .parseContent(state)

            case "circle":
                let r = .geoNumber(&geo, "r")
                emitEllipse(.drawing, &state, .geoNumber(&geo, "cx"), .geoNumber(&geo, "cy"), r, r)
                if !selfClosed do
                    try .parseContent(state)

            case "ellipse":
                emitEllipse(.drawing, &state, .geoNumber(&geo, "cx"), .geoNumber(&geo, "cy"), .geoNumber(&geo, "rx"), .geoNumber(&geo, "ry"))
                if !selfClosed do
                    try .parseContent(state)

            case "line":
                var list: LinePathList
                let path   = list.newPath()
                let x1     = .geoNumber(&geo, "x1")
                let y1     = .geoNumber(&geo, "y1")
                let x2     = .geoNumber(&geo, "x2")
                let y2     = .geoNumber(&geo, "y2")
                let from   = mapPoint(&state, x1, y1)
                let target = mapPoint(&state, x2, y2)
                path.start(from.x, from.y)
                path.lineTo(target.x, target.y)
                var strokeOnly = state
                strokeOnly.hasFill = false
                emitShape(.drawing, list, &strokeOnly)

                if state.hasMarkers()
                {
                    let direction = Vector2{x2 - x1, y2 - y1}
                    var vertices: Array'MarkerVertex
                    vertices.add(MarkerVertex{{x1, y1}, {}, direction})
                    vertices.add(MarkerVertex{{x2, y2}, direction, {}})
                    .applyMarkers(&state, vertices.toSlice())
                }

                if !selfClosed do
                    try .parseContent(state)

            case "defs":

                // Definitions are parsed in local coordinates and withheld from
                // painting; `use` elements instantiate them.
                var defState: GroupState
                defState.inDefs = true
                if !selfClosed do
                    try .parseContent(defState)

            case "clipPath":

                // A clip is geometry, not paint: its children are parsed in their own
                // coordinates and kept out of the paint order, and every element that names the
                // clip instantiates a copy under its own transform.
                var clipState: GroupState
                clipState.inDefs = true
                let clipFirst = .drawing.shapes.count
                if !selfClosed do
                    try .parseContent(clipState)

                let clipId = geo.tryFind("id")
                if clipId and .drawing.shapes.count > clipFirst do
                    .clipPaths.add(clipId.value, {clipFirst, .drawing.shapes.count - clipFirst})

            case "symbol":

                // A symbol is a definition with a viewport. Its children are parsed like any
                // other definition, and the view box it declares is what a `use` fits into the
                // size it asks for.
                var symbolState: GroupState
                symbolState.inDefs = true
                let symbolFirst = .drawing.shapes.count
                if !selfClosed do
                    try .parseContent(symbolState)

                let symbolId = geo.tryFind("id")
                if symbolId and .drawing.shapes.count > symbolFirst
                {
                    .defs.add(symbolId.value, {symbolFirst, .drawing.shapes.count - symbolFirst})

                    var viewport: SymbolViewport
                    let box = geo.tryFind("viewBox")
                    if box
                    {
                        var boxPos = 0'u64
                        viewport.viewX      = scanNumber(box.value.toString(), &boxPos)
                        viewport.viewY      = scanNumber(box.value.toString(), &boxPos)
                        viewport.viewWidth  = scanNumber(box.value.toString(), &boxPos)
                        viewport.viewHeight = scanNumber(box.value.toString(), &boxPos)
                        viewport.hasViewBox = true
                    }

                    .symbols.add(symbolId.value, viewport)
                }

            case "marker":

                // A marker is a definition with its own viewport and its own orientation rule.
                // Its children are parsed in that viewport's coordinates and kept out of the
                // paint order; the elements that reference it place copies on their vertices.
                var markerState: GroupState
                markerState.inDefs = true
                let markerFirst = .drawing.shapes.count
                if !selfClosed do
                    try .parseContent(markerState)

                let markerId = geo.tryFind("id")
                if markerId and .drawing.shapes.count > markerFirst do
                    .markers.add(markerId.value, .readMarkerDefinition(&geo, markerFirst, .drawing.shapes.count - markerFirst))

            case "linearGradient":
                try .parseGradient(.Linear, &geo, selfClosed)

            case "radialGradient":
                try .parseGradient(.Radial, &geo, selfClosed)

            case "pattern":
                try .parsePattern(state, &geo, selfClosed)

            case "filter":
                try .parseFilter(&geo, selfClosed)

            case "style":
                if !selfClosed do
                    .parseStyleSheet()

            case "text":
                try .parseText(state, &geo, selfClosed)

            case "image":
                try .emitImage(&state, &geo)
                if !selfClosed do
                    try .parseContent(state)

            case "use":
                var href = geo.tryFind("href")
                if !href do
                    href = geo.tryFind("xlink:href")
                if href
                {
                    var target = href.value.toString()
                    if target.count and target[0] == '#' do
                        target = cast(string) Swag.makeSlice(target.buffer + 1, target.count - 1)
                    let here = .defs.tryFind(target)
                    if here
                    {
                        var useState = state
                        useState.transform = prependTranslation(state.transform, .geoNumber(&geo, "x"), .geoNumber(&geo, "y"))

                        // A referenced `symbol` brings its own viewport: its view box is fitted
                        // into the width and height the instance states, which is what makes one
                        // symbol usable at several sizes.
                        let symbol = .symbols.tryFind(target)
                        if symbol and symbol.value.hasViewBox
                        {
                            let width  = .geoNumber(&geo, "width", symbol.value.viewWidth)
                            let height = .geoNumber(&geo, "height", symbol.value.viewHeight)
                            if symbol.value.viewWidth > 0 and symbol.value.viewHeight > 0 and width > 0 and height > 0
                            {
                                var fit = Math.Transform2.createTranslation(-symbol.value.viewX, -symbol.value.viewY)
                                fit.multiply(Math.Transform2.createScale(width / symbol.value.viewWidth, height / symbol.value.viewHeight, 0, 0))
                                fit.multiply(useState.transform)
                                useState.transform = fit
                            }
                        }

                        discard .instantiate(here.value.first, here.value.count, &useState)
                    }
                }

                if !selfClosed do
                    try .parseContent(state)

            case "polygon":
                let pts = geo.tryFind("points")
                if pts
                {
                    emitPoly(.drawing, &state, pts.value.toString(), true)
                    var vertices = polyVertices(pts.value.toString(), state.hasMarkers())
                    .applyMarkers(&state, vertices.toSlice())
                }

                if !selfClosed do
                    try .parseContent(state)

            case "polyline":
                let pts = geo.tryFind("points")
                if pts
                {
                    var strokeOnly = state
                    strokeOnly.hasFill = false
                    emitPoly(.drawing, &strokeOnly, pts.value.toString(), false)
                    var vertices = polyVertices(pts.value.toString(), state.hasMarkers())
                    .applyMarkers(&state, vertices.toSlice())
                }

                if !selfClosed do
                    try .parseContent(state)

            default:

                // Unknown element: ignore it and its whole subtree.
                if !selfClosed do
                    try .parseContent(state)
            }

            let authoredPathLength = .geoNumber(&geo, "pathLength", -1)
            if authoredPathLength > 0 and .drawing.shapes.count > firstShape do
                .applyPathLength(firstShape, .drawing.shapes.count - firstShape, authoredPathLength, transformScale(state.transform))

            // Register the shapes a defs child emitted under its id.
            if state.inDefs and .drawing.shapes.count > firstShape
            {
                let idAttr = geo.tryFind("id")
                if idAttr do
                    .defs.add(idAttr.value, {firstShape, .drawing.shapes.count - firstShape})
            }

            .applyClipPath(&state, firstItem)
        }
    }

    // Reads a `marker` element's viewport, reference point and orientation rule.
    mtd readMarkerDefinition(geo: *HashTable'(String, String), first, count: u64)->MarkerDefinition
    {
        var result: retval
        result.first  = first
        result.count  = count
        result.refX   = .geoNumber(geo, "refX")
        result.refY   = .geoNumber(geo, "refY")
        result.width  = .geoNumber(geo, "markerWidth", 3)
        result.height = .geoNumber(geo, "markerHeight", 3)

        let units = geo.tryFind("markerUnits")
        if units do
            result.scaleWithWidth = units.value.toString() != "userSpaceOnUse"

        let box = geo.tryFind("viewBox")
        if box
        {
            var boxPos = 0'u64
            result.viewX      = scanNumber(box.value.toString(), &boxPos)
            result.viewY      = scanNumber(box.value.toString(), &boxPos)
            result.viewWidth  = scanNumber(box.value.toString(), &boxPos)
            result.viewHeight = scanNumber(box.value.toString(), &boxPos)
            result.hasViewBox = true
        }

        let orient = geo.tryFind("orient")
        if orient
        {
            let text = Latin1.trim(orient.value.toString())
            if !Latin1.compare(text, "auto-start-reverse", ignoreCase: true)
            {
                result.orientAuto         = true
                result.orientStartReverse = true
            }
            elif !Latin1.compare(text, "auto", ignoreCase: true) do
                result.orientAuto = true
            else
            {
                var anglePos = 0'u64
                result.angle = Math.toRadians(scanNumber(text, &anglePos))
            }
        }

        return result
    }

    // Draws the markers an element's state names on the vertices it produced.
    //
    // The first vertex takes `marker-start`, the last takes `marker-end`, and every other one
    // takes `marker-mid`; a contour of a single point is a start, which is what makes a lone
    // `moveto` still show its marker.
    mtd applyMarkers(state: *GroupState, vertices: const [..] MarkerVertex)
    {
        if state.inDefs or vertices.count == 0 do
            return
        if state.markerStartId.isEmpty() and state.markerMidId.isEmpty() and state.markerEndId.isEmpty() do
            return

        for vertex, index in vertices
        {
            let isStart = index == 0
            var id      = state.markerMidId
            if isStart do
                id = state.markerStartId
            elif index == vertices.count - 1 do
                id = state.markerEndId
            if id.isEmpty() do
                continue

            let definition = .markers.tryFind(id.toString())
            if !definition or definition.value.count == 0 do
                continue

            .placeMarker(&definition.value, state, vertex, isStart)
        }
    }

    // Instantiates one marker on one vertex.
    //
    // The definition's own viewport is fitted first, then the reference point is moved onto the
    // vertex, then the stroke width scales it and the tangent turns it. `auto` splits the angle
    // between the directions the outline arrives and leaves along, which is what keeps a marker
    // aligned on a corner instead of on one of its two sides.
    mtd placeMarker(definition: const *MarkerDefinition, state: *GroupState, vertex: MarkerVertex, isStart: bool)
    {
        var angle = definition.angle
        if definition.orientAuto
        {
            var direction = Vector2{vertex.inDir.x + vertex.outDir.x, vertex.inDir.y + vertex.outDir.y}
            if Math.isZeroEpsilon(direction.x) and Math.isZeroEpsilon(direction.y) do
                direction = (vertex.outDir.x != 0 or vertex.outDir.y != 0) ? vertex.outDir : vertex.inDir
            if direction.x != 0 or direction.y != 0 do
                angle = Math.atan2(direction.y, direction.x)
            if isStart and definition.orientStartReverse do
                angle += Math.ConstF32.Pi
        }

        var placement = Math.Transform2.Identity
        if definition.hasViewBox and definition.viewWidth > 0 and definition.viewHeight > 0
        {
            // The view box meets the marker viewport: one uniform scale, centred on the axis
            // that has room left over.
            let fit = Math.min(definition.width / definition.viewWidth, definition.height / definition.viewHeight)
            placement = Math.Transform2.createTranslation(-definition.viewX, -definition.viewY)
            placement.multiply(Math.Transform2.createScale(fit, fit, 0, 0))
            placement.multiply(Math.Transform2.createTranslation((definition.width - definition.viewWidth * fit) * 0.5, (definition.height - definition.viewHeight * fit) * 0.5))

            let reference = placement.transformPoint({definition.refX, definition.refY})
            placement.multiply(Math.Transform2.createTranslation(-reference.x, -reference.y))
        }
        else do
            placement = Math.Transform2.createTranslation(-definition.refX, -definition.refY)

        if definition.scaleWithWidth
        {
            let width = Math.max(state.strokeWidth, 0)
            placement.multiply(Math.Transform2.createScale(width, width, 0, 0))
        }

        placement.multiply(Math.Transform2.createRotation(angle, 0, 0))
        placement.multiply(Math.Transform2.createTranslation(vertex.point.x, vertex.point.y))
        placement.multiply(state.transform)

        var markerState: GroupState
        markerState.transform = placement
        discard .instantiate(definition.first, definition.count, &markerState)
    }

    // Gives the items an element just emitted the clip its state names.
    //
    // The clip's own shapes are instantiated once, under the transform of the element that
    // named the clip rather than of the element being drawn, and every item of the element
    // points at that one copy. An element with no clip, an unresolved reference, or an empty
    // clip definition is left alone.
    mtd applyClipPath(state: *GroupState, firstItem: u64)
    {
        if state.inDefs or state.clipPathId.isEmpty() or .drawing.items.count == firstItem do
            return

        let definition = .clipPaths.tryFind(state.clipPathId)
        if !definition or definition.value.count == 0 do
            return

        var clipState: GroupState
        clipState.transform = state.clipTransform
        let clip = .instantiate(definition.value.first, definition.value.count, &clipState, hidden: true)
        if clip.count == 0 do
            return

        for i in .drawing.items.count - firstItem
        {
            let item = &.drawing.items[firstItem + i]
            item.clipFirst = clip.first
            item.clipCount = clip.count
        }
    }

    mtd shapeBounds(shape: const *Shape)->{ min, max: Vector2 }
    {
        var result: retval
        result.min = Vector2.Max
        result.max = Vector2.NegMax
        for path in shape.pathList.paths
        {
            result.min = Vector2.min(result.min, path.minBounds)
            result.max = Vector2.max(result.max, path.maxBounds)
        }

        return result
    }

    mtd gradientCoordinate(length: SvgLength, begin, extent, viewportExtent: f32, userSpace: bool)->f32
    {
        if userSpace do
            return length.isPercent ? length.value * viewportExtent : length.value
        return begin + length.value * extent
    }

    mtd gradientPoint(gradient: const *Gradient, shape: const *Shape, x, y: SvgLength, boundsMin, boundsSize: Vector2)->Vector2
    {
        let px = .gradientCoordinate(x, boundsMin.x, boundsSize.x, .drawing.width, gradient.userSpace)
        let py = .gradientCoordinate(y, boundsMin.y, boundsSize.y, .drawing.height, gradient.userSpace)

        // A user-space stop is a point of the element's own coordinate system, so it goes
        // through the gradient's transform and then through the element's.
        if gradient.userSpace do
            return shape.paintTransform.transformPoint(gradient.transform.transformPoint({px, py}))

        // An object-bounding-box stop is a fraction of the shape's extent, and the gradient
        // transform applies in that unit square before it is stretched back over the bounds.
        let unit = gradient.transform.transformPoint({(px - boundsMin.x) / Math.max(boundsSize.x, 0.000001), (py - boundsMin.y) / Math.max(boundsSize.y, 0.000001)})
        return {boundsMin.x + unit.x * boundsSize.x, boundsMin.y + unit.y * boundsSize.y}
    }

    mtd gradientBrush(gradient: const *Gradient, shape: const *Shape)->Brush
    {
        if gradient.stops.isEmpty() do
            return Brush.createSolid(Color.fromArgb(Argb.Zero))

        let {min, max} = .shapeBounds(shape)
        let size       = max - min

        var result: retval
        result.color          = Color.fromArgb(Argb.White)
        result.gradientSpread = gradient.spread
        switch gradient.kind
        {
        case .Linear:
            result.type          = .LinearGradient
            result.gradientStart = .gradientPoint(gradient, shape, gradient.x1, gradient.y1, min, size)
            result.gradientEnd   = .gradientPoint(gradient, shape, gradient.x2, gradient.y2, min, size)

        case .Radial:
            result.type          = .RadialGradient
            result.gradientStart = .gradientPoint(gradient, shape, gradient.cx, gradient.cy, min, size)
            result.gradientEnd   = result.gradientStart

            if gradient.userSpace
            {
                let viewportDiagonal = Math.sqrt(.drawing.width * .drawing.width + .drawing.height * .drawing.height) / Math.ConstF32.Sqrt2
                let radius           = gradient.r.isPercent ? gradient.r.value * viewportDiagonal : gradient.r.value
                let inner            = gradient.fr.isPercent ? gradient.fr.value * viewportDiagonal : gradient.fr.value
                let radiusScale      = transformScale(gradient.transform) * transformScale(shape.paintTransform)
                result.gradientRadius0 = Math.max(inner * radiusScale, 0)
                result.gradientRadius1 = Math.max(radius * radiusScale, result.gradientRadius0)
            }
            else
            {
                let radiusScale = transformScale(gradient.transform)
                result.gradientRadius0 = Math.max(gradient.fr.value * size.x * radiusScale, 0)
                result.gradientRadius1 = Math.max(gradient.r.value * size.x * radiusScale, result.gradientRadius0)
            }
        }

        for stop in gradient.stops do
            result.addGradientStop(stop.offset, stop.color)
        return result
    }

    // Fills every gradient's unstated attributes from the chain of gradients it references.
    //
    // The chain is followed after the whole document is read, so a gradient may name one defined
    // further down, and it is bounded: a reference that loops back on itself stops contributing
    // instead of hanging, and a reference to nothing leaves the gradient with its own values.
    mtd resolveGradientInheritance()
    {
        const MaxInheritanceDepth = 16'u32

        var keys: Array'String
        for id, gradient in .gradients do
            keys.add(id)

        for id in keys
        {
            let entry = .gradients.tryFind(id.toString())
            if !entry do
                continue
            var resolved = entry.value

            var visited: Array'String
            visited.add(id)

            var current = resolved.href
            var depth   = 0'u32
            while !current.isEmpty() and depth < MaxInheritanceDepth
            {
                var seen = false
                for name in visited where name.toString() == current.toString() do
                    seen = true
                if seen do
                    break
                visited.add(current)

                let base = .gradients.tryFind(current.toString())
                if !base do
                    break

                let from = &base.value
                if !resolved.specified.x1
                {
                    resolved.x1           = from.x1
                    resolved.specified.x1 = from.specified.x1
                }

                if !resolved.specified.y1
                {
                    resolved.y1           = from.y1
                    resolved.specified.y1 = from.specified.y1
                }

                if !resolved.specified.x2
                {
                    resolved.x2           = from.x2
                    resolved.specified.x2 = from.specified.x2
                }

                if !resolved.specified.y2
                {
                    resolved.y2           = from.y2
                    resolved.specified.y2 = from.specified.y2
                }

                if !resolved.specified.cx
                {
                    resolved.cx           = from.cx
                    resolved.specified.cx = from.specified.cx
                }

                if !resolved.specified.cy
                {
                    resolved.cy           = from.cy
                    resolved.specified.cy = from.specified.cy
                }

                if !resolved.specified.r
                {
                    resolved.r           = from.r
                    resolved.specified.r = from.specified.r
                }

                if !resolved.specified.fx
                {
                    resolved.fx           = from.fx
                    resolved.specified.fx = from.specified.fx
                }

                if !resolved.specified.fy
                {
                    resolved.fy           = from.fy
                    resolved.specified.fy = from.specified.fy
                }

                if !resolved.specified.fr
                {
                    resolved.fr           = from.fr
                    resolved.specified.fr = from.specified.fr
                }

                if !resolved.specified.units
                {
                    resolved.userSpace       = from.userSpace
                    resolved.specified.units = from.specified.units
                }

                if !resolved.specified.spread
                {
                    resolved.spread           = from.spread
                    resolved.specified.spread = from.specified.spread
                }

                if !resolved.specified.transform
                {
                    resolved.transform           = from.transform
                    resolved.specified.transform = from.specified.transform
                }

                if !resolved.specified.stops and from.stops.count
                {
                    resolved.stops           = from.stops
                    resolved.specified.stops = true
                }

                current = from.href
                depth   += 1
            }

            .gradients.add(id, #move resolved)
        }
    }

    mtd resolvePaints()
    {
        for &shape in .drawing.shapes
        {
            if shape.hasFill
            {
                if shape.fillPaintId.isEmpty()
                {
                    shape.fillBrush = Brush.createSolid(shape.fillColor)
                }
                else
                {
                    let gradient = .gradients.tryFind(shape.fillPaintId)
                    if gradient
                    {
                        shape.pathList.flatten(.Normal)
                        shape.fillBrush = .gradientBrush(&gradient.value, shape)
                    }
                    elif .patterns.tryFind(shape.fillPaintId) do
                        shape.fillBrush = Brush.createSolid(Color.fromArgb(Argb.White))
                    else do
                        shape.hasFill = false
                }

                if shape.hasFill do
                    shape.fillBrush.multiplyOpacity(shape.fillOpacity)
            }

            if shape.hasStroke
            {
                if shape.strokePaintId.isEmpty()
                {
                    shape.strokeBrush = Brush.createSolid(shape.strokeColor)
                }
                else
                {
                    let gradient = .gradients.tryFind(shape.strokePaintId)
                    if gradient
                    {
                        shape.pathList.flatten(.Normal)
                        shape.strokeBrush = .gradientBrush(&gradient.value, shape)
                    }
                    else do
                        shape.hasStroke = false
                }

                if shape.hasStroke do
                    shape.strokeBrush.multiplyOpacity(shape.strokeOpacity)
            }
        }
    }

    // Appends transformed copies of a definition's shapes.
    // Appends transformed copies of a definition's shapes and reports the range they occupy.
    //
    // `state` carries the complete transform the copies are placed under, so a `use` offset, a
    // `symbol` viewport and a clip reference all reach here the same way. `hidden` withholds the
    // copies from the paint order, which is what a clip needs: its shapes exist as geometry and
    // are never drawn.
    mtd instantiate(first, count: u64, state: *GroupState, hidden = false)->{ first: u64, count: u64 }
    {
        var result: retval
        result.first = .drawing.shapes.count

        for i in count
        {
            // Build the transformed copy fully before appending: appending can
            // reallocate the array and invalidate the source borrow.
            var list:                        LinePathList
            var fillColor, strokeColor:      Color
            var fillPaintId, strokePaintId:  String
            var filterId:                    String
            var fillOpacity, strokeOpacity:  f32
            var hasFill, hasStroke, evenOdd: bool
            var strokeWidth, strokeOffset:   f32
            var strokeMiter:                 f32
            var strokePattern:               Array'f32
            var capStyle:                    LineCapStyle = None
            var joinStyle:                   JoinStyle    = Miter
            var paintTransform:              Math.Transform2

            {
                let src = &.drawing.shapes[first + i]
                fillColor     = src.fillColor
                strokeColor   = src.strokeColor
                fillPaintId   = src.fillPaintId
                strokePaintId = src.strokePaintId
                filterId      = src.filterId
                fillOpacity   = src.fillOpacity
                strokeOpacity = src.strokeOpacity
                hasFill       = src.hasFill
                hasStroke     = src.hasStroke
                evenOdd       = src.evenOdd
                let geometryScale = transformScale(state.transform)
                strokeWidth   = src.strokeWidth * geometryScale
                strokeOffset  = src.strokeOffset * geometryScale
                strokeMiter   = src.strokeMiter
                strokePattern = src.strokePattern
                for &value in strokePattern do
                    value[] *= geometryScale
                capStyle  = src.capStyle
                joinStyle = src.joinStyle

                // The definition's own paint space is composed under the instance's, with the
                // `use` offset between them.
                paintTransform = src.paintTransform
                paintTransform.multiply(state.transform)

                for srcPath in src.pathList.paths
                {
                    let path   = list.newPath()
                    let origin = mapPoint(state, srcPath.startPoint.x, srcPath.startPoint.y)
                    path.start(origin.x, origin.y)
                    for &element in srcPath.elements
                    {
                        switch element.type
                        {
                        case .Line:
                            let target = mapPoint(state, element.position.x, element.position.y)
                            path.lineTo(target.x, target.y)

                        case .Bezier1:
                            let target  = mapPoint(state, element.position.x, element.position.y)
                            let control = mapPoint(state, element.p1.x, element.p1.y)
                            path.bezierTo(target.x, target.y, control.x, control.y)

                        case .Bezier2:
                            let target   = mapPoint(state, element.position.x, element.position.y)
                            let control1 = mapPoint(state, element.p1.x, element.p1.y)
                            let control2 = mapPoint(state, element.p2.x, element.p2.y)
                            path.bezierTo(target.x, target.y, control1.x, control1.y, control2.x, control2.y)

                        case .Arc:

                            // An arc stores its center in `position`, its angle
                            // interval in `p1`, and its radii in `p2`.
                            appendArcElement(path, state, element.position, element.p1, element.p2)

                        default:
                            Debug.assert(false, "definition uses an unsupported segment type")
                        }
                    }

                    if srcPath.isClosed do
                        path.close()
                }
            }

            let shapeIndex = .drawing.shapes.count
            let shape      = .drawing.shapes.emplaceInitAddress()
            shape.pathList       = #move list
            shape.fillColor      = fillColor
            shape.fillPaintId    = #move fillPaintId
            shape.fillOpacity    = fillOpacity
            shape.strokeColor    = strokeColor
            shape.strokePaintId  = #move strokePaintId
            shape.strokeOpacity  = strokeOpacity
            shape.hasFill        = hasFill
            shape.hasStroke      = hasStroke
            shape.evenOdd        = evenOdd
            shape.strokeWidth    = strokeWidth
            shape.strokeOffset   = strokeOffset
            shape.strokeMiter    = strokeMiter
            shape.strokePattern  = #move strokePattern
            shape.capStyle       = capStyle
            shape.joinStyle      = joinStyle
            shape.paintTransform = paintTransform
            shape.hidden         = hidden or state.inDefs
            shape.filterId       = #move filterId
            if !shape.hidden do
                .drawing.items.add(DrawingItem{.Shape, shapeIndex})
        }

        result.count = .drawing.shapes.count - result.first
        return result
    }
}

// How far outside its geometry an antialiased edge lays its fringe, which a rectangle tested
// against a viewport is widened by so an item touching the edge is never rejected.
private const InkFringeMargin = 2.0'f32

internal impl Shape
{
    // Returns the rectangle this shape can ink, its contours plus whatever a stroke adds
    // around them.
    mtd const inkBounds()->Rectangle
    {
        var result: retval = .pathList.controlBounds()
        if .hasStroke
        {
            // Half the width lies either side of the contour, and a miter join reaches at
            // most the miter limit past a corner. A cap never reaches further than a join.
            let margin = Math.abs(.strokeWidth) * 0.5 * Math.max(.strokeMiter, 1.0'f32)
            result.inflate(margin)
        }

        return result
    }
}

impl Drawing
{
    // Returns the number of parsed shapes.
    mtd const shapeCount()->u64 => .shapes.count

    // Parses an SVG document authored in the supported subset.
    //
    // The result owns its shapes and decoded images. Text supports one-level `tspan`
    // runs with `x`, `y`, `dx`, `dy`, size, family class, anchor, weight, style, letter
    // and word spacing, solid fill, and opacity, and runs along the direction its element
    // is turned by. Images stretch into their declared rectangle. Patterns repeat vector
    // shape tiles in user or object-bounding-box units. Filters support either a
    // Gaussian blur followed by offsets, or a standalone `feDropShadow`.
    //
    // A `clip-path` is instantiated in the space of the element that names it, a `use`
    // fits a referenced `symbol`'s view box into the size it asks for, and markers are
    // placed on authored vertices with the tangent orientation `orient="auto"` states.
    // A reference to an identifier the document does not define leaves its element alone.
    //
    // `options` confines external image references and selects the typefaces for text;
    // see [[Pixel.Svg.ParseOptions]]. Unknown elements and attributes are ignored.
    func parse(text: string, options: ParseOptions = {})->Drawing fail
    {
        var result: retval

        var parser = Parser{text: text, drawing: &result, options: options}

        var root: GroupState
        try parser.parseContent(root)
        parser.resolveGradientInheritance()
        parser.resolvePaints()
        result.patterns = #move parser.patterns
        result.filters  = #move parser.filters

        if result.width <= 0 or result.height <= 0 do
            fail Swag.SystemError{"SVG document has no valid dimensions"}

        result.measureItems()
        return result
    }

    // Records what each item can ink, so painting can reject the ones a viewport misses.
    //
    // Shapes and pictures are bounded from the geometry the parser produced. A text block is
    // left unmeasured: its runs are placed by the advances of the runs before them, which only
    // shaping can give, so the first paint measures it and every later one rejects it.
    private mtd measureItems()
    {
        for &item in .items
        {
            switch item.kind
            {
            case .Shape:

                // A filter spreads ink past the shape that carries it — a blur by its radius,
                // an offset by its distance — so a filtered shape is never rejected.
                let shape  = &.shapes[item.index]
                let filter = .filters.tryFind(shape.filterId)
                if filter and filter.value.primitives.count do
                    break
                item.bounds    = shape.inkBounds()
                item.hasBounds = true

            case .Image:
                item.bounds    = .images[item.index].rect
                item.hasBounds = true

            case .Text:
                break
            }

            if item.hasBounds and item.clipCount do
                item.bounds.intersect(.clipRangeBounds(item.clipFirst, item.clipCount))
        }
    }

    // Returns the rectangle a clip range can keep, which is the union of its shapes.
    private mtd const clipRangeBounds(first, count: u64)->Rectangle
    {
        var result: retval
        for i in count
        {
            let bounds = .shapes[first + i].pathList.controlBounds()
            if !i do
                result = bounds
            else do
                result.expandToInclude(bounds)
        }

        return result
    }

    // Paints the drawing with its origin at `(x, y)` of the current path space,
    // its content multiplied by `scale`.
    //
    // Fills honor the winding of their contours (a counter-clockwise contour is a
    // hole), strokes honor width, caps, and joins scaled by `scale`.
    mtd const paint(painter: *Painter, x, y: f32, scale = 1.0'f32)
    {
        // Contours are flattened in drawing units, so a magnified drawing needs the scale to
        // reach the tolerance or its curves show their segments. Shown smaller than its own
        // units the same statement runs the other way: a document poster-sized next to the
        // window it is fitted into holds far more contour points than the window has pixels,
        // and the stroker is told so here rather than walking all of them. The painter buckets
        // the value, so a viewer that zooms continuously re-keys only on doublings.
        //
        // [[Pixel.Svg.Drawing.rasterize]] deliberately declares nothing. A contour keeps the
        // finest flattening anything ever asked it for, so a drawing rasterized at several sizes
        // would carry the tolerance of whichever size came first, and a cached sheet — a theme's
        // icon atlas — would depend on the order its sizes were first requested.
        let previousFlattenScale = painter.flattenScale()
        defer painter.setFlattenScale(previousFlattenScale)
        painter.setFlattenScale(Math.max(scale * painter.contentScale(), 1.0'f32 / 64))

        .paintImpl(painter, x, y, scale, false)
    }

    private mtd const paintShapeCore(painter: *Painter, shape: *Shape, compensateAlpha: bool, paintFill = true)
    {
        if paintFill and shape.hasFill
        {
            var brush = shape.fillBrush
            if compensateAlpha
            {
                brush.color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) brush.color.a / 255.0))
                for &stop in brush.gradientStops do
                    stop.color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) stop.color.a / 255.0))
            }

            painter.fillPath(&shape.pathList, brush)
        }

        if shape.hasStroke
        {
            var brush = shape.strokeBrush
            if compensateAlpha
            {
                brush.color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) brush.color.a / 255.0))
                for &stop in brush.gradientStops do
                    stop.color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) stop.color.a / 255.0))
            }

            var pen: Pen
            pen.brush          = #move brush
            pen.size           = shape.strokeWidth
            pen.begCapStyle    = shape.capStyle
            pen.endCapStyle    = shape.capStyle
            pen.joinStyle      = shape.joinStyle
            pen.joinMiterLimit = shape.strokeMiter
            pen.dashOffset     = shape.strokeOffset
            if shape.strokePattern.count
            {
                pen.pattern = shape.strokePattern
                if Math.abs(shape.strokeWidth) > 0.000001
                {
                    for &value in pen.pattern do
                        value[] /= Math.abs(shape.strokeWidth)
                }

                pen.dashStyle = .Pattern
            }

            painter.drawPath(&shape.pathList, pen, .Separate)
        }
    }

    private mtd const paintPattern(painter: *Painter, shape: *Shape, pattern: const *Pattern, compensateAlpha: bool)
    {
        shape.pathList.flatten(.Normal)
        var min = Vector2.Max
        var max = Vector2.NegMax
        for path in shape.pathList.paths
        {
            min = Vector2.min(min, path.minBounds)
            max = Vector2.max(max, path.maxBounds)
        }

        let size       = max - min
        let tileX      = pattern.userSpace ? pattern.x.value : min.x + pattern.x.value * size.x
        let tileY      = pattern.userSpace ? pattern.y.value : min.y + pattern.y.value * size.y
        let tileWidth  = pattern.userSpace ? pattern.width.value : pattern.width.value * size.x
        let tileHeight = pattern.userSpace ? pattern.height.value : pattern.height.value * size.y
        if tileWidth <= 0 or tileHeight <= 0 do
            return

        let rasterScale         = Math.max(painter.contentScale(), 1.0'f32)
        let pixelWidth          = cast(s32) Math.max(Math.ceil(tileWidth * rasterScale), 1.0'f32)
        let pixelHeight         = cast(s32) Math.max(Math.ceil(tileHeight * rasterScale), 1.0'f32)
        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        cpu.begin(pixelWidth, pixelHeight)
        var target      = renderer.createRenderTarget(pixelWidth, pixelHeight)
        var tilePainter = Painter.create(renderer)
        tilePainter.begin()
        tilePainter.bindRenderTarget(&target, paintAlpha: false)
        tilePainter.setColorMaskFull()
        tilePainter.clear(Color.fromArgb(Argb.Zero))
        let phaseX = min.x - tileX - Math.floor((min.x - tileX) / tileWidth) * tileWidth
        let phaseY = min.y - tileY - Math.floor((min.y - tileY) / tileHeight) * tileHeight
        for copyY in 3
        {
            for copyX in 3
            {
                let offsetX       = cast(f32) (cast(s32) copyX - 1) * tileWidth
                let offsetY       = cast(f32) (cast(s32) copyY - 1) * tileHeight
                var tileTransform = Math.Transform2.createTranslation(-tileX - phaseX + offsetX, -tileY - phaseY + offsetY)
                tileTransform.multiply(Math.Transform2.createScale(rasterScale, rasterScale, 0, 0))
                tilePainter.setTransform(tileTransform)
                for i in pattern.count do
                    .paintShapeCore(&tilePainter, &.shapes[pattern.first + i], false)
            }
        }

        tilePainter.unbindRenderTarget()
        tilePainter.end()
        renderer.draw(&tilePainter)

        let tileImage = renderer.readRenderTarget(&target, 0, 0, pixelWidth, pixelHeight)
        renderer.deleteRenderTarget(&target)
        renderer.end()

        let texture = painter.renderer().addImage(tileImage)
        var brush   = Brush.createTiled(texture)
        if compensateAlpha do
            brush.color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) brush.color.a / 255.0))
        painter.fillPath(&shape.pathList, brush)
        painter.releaseTexture(texture)
    }

    // Paints one text block and returns the drawing-space rectangle its runs covered.
    private mtd const paintText(painter: *Painter, text: const *SvgText, compensateAlpha: bool)->Rectangle
    {
        // The pen is a point plus a distance along the baseline, because a rotated element
        // runs its text along a direction rather than along the drawing's x axis. With no
        // rotation the direction is the x axis and this is the ordinary running position.
        var origin:  Vector2
        var advance: f32

        var inked:    retval
        var hasInked: bool

        for run in text.runs
        {
            if run.hasX
            {
                origin.x = run.x
                advance  = 0
            }

            if run.hasY do
                origin.y = run.y
            origin.x += run.dx
            origin.y += run.dy

            let size = cast(u32) Math.max(Math.round(run.fontSize), 1.0'f32)
            let font = painter.renderer().fontCache().createFont(run.typeFace, size, forceBold: run.forceBold, forceItalic: run.forceItalic)

            // Shape once: the anchor needs the advance the spacing produces, and drawing
            // the same run keeps the glyphs on the positions that width was measured from.
            var shaped  = Painter.shapeRun(run.text.toString(), font, letterSpacing: run.letterSpacing, wordSpacing: run.wordSpacing)
            let metrics = Painter.measureString(&shaped)
            var offset  = advance
            if run.anchor == .Middle do
                offset -= metrics.width * 0.5
            elif run.anchor == .End do
                offset -= metrics.width

            var color = run.color.withAlphaF32(run.opacity)
            if compensateAlpha do
                color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) color.a / 255.0))

            // The run is drawn from `font.ascent` above the baseline; its glyphs can reach a
            // little past the recommended extents either way, so the box takes the larger of
            // the two and a margin of its own.
            let above   = Math.max(font.ascent, metrics.ascent)
            let below   = Math.max(font.descent, metrics.descent)
            let rotated = Math.abs(run.rotation) > 0.0001
            var runBox  = Rectangle{origin.x + offset, origin.y - above, metrics.width, above + below}
            runBox.inflate(run.fontSize * 0.5)
            if rotated
            {
                // Turning the painter around the baseline origin puts the run on the direction
                // its element states, and leaves glyph shaping in its own upright space.
                painter.pushState()
                var tr = Math.Transform2.createRotation(run.rotation, origin.x, origin.y)
                runBox = tr.transformBounds(runBox)
                tr.multiply(painter.transform())
                painter.setTransform(tr)
            }

            if !hasInked
            {
                inked    = runBox
                hasInked = true
            }
            else do
                inked.expandToInclude(runBox)

            painter.drawShapedRun(origin.x + offset, origin.y - font.ascent, &shaped, font, Brush.createSolid(color))
            if rotated do
                painter.popState()
            advance += metrics.width
        }

        return inked
    }

    private mtd const paintImage(painter: *Painter, image: const *SvgImage, compensateAlpha: bool)
    {
        var alpha = image.opacity
        if compensateAlpha do
            alpha = Math.sqrt(alpha)
        let texture = painter.renderer().addImage(image.image)
        painter.drawTexture(image.rect, texture, Color.fromArgb(Argb.White).withAlphaF32(alpha))
        painter.releaseTexture(texture)
    }

    private mtd const paintFilteredShape(painter: *Painter, shape: *Shape, filter: const *SvgFilter, x, y, scale: f32, outerTransform, drawingTransform: Transform2, compensateAlpha: bool)
    {
        var layer: Layer
        var begin: LayerBeginInfo
        begin.width      = cast(s32) Math.ceil(.width * scale)
        begin.height     = cast(s32) Math.ceil(.height * scale)
        begin.paintAlpha = false

        painter.setTransform(Math.Transform2.createScale(scale, scale, 0, 0))
        layer.begin(painter, begin)
        painter.setColorMaskFull()
        let pattern = .patterns.tryFind(shape.fillPaintId)
        if pattern
        {
            .paintPattern(painter, shape, &pattern.value, compensateAlpha)
            .paintShapeCore(painter, shape, compensateAlpha, false)
        }
        else do
            .paintShapeCore(painter, shape, compensateAlpha)
        layer.end()

        var offsetX, offsetY: f32
        var shadow:           LayerShadowInfo
        for primitive in filter.primitives
        {
            switch primitive.kind
            {
            case .GaussianBlur:
                layer.applyBlur(primitive.radius * scale)

            case .Offset:
                offsetX += primitive.x * scale
                offsetY += primitive.y * scale

            case .DropShadow:
                shadow.enabled = true
                shadow.radius  = primitive.radius * scale
                shadow.offsetX = primitive.x * scale
                shadow.offsetY = primitive.y * scale
                shadow.color   = primitive.color
            }
        }

        painter.setTransform(outerTransform)
        var draw: LayerDrawInfo
        draw.dstRect = {x + offsetX, y + offsetY, .width * scale, .height * scale}
        draw.shadow  = shadow
        layer.draw(draw)
        painter.setTransform(drawingTransform)
    }

    // The alpha-preserving resolve of a `paintAlpha` render target squares fragment
    // alpha (GL_MAX with a source-alpha factor; the CPU renderer matches it). Painting
    // with square-rooted shape alphas makes that resolve land back on the authored
    // values; with supersampling, per-sample coverage is essentially binary, so the
    // compensation is exact in practice.
    internal mtd const paintImpl(painter: *Painter, x, y: f32, scale: f32, compensateAlpha: bool)
    {
        painter.pushState()
        defer painter.popState()

        // Local drawing space: scale then translate, applied before the current transform.
        let outerTransform = painter.transform()
        var tr             = Math.Transform2.createScale(scale, scale, 0, 0)
        tr.multiply(Math.Transform2.createTranslation(x, y))
        tr.multiply(outerTransform)
        painter.setTransform(tr)

        // The clipping region persists across draws, so the one in force is tracked and only
        // exchanged when it changes: the outgoing clip is taken back out with a `Clear` pass
        // before the incoming one is put in. Consecutive items of one clipped group therefore
        // stamp their clip once.
        var activeFirst, activeCount: u64

        // What the painter can still reach, in surface space. An item landing outside it is
        // not drawn, and does not stamp its clip either: a document is normally much larger
        // than the window showing it, and a rejected item costs a rectangle test instead of
        // all of its geometry.
        let visible = painter.clippingRect()

        for &item in .items
        {
            if item.hasBounds
            {
                var painted = tr.transformBounds(item.bounds)
                painted.inflate(InkFringeMargin)
                if !visible.intersects(painted) do
                    continue
            }

            if item.clipFirst != activeFirst or item.clipCount != activeCount
            {
                .exchangeClip(painter, activeFirst, activeCount, item.clipFirst, item.clipCount)
                activeFirst = item.clipFirst
                activeCount = item.clipCount
            }

            switch item.kind
            {
            case .Shape:
                let shape  = &.shapes[item.index]
                let filter = .filters.tryFind(shape.filterId)
                if filter and filter.value.primitives.count
                {
                    .paintFilteredShape(painter, shape, &filter.value, x, y, scale, outerTransform, tr, compensateAlpha)
                    continue
                }

                let pattern = .patterns.tryFind(shape.fillPaintId)
                if pattern
                {
                    .paintPattern(painter, shape, &pattern.value, compensateAlpha)
                    .paintShapeCore(painter, shape, compensateAlpha, false)
                }
                else do
                    .paintShapeCore(painter, shape, compensateAlpha)

            case .Text:
                let inked = .paintText(painter, &.texts[item.index], compensateAlpha)

                // Where the runs landed is what the block covers, and it is the same at every
                // scale because a run is shaped in its own upright space.
                if !item.hasBounds
                {
                    item.bounds = inked
                    if item.clipCount do
                        item.bounds.intersect(.clipRangeBounds(item.clipFirst, item.clipCount))
                    item.hasBounds = true
                }

            case .Image:
                .paintImage(painter, &.images[item.index], compensateAlpha)
            }
        }

        .exchangeClip(painter, activeFirst, activeCount, 0, 0)
    }

    // Replaces the clip in force by another, leaving the region empty for an empty incoming one.
    //
    // A region persists until coverage is taken back out of it, so the outgoing clip is drawn
    // again in `Clear` mode rather than assumed gone.
    private mtd const exchangeClip(painter: *Painter, outFirst, outCount, inFirst, inCount: u64)
    {
        let white = Brush.createSolid(Color.fromArgb(Argb.White))
        if outCount
        {
            painter.startClippingRegion(.Clear)
            for i in outCount do
                painter.fillPath(&.shapes[outFirst + i].pathList, white)
            painter.endClippingRegion()
        }

        if inCount == 0
        {
            painter.resetClippingRegion()
            return
        }

        painter.startClippingRegion(.Set)
        for i in inCount do
            painter.fillPath(&.shapes[inFirst + i].pathList, white)
        painter.endClippingRegion()
    }

    // Rasterizes the drawing into an owned image of exactly `width` by `height` pixels.
    //
    // The drawing is scaled uniformly from its view box to `width`, antialiased, on
    // a transparent ground. Rasterization is done in software: no window, no GPU.
    //
    // `supersample` renders that many samples per axis and box-filters them down,
    // replacing the renderer's screen-space edge feather with near-exact coverage.
    // The default doubles sampling, a good balance for icon and atlas work.
    //
    // An application that already owns a renderer should pass it to the overload
    // below instead: filling the supersampled buffer is the whole cost here, and a
    // GPU backend does it in a fraction of the time.
    mtd const rasterize(width, height: s32, supersample: u8 = 2)->Image
    {
        Debug.assert(width > 0 and height > 0)

        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        cpu.begin(width, height)
        var result = .rasterize(renderer, width, height, supersample)
        renderer.end()
        return result
    }

    // Rasterizes the drawing through `renderer` into an owned image of exactly
    // `width` by `height` pixels.
    //
    // The result is identical whichever backend produces it, up to the raster-edge
    // tolerance the two backends already carry elsewhere. Supersampled work is split
    // into aligned tiles, so the renderer never retains a target larger than 1024 by
    // 1024 samples; only the finished image crosses back to the caller.
    //
    // The renderer must be ready to draw — its context selected and [[Pixel.IRenderer.init]]
    // called — because this records a complete painter submission and executes it.
    mtd const rasterize(renderer: IRenderer, width, height: s32, supersample: u8 = 2)->Image
    {
        Debug.assert(width > 0 and height > 0)
        return .rasterizeWithSampleTileSide(renderer, width, height, supersample, RasterSampleTileSide)
    }

    // Reports whether any painted shape is stroked.
    private mtd const hasStrokedShape()->bool
    {
        for item in .items where item.kind == .Shape and .shapes[item.index].hasStroke do
            return true
        return false
    }

    // Rasterizes with an explicit sampled-tile bound for module tests.
    internal mtd const rasterizeWithSampleTileSide(renderer: IRenderer, width, height: s32, supersample: u8, sampleTileSide: s32)->Image
    {
        Debug.assert(width > 0 and height > 0)
        Debug.assert(sampleTileSide > 0)

        let ss            = cast(s32) Math.max(supersample, 1'u8)
        let tileWidth     = Math.min(width, Math.max(sampleTileSide / ss, 1))
        let tileHeight    = Math.min(height, Math.max(sampleTileSide / ss, 1))
        let sampledWidth  = tileWidth * ss
        let sampledHeight = tileHeight * ss

        // Whether the content writes its own alpha, or the target rebuilds it by replaying the
        // recording.
        //
        // Text, pictures, patterns and filters carry an alpha the replay cannot reproduce
        // exactly: glyph coverage and sampled texels are not the near-binary sample coverage the
        // resolve assumes. A drawing made of those writes its alpha directly.
        //
        // A stroke takes that choice away. The overlap-safe pass an antialiased stroke goes
        // through uses the destination alpha as its own scratch plane and clears it across the
        // target, so one stroke anywhere leaves a directly written alpha empty and the whole
        // drawing rasterizes to nothing. Such a drawing is rebuilt by the replay instead:
        // slightly soft alpha beats no alpha at all.
        let directAlpha = (.texts.count or .images.count or .patterns.count or .filters.count) and !.hasStrokedShape()
        var result      = Image.create(width, height, .BGRA8)

        // Targets are created at the exact size instead of acquired from the pool, which
        // rounds up to a power of two: the resolve reads the sampled target as a whole,
        // and padding would land inside the box filter. Every tile reuses these same two
        // target sizes, including a partial tile at the right or bottom edge.
        var sampled = renderer.createRenderTarget(sampledWidth, sampledHeight)
        var resolved: RenderTarget
        if ss > 1 do
            resolved = renderer.createRenderTarget(tileWidth, tileHeight)

        var tileY = 0
        while tileY < height
        {
            let copyHeight = Math.min(tileHeight, height - tileY)
            var tileX      = 0
            while tileX < width
            {
                let copyWidth = Math.min(tileWidth, width - tileX)

                // Antialiased and translucent shapes go through the overlap-safe pass, which
                // sacrifices the destination alpha channel; render into a target with the
                // alpha-preserving replay so the result carries a correct alpha mask.
                var painter = Painter.create(renderer)
                painter.begin()
                painter.bindRenderTarget(&sampled, paintAlpha: !directAlpha)
                painter.setColorMaskFull()
                painter.clear(Color.fromArgb(Argb.Zero))
                if !directAlpha do
                    painter.setColorMaskColor()
                .paintImpl(&painter, cast(f32) (-tileX * ss), cast(f32) (-tileY * ss), cast(f32) (width * ss) / .width, !directAlpha)
                painter.unbindRenderTarget()

                // Box-filter the samples down with the renderer's own resolve program, the one
                // the layer pipeline already uses. Unbinding above has resolved the alpha plane,
                // so the sampled target is a plain texture by the time it is read here.
                if ss > 1
                {
                    let dstRect = Math.Rectangle{0, 0, cast(f32) tileWidth, cast(f32) tileHeight}
                    let srcRect = Math.Rectangle{0, 0, cast(f32) sampledWidth, cast(f32) sampledHeight}
                    painter.bindRenderTarget(&resolved)
                    painter.setResolveShader(ss)
                    painter.setColorMaskFull()
                    painter.setBlendingMode(.Copy)
                    painter.clear(Color.fromArgb(Argb.Zero))
                    painter.drawTexture(dstRect, srcRect, sampled.colorBuffer)
                    painter.setDefaultShader()
                    painter.unbindRenderTarget()
                }

                painter.end()
                renderer.draw(&painter)

                // Render-target readbacks and images share the bottom-up row convention. Copy
                // each tile into the matching bottom-up rows of the complete result.
                let tile = ss == 1 ? renderer.readRenderTarget(&sampled, 0, 0, copyWidth, copyHeight) : renderer.readRenderTarget(&resolved, 0, 0, copyWidth, copyHeight)
                for row in copyHeight
                {
                    let source      = tile.pixels.buffer! + cast(u64) row * cast(u64) tile.rowStride
                    let resultRow   = result.height - tileY - copyHeight + row
                    let destination = result.pixels.buffer! + cast(u64) resultRow * cast(u64) result.rowStride + cast(u64) tileX * result.bytesPerPixel
                    Memory.copy(destination, source, cast(u64) copyWidth * result.bytesPerPixel)
                }

                tileX += tileWidth
            }

            tileY += tileHeight
        }

        if ss > 1 do
            renderer.deleteRenderTarget(&resolved)
        renderer.deleteRenderTarget(&sampled)

        // The resolve leaves a fully transparent pixel black; make it white instead, so a
        // consumer that tints the result, or a sampler that interpolates across the edge
        // of a shape, never blends a dark fringe in.
        if ss > 1 do
            result.setTransparentColor(Color.fromArgb(Argb.White))
        return result
    }
}

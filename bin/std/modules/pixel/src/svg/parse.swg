#global public
#global namespace Svg

using Core, Core.Math

// Controls resources that SVG parsing may resolve outside the document text.
//
// Data-image URIs are accepted up to `maxImageBytes`. A non-empty
// `externalResourceRoot` additionally permits relative raster-image references whose
// canonical path remains inside that directory; absolute paths and escaping `..`
// references are rejected. `fontFileName` selects the typeface used by `text` and
// `tspan`; it may be a file path or a filename from the system font directory.
struct ParseOptions
{
    public
    {
        externalResourceRoot: string = ""                   // Canonical containment root for relative image references; empty disables them.
        fontFileName:         string = "segoeui.ttf"        // Typeface file or installed-font filename used by SVG text.
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

        paintTx, paintTy: f32         // Element transform retained for user-space paint servers.
        paintSx, paintSy: f32 = 1     // Element scale retained for user-space paint servers.

        filterId: String     // Referenced filter definition, if any.
    }
}

// A parsed vector document, ready to paint at any scale.
//
// [[Pixel.Svg.Drawing.parse]] reads the SVG subset used by standalone artwork and the
// standard themes: basic shapes and paths, groups, definitions and uses, linear and
// centered radial gradients, repeating patterns, text runs, bounded raster images,
// a Gaussian blur followed by offsets or a standalone drop shadow, CSS Color 3
// solid paints, opacity,
// path-length-calibrated stroke dashes, `translate`/`scale` transforms, and simple
// element/class/id style rules. Clipping, masks, markers, rotations, arbitrary font
// fallback, and the remaining SVG filter primitives are out of contract. Because vector
// geometry is not rasterized at parse time, the same drawing renders sharply at any size.
struct Drawing
{
    public
    {
        width:  f32     // View-box width, in user units.
        height: f32     // View-box height, in user units.

        internal
        shapes:   Array'Shape                       // Parsed vector shapes, including hidden definitions.
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
}

private enum TextAnchor
{
    Start
    Middle
    End
}

private struct SvgTextRun
{
    text:        String
    typeFace:    *TypeFace = undefined
    x, y:        f32
    dx, dy:      f32
    fontSize:    f32
    color:       Color
    opacity:     f32       = 1
    anchor:      TextAnchor
    forceBold:   bool
    forceItalic: bool
    hasX, hasY:  bool
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
    tx, ty: f32         // Accumulated translation, in drawing units.
    sx, sy: f32 = 1     // Accumulated scale.

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

    currentColor: Color = Color.fromArgb(Argb.Black)     // Inherited `currentColor` value.
    isDisplayed:  bool  = true                           // Whether an ancestor selected `display:none`.
    isVisible:    bool  = true                           // Inherited visibility state.

    opacity: f32 = 1     // Accumulated group opacity.
    inDefs:  bool        // Whether the element sits inside a `defs` scope.

    fontSize:    f32 = 16
    textAnchor:  TextAnchor
    forceBold:   bool
    forceItalic: bool
    filterId:    String
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
    gradients: HashTable'(String, Gradient)
    patterns:  HashTable'(String, Pattern)
    filters:   HashTable'(String, SvgFilter)
    styles:    Array'StyleRule
    options:   ParseOptions
    typeFace:  #null *TypeFace
    svgDepth:  u32
    inDefs:    bool     // Whether parsing currently sits inside a `defs` element.
}

private struct StyleRule
{
    selector:     String
    declarations: String
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

private struct Gradient
{
    kind: GradientKind = Linear

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
    spread:    GradientSpread = Clamp
    tx, ty:    f32
    sx, sy:    f32            = 1
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
    let len = @countof(s)
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

    if i < len and (s[i] == 'e' or s[i] == 'E')
    {
        i += 1
        if i < len and (s[i] == '-' or s[i] == '+') do
            i += 1
        while i < len and s[i] >= '0' and s[i] <= '9' do
            i += 1
    }

    pos[] = i
    if i == start do
        return 0
    return catch StrConv.toF32(cast(string) @mkslice(@dataof(s) + start, i - start))
}

private func parseLength(value: string, defaultValue: SvgLength = {})->SvgLength
{
    var pos = 0'u64
    while pos < @countof(value) and (value[pos] == ' ' or value[pos] == '\t' or value[pos] == '\n' or value[pos] == '\r') do
        pos += 1
    if pos >= @countof(value) or !isNumberStart(value[pos]) do
        return defaultValue

    var result: retval
    result.value = scanNumber(value, &pos)
    while pos < @countof(value) and value[pos] == ' ' do
        pos += 1
    if pos < @countof(value) and value[pos] == '%'
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
    if @countof(trimmed) < 7 or Latin1.compare(cast(string) @mkslice(@dataof(trimmed), 5), "url(#", ignoreCase: true) do
        return result

    var end = 5'u64
    while end < @countof(trimmed) and trimmed[end] != ')' do
        end += 1
    if end > 5 do
        result = cast(string) @mkslice(@dataof(trimmed) + 5, end - 5)
    return result
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
    if pos[] < @countof(value) and value[pos[]] == '%'
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

    let len = @countof(text)
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

    let isRgb  = len > 4 and !Latin1.compare(cast(string) @mkslice(@dataof(text), 4), "rgb(", ignoreCase: true)
    let isRgba = len > 5 and !Latin1.compare(cast(string) @mkslice(@dataof(text), 5), "rgba(", ignoreCase: true)
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

    let isHsl  = len > 4 and !Latin1.compare(cast(string) @mkslice(@dataof(text), 4), "hsl(", ignoreCase: true)
    let isHsla = len > 5 and !Latin1.compare(cast(string) @mkslice(@dataof(text), 5), "hsla(", ignoreCase: true)
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
    while pos < @countof(text)
    {
        while pos < @countof(text) and (text[pos] == ' ' or text[pos] == ',' or text[pos] == '\t' or text[pos] == '\n' or text[pos] == '\r') do
            pos += 1
        if pos >= @countof(text) or !isNumberStart(text[pos]) do
            break

        var length = SvgLength{value: scanNumber(text, &pos)}
        if pos < @countof(text) and text[pos] == '%'
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

    case "font-size":
        state.fontSize = Math.max(parseLength(value, {state.fontSize, false}).value, 1)

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
        var pos = 0'u64
        let len = @countof(value)
        while pos < len
        {
            while pos < len and (value[pos] == ' ' or value[pos] == ',') do
                pos += 1
            if pos + 9 < len and cast(string) @mkslice(@dataof(value) + pos, 9) == "translate"
            {
                pos += 9
                while pos < len and value[pos] != '(' do
                    pos += 1
                pos += 1
                let x    = scanNumber(value, &pos)
                var y    = 0'f32
                var look = pos
                while look < len and (value[look] == ' ' or value[look] == ',') do
                    look += 1
                if look < len and isNumberStart(value[look]) do
                    y = scanNumber(value, &pos)
                state.tx += x * state.sx
                state.ty += y * state.sy
                while pos < len and value[pos] != ')' do
                    pos += 1
                pos += 1
            }
            elif pos + 5 < len and cast(string) @mkslice(@dataof(value) + pos, 5) == "scale"
            {
                pos += 5
                while pos < len and value[pos] != '(' do
                    pos += 1
                pos += 1
                let x    = scanNumber(value, &pos)
                var y    = x
                var look = pos
                while look < len and (value[look] == ' ' or value[look] == ',') do
                    look += 1
                if look < len and isNumberStart(value[look]) do
                    y = scanNumber(value, &pos)
                state.sx *= x
                state.sy *= y
                while pos < len and value[pos] != ')' do
                    pos += 1
                pos += 1
            }
            else do
                break
        }
    }
}

private func applyAttribute(state: *GroupState, name, value: string)
{
    if name == "style"
    {
        // Inline declarations: name:value pairs separated by ';'.
        var scan = value
        while @countof(scan)
        {
            var stop = 0'u64
            while stop < @countof(scan) and scan[stop] != ';' do
                stop += 1
            let decl = @mkslice(@dataof(scan), stop)

            var sep = 0'u64
            while sep < @countof(decl) and decl[sep] != ':' do
                sep += 1
            if sep < @countof(decl)
            {
                var n = cast(string) @mkslice(@dataof(decl), sep)
                var v = cast(string) @mkslice(@dataof(decl) + sep + 1, @countof(decl) - sep - 1)
                n = Latin1.trim(n)
                v = Latin1.trim(v)
                applyStyleProperty(state, n, v)
            }

            if stop == @countof(scan) do
                break
            scan = cast(string) @mkslice(@dataof(scan) + stop + 1, @countof(scan) - stop - 1)
        }

        return
    }

    applyStyleProperty(state, name, value)
}

private func styleValue(style, property: string)->String
{
    var result: retval
    var scan = style
    while @countof(scan)
    {
        var stop = 0'u64
        while stop < @countof(scan) and scan[stop] != ';' do
            stop += 1
        let declaration = @mkslice(@dataof(scan), stop)

        var sep = 0'u64
        while sep < @countof(declaration) and declaration[sep] != ':' do
            sep += 1
        if sep < @countof(declaration)
        {
            let name = Latin1.trim(cast(string) @mkslice(@dataof(declaration), sep))
            if !Latin1.compare(name, property, ignoreCase: true)
            {
                result = Latin1.trim(cast(string) @mkslice(@dataof(declaration) + sep + 1, @countof(declaration) - sep - 1))
                return result
            }
        }

        if stop == @countof(scan) do
            break
        scan = cast(string) @mkslice(@dataof(scan) + stop + 1, @countof(scan) - stop - 1)
    }

    return result
}

// Geometry /////////////////////////////////////////////////////////////////////

#[Swag.Inline]
private func mapX(state: *GroupState, x: f32) => x * state.sx + state.tx

#[Swag.Inline]
private func mapY(state: *GroupState, y: f32) => y * state.sy + state.ty

// Appends one endpoint-parameterized elliptical arc as cubic Béziers.
//
// `rotation` is out of contract and ignored; the themes never use it.
private func appendArc(path: *LinePath, x0, y0: f32, rxIn, ryIn: f32, largeArc, sweep: bool, x1, y1: f32)
{
    var rx = Math.abs(rxIn)
    var ry = Math.abs(ryIn)
    if rx <= 0.000001 or ry <= 0.000001 or (x0 == x1 and y0 == y1)
    {
        path.lineTo(x1, y1)
        return
    }

    // Endpoint to center parameterization (SVG specification appendix).
    let dx = (x0 - x1) * 0.5
    let dy = (y0 - y1) * 0.5

    var lambda = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
    if lambda > 1
    {
        lambda = Math.sqrt(lambda)
        rx     *= lambda
        ry     *= lambda
    }

    let rx2 = rx * rx
    let ry2 = ry * ry
    var num = rx2 * ry2 - rx2 * dy * dy - ry2 * dx * dx
    if num < 0 do
        num = 0
    let den  = rx2 * dy * dy + ry2 * dx * dx
    var coef = Math.sqrt(num / Math.max(den, 0.000001))
    if largeArc == sweep do
        coef = -coef

    let cx = coef * rx * dy / ry + (x0 + x1) * 0.5
    let cy = -coef * ry * dx / rx + (y0 + y1) * 0.5

    let startAngle = Math.atan2((y0 - cy) / ry, (x0 - cx) / rx)
    let endAngle   = Math.atan2((y1 - cy) / ry, (x1 - cx) / rx)

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
        let p0x = cx + rx * Math.cos(a0)
        let p0y = cy + ry * Math.sin(a0)
        let p1x = cx + rx * Math.cos(a1)
        let p1y = cy + ry * Math.sin(a1)
        let c0x = p0x - k * rx * Math.sin(a0)
        let c0y = p0y + k * ry * Math.cos(a0)
        let c1x = p1x + k * rx * Math.sin(a1)
        let c1y = p1y - k * ry * Math.cos(a1)
        path.bezierTo(p1x, p1y, c0x, c0y, c1x, c1y)
        angle = a1
    }
}

// Parses one `d` attribute into subpath contours, transformed by `state`.
private func parsePathData(list: *LinePathList, data: string, state: *GroupState)
{
    let len = @countof(data)
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
        while look < @countof(data) and (data[look] == ' ' or data[look] == ',' or data[look] == '\t' or data[look] == '\n' or data[look] == '\r') do
            look += 1
        if look >= @countof(data) or !isNumberStart(data[look])
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

        while pos[] < @countof(data) and (data[pos[]] == ' ' or data[pos[]] == ',' or data[pos[]] == '\t' or data[pos[]] == '\n' or data[pos[]] == '\r') do
            pos[] += 1
        if pos[] >= @countof(data) or (data[pos[]] != '0' and data[pos[]] != '1')
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

            path = list.newPath()
            path.start(mapX(state, x), mapY(state, y))
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
            if Math.abs(x - curX) > 0.0005 or Math.abs(y - curY) > 0.0005 do
                path!.lineTo(mapX(state, x), mapY(state, y))
            curX = x
            curY = y

        case 'H', 'h':
            var x = number(data, &pos, &valid)
            if !valid do
                return
            if rel do
                x += curX
            path!.lineTo(mapX(state, x), mapY(state, curY))
            curX = x

        case 'V', 'v':
            var y = number(data, &pos, &valid)
            if !valid do
                return
            if rel do
                y += curY
            path!.lineTo(mapX(state, curX), mapY(state, y))
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

            path!.bezierTo(mapX(state, x), mapY(state, y), mapX(state, c1x), mapY(state, c1y), mapX(state, c2x), mapY(state, c2y))
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

            path!.bezierTo(mapX(state, x), mapY(state, y), mapX(state, c1x), mapY(state, c1y))
            ctlX      = c1x
            ctlY      = c1y
            curX      = x
            curY      = y
            lastCurve = 'q'
            continue

        case 'A', 'a':
            let rx = number(data, &pos, &valid)
            let ry = number(data, &pos, &valid)
            discard number(data, &pos, &valid)     // x-axis rotation, out of contract
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

            appendArc(path!, mapX(state, curX), mapY(state, curY), rx * state.sx, ry * state.sy, largeArc, sweepF, mapX(state, x), mapY(state, y))
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
        shape.strokeWidth   = state.strokeWidth * state.sx
        let viewportDiagonal = Math.sqrt(drawing.width * drawing.width + drawing.height * drawing.height) / Math.ConstF32.Sqrt2
        shape.strokeOffset = (state.strokeOffset.isPercent ? state.strokeOffset.value * viewportDiagonal : state.strokeOffset.value) * state.sx
        shape.strokeMiter  = state.strokeMiter
        for value in state.strokePattern
        {
            let length = value.isPercent ? value.value * viewportDiagonal : value.value
            shape.strokePattern.add(length * state.sx)
        }

        shape.capStyle  = state.capStyle
        shape.joinStyle = state.joinStyle
    }

    shape.paintTx  = state.tx
    shape.paintTy  = state.ty
    shape.paintSx  = state.sx
    shape.paintSy  = state.sy
    shape.filterId = state.filterId

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
        path.setEllipseRaw(mapX(state, x + w * 0.5), mapY(state, y + h * 0.5), w * 0.5 * state.sx, h * 0.5 * state.sy)
    }
    elif crx > 0 and cry > 0
    {
        path.setRoundRectRaw(mapX(state, x), mapY(state, y), w * state.sx, h * state.sy, crx * state.sx, cry * state.sy)
    }
    else do
        path.setRectRaw(mapX(state, x), mapY(state, y), w * state.sx, h * state.sy)
    emitShape(drawing, list, state)
}

private func emitEllipse(drawing: *Drawing, state: *GroupState, cx, cy, rx, ry: f32)
{
    if rx <= 0 or ry <= 0 do
        return

    var list: LinePathList
    let path = list.newPath()
    path.setEllipseRaw(mapX(state, cx), mapY(state, cy), rx * state.sx, ry * state.sy)
    emitShape(drawing, list, state)
}

private func emitPoly(drawing: *Drawing, state: *GroupState, points: string, closeIt: bool)
{
    var list: LinePathList
    let path = list.newPath()
    var pos  = 0'u64
    var idx  = 0

    while pos < @countof(points)
    {
        var look = pos
        while look < @countof(points) and (points[look] == ' ' or points[look] == ',') do
            look += 1
        if look >= @countof(points) or !isNumberStart(points[look]) do
            break

        let x = scanNumber(points, &pos)
        let y = scanNumber(points, &pos)
        if idx == 0 do
            path.start(mapX(state, x), mapY(state, y))
        else do
            path.lineTo(mapX(state, x), mapY(state, y))
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
        let len = @countof(.text)
        while .pos < len and .text[.pos] != c do
            .pos += 1
    }

    mtd parseStyleSheet()
    {
        let contentStart = .pos
        var contentEnd   = .pos
        while contentEnd + 7 < @countof(.text)
        {
            if .text[contentEnd] == '<' and .text[contentEnd + 1] == '/' and !Latin1.compare(cast(string) @mkslice(@dataof(.text) + contentEnd + 2, 5), "style", ignoreCase: true) do
                break
            contentEnd += 1
        }

        let content = cast(string) @mkslice(@dataof(.text) + contentStart, contentEnd - contentStart)
        var pos     = 0'u64
        while pos < @countof(content)
        {
            while pos < @countof(content) and content[pos] != '{' do
                pos += 1
            if pos >= @countof(content) do
                break

            var selectorStart = pos
            while selectorStart and content[selectorStart - 1] != '}' do
                selectorStart -= 1
            let selector = Latin1.trim(cast(string) @mkslice(@dataof(content) + selectorStart, pos - selectorStart))
            pos += 1
            let declarationsStart = pos
            while pos < @countof(content) and content[pos] != '}' do
                pos += 1
            if pos >= @countof(content) do
                break

            if @countof(selector) and selector[0] != '@' do
                .styles.add({String.from(selector), String.from(Latin1.trim(cast(string) @mkslice(@dataof(content) + declarationsStart, pos - declarationsStart)))})
            pos += 1
        }

        .pos = contentEnd
        .skipUntil('>')
        if .pos < @countof(.text) do
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
                    matches = @countof(selector) and selector[0] != '.' and selector[0] != '#' and !Latin1.compare(selector, elementName, ignoreCase: true)

                case 1:
                    if @countof(selector) > 1 and selector[0] == '.' and classAttr
                    {
                        let wanted  = cast(string) @mkslice(@dataof(selector) + 1, @countof(selector) - 1)
                        var classes = classAttr.value.toString()
                        while @countof(classes)
                        {
                            var end = 0'u64
                            while end < @countof(classes) and classes[end] != ' ' and classes[end] != '\t' and classes[end] != '\n' and classes[end] != '\r' do
                                end += 1
                            if !Latin1.compare(cast(string) @mkslice(@dataof(classes), end), wanted) do
                                matches = true
                            if matches or end == @countof(classes) do
                                break
                            classes = Latin1.trim(cast(string) @mkslice(@dataof(classes) + end, @countof(classes) - end))
                        }
                    }

                case 2:
                    if @countof(selector) > 1 and selector[0] == '#' and idAttr do
                        matches = !Latin1.compare(cast(string) @mkslice(@dataof(selector) + 1, @countof(selector) - 1), idAttr.value.toString())
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
        let len = @countof(.text)

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
            let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)

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
            let value = cast(string) @mkslice(@dataof(.text) + valueStart, .pos - valueStart)
            .pos += 1

            switch name
            {
            case "d", "x", "y", "dx", "dy", "width", "height", "rx", "ry", "cx", "cy", "r", "fx", "fy", "fr", "points", "pathLength", "x1", "y1", "x2", "y2", "viewBox", "id", "class", "href", "xlink:href", "gradientUnits", "gradientTransform", "spreadMethod", "patternUnits", "patternContentUnits", "stdDeviation", "offset", "stop-color", "stop-opacity", "flood-color", "flood-opacity":
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
        let len = @countof(.text)
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
            let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)

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

        var href = geo.tryFind("href")
        if !href do
            href = geo.tryFind("xlink:href")
        if href
        {
            var baseId = href.value.toString()
            if @countof(baseId) and baseId[0] == '#' do
                baseId = cast(string) @mkslice(@dataof(baseId) + 1, @countof(baseId) - 1)
            let base = .gradients.tryFind(baseId)
            if base do
                gradient = base.value
        }

        gradient.kind = kind
        switch kind
        {
        case .Linear:
            gradient.x1 = .geoLength(geo, "x1", gradient.x1)
            gradient.y1 = .geoLength(geo, "y1", gradient.y1)
            gradient.x2 = .geoLength(geo, "x2", gradient.x2)
            gradient.y2 = .geoLength(geo, "y2", gradient.y2)

        case .Radial:
            gradient.cx = .geoLength(geo, "cx", gradient.cx)
            gradient.cy = .geoLength(geo, "cy", gradient.cy)
            gradient.r  = .geoLength(geo, "r", gradient.r)
            gradient.fx = .geoLength(geo, "fx", gradient.cx)
            gradient.fy = .geoLength(geo, "fy", gradient.cy)
            gradient.fr = .geoLength(geo, "fr", gradient.fr)
        }

        let units = geo.tryFind("gradientUnits")
        if units do
            gradient.userSpace = units.value.toString() == "userSpaceOnUse"

        let spread = geo.tryFind("spreadMethod")
        if spread
        {
            switch spread.value.toString()
            {
            case "repeat":  gradient.spread = .Repeat
            case "reflect": gradient.spread = .Mirror
            default:        gradient.spread = .Clamp
            }
        }

        let transform = geo.tryFind("gradientTransform")
        if transform
        {
            var transformState: GroupState
            applyStyleProperty(&transformState, "transform", transform.value.toString())
            gradient.tx = transformState.tx
            gradient.ty = transformState.ty
            gradient.sx = transformState.sx
            gradient.sy = transformState.sy
        }

        if !selfClosed
        {
            gradient.stops.clear()
            try .parseGradientStops(&gradient)
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
            if (@countof(href) / 4) * 3 > .options.maxImageBytes do
                fail Swag.SystemError{"embedded SVG image exceeds the configured byte limit"}
            return try Image.fromDataUri(href)
        }

        if @countof(.options.externalResourceRoot) == 0 do
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
        item.image   = try .loadImage(href.value.toString())
        item.rect    = {mapX(state, .geoNumber(geo, "x")), mapY(state, .geoNumber(geo, "y")), width * state.sx, height * state.sy}
        item.opacity = state.opacity
        if !state.inDefs do
            .drawing.items.add(DrawingItem{.Image, index})
    }

    mtd addTextRun(text: string, state: *GroupState, geo: *HashTable'(String, String), block: *SvgText, first: bool) fail
    {
        let normalized = normalizedText(text)
        if normalized.isEmpty() or !state.isDisplayed or !state.isVisible or !state.hasFill do
            return

        if !.typeFace
        {
            if @countof(.options.fontFileName) == 0 do
                fail Swag.SystemError{"SVG text requires a configured font file"}
            .typeFace = try TypeFace.load(.options.fontFileName)
        }

        let x   = geo.tryFind("x")
        let y   = geo.tryFind("y")
        let dx  = .geoNumber(geo, "dx")
        let dy  = .geoNumber(geo, "dy")
        let run = block.runs.emplaceInitAddress()
        run.text        = #move normalized
        run.typeFace    = .typeFace!
        run.hasX        = first or x != null
        run.hasY        = first or y != null
        run.x           = mapX(state, x ? .geoNumber(geo, "x") : 0)
        run.y           = mapY(state, y ? .geoNumber(geo, "y") : 0)
        run.dx          = dx * state.sx
        run.dy          = dy * state.sy
        run.fontSize    = state.fontSize * Math.abs(state.sy)
        run.color       = state.fillColor
        run.opacity     = state.fillOpacity * state.opacity
        run.anchor      = state.textAnchor
        run.forceBold   = state.forceBold
        run.forceItalic = state.forceItalic
    }

    mtd parseText(state: GroupState, geo: *HashTable'(String, String), selfClosed: bool) fail
    {
        let index = .drawing.texts.count
        let block = .drawing.texts.emplaceInitAddress()
        if selfClosed do
            return

        let len   = @countof(.text)
        var first = true
        while .pos < len
        {
            let textStart = .pos
            .skipUntil('<')
            if .pos > textStart
            {
                let content = cast(string) @mkslice(@dataof(.text) + textStart, .pos - textStart)
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
            let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)

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
            let childText = cast(string) @mkslice(@dataof(.text) + childStart, .pos - childStart)
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
            let len = @countof(.text)
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
                let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)
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
        let len = @countof(.text)
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
            let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)

            var state        = parent
            var geo: HashTable'(String, String)
            let {selfClosed} = .scanAttributes(&state, &geo)
            .applyStyleRules(name, &geo, &state)
            let firstShape = .drawing.shapes.count

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
                        state.tx        -= viewX * state.sx
                        state.ty        -= viewY * state.sy
                    }
                    else
                    {
                        .drawing.width  = .geoNumber(&geo, "width", 0)
                        .drawing.height = .geoNumber(&geo, "height", 0)
                    }
                }
                else
                {
                    state.tx += .geoNumber(&geo, "x") * state.sx
                    state.ty += .geoNumber(&geo, "y") * state.sy
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
                    var list: LinePathList
                    parsePathData(&list, d.value.toString(), &state)
                    emitShape(.drawing, list, &state)
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
                let path = list.newPath()
                path.start(mapX(&state, .geoNumber(&geo, "x1")), mapY(&state, .geoNumber(&geo, "y1")))
                path.lineTo(mapX(&state, .geoNumber(&geo, "x2")), mapY(&state, .geoNumber(&geo, "y2")))
                var strokeOnly = state
                strokeOnly.hasFill = false
                emitShape(.drawing, list, &strokeOnly)
                if !selfClosed do
                    try .parseContent(state)

            case "defs":

                // Definitions are parsed in local coordinates and withheld from
                // painting; `use` elements instantiate them.
                var defState: GroupState
                defState.inDefs = true
                if !selfClosed do
                    try .parseContent(defState)

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
                    var name2 = href.value.toString()
                    if @countof(name2) and name2[0] == '#' do
                        name2 = cast(string) @mkslice(@dataof(name2) + 1, @countof(name2) - 1)
                    let here = .defs.tryFind(name2)
                    if here do
                        .instantiate(here.value.first, here.value.count, &state, .geoNumber(&geo, "x"), .geoNumber(&geo, "y"))
                }

                if !selfClosed do
                    try .parseContent(state)

            case "polygon":
                let pts = geo.tryFind("points")
                if pts do
                    emitPoly(.drawing, &state, pts.value.toString(), true)
                if !selfClosed do
                    try .parseContent(state)

            case "polyline":
                let pts = geo.tryFind("points")
                if pts
                {
                    var strokeOnly = state
                    strokeOnly.hasFill = false
                    emitPoly(.drawing, &strokeOnly, pts.value.toString(), false)
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
                .applyPathLength(firstShape, .drawing.shapes.count - firstShape, authoredPathLength, state.sx)

            // Register the shapes a defs child emitted under its id.
            if state.inDefs and .drawing.shapes.count > firstShape
            {
                let idAttr = geo.tryFind("id")
                if idAttr do
                    .defs.add(idAttr.value, {firstShape, .drawing.shapes.count - firstShape})
            }
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
        var px = .gradientCoordinate(x, boundsMin.x, boundsSize.x, .drawing.width, gradient.userSpace)
        var py = .gradientCoordinate(y, boundsMin.y, boundsSize.y, .drawing.height, gradient.userSpace)
        if gradient.userSpace
        {
            px = (px * gradient.sx + gradient.tx) * shape.paintSx + shape.paintTx
            py = (py * gradient.sy + gradient.ty) * shape.paintSy + shape.paintTy
        }
        else
        {
            px = boundsMin.x + ((px - boundsMin.x) / Math.max(boundsSize.x, 0.000001) * gradient.sx + gradient.tx) * boundsSize.x
            py = boundsMin.y + ((py - boundsMin.y) / Math.max(boundsSize.y, 0.000001) * gradient.sy + gradient.ty) * boundsSize.y
        }

        return {px, py}
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
                result.gradientRadius0 = Math.max(inner * gradient.sx * shape.paintSx, 0)
                result.gradientRadius1 = Math.max(radius * gradient.sx * shape.paintSx, result.gradientRadius0)
            }
            else
            {
                result.gradientRadius0 = Math.max(gradient.fr.value * size.x * gradient.sx, 0)
                result.gradientRadius1 = Math.max(gradient.r.value * size.x * gradient.sx, result.gradientRadius0)
            }
        }

        for stop in gradient.stops do
            result.addGradientStop(stop.offset, stop.color)
        return result
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
    mtd instantiate(first, count: u64, state: *GroupState, offX, offY: f32)
    {
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
            var paintTx, paintTy:            f32
            var paintSx, paintSy:            f32

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
                strokeWidth   = src.strokeWidth * state.sx
                strokeOffset  = src.strokeOffset * state.sx
                strokeMiter   = src.strokeMiter
                strokePattern = src.strokePattern
                for &value in strokePattern do
                    value[] *= state.sx
                capStyle  = src.capStyle
                joinStyle = src.joinStyle
                paintTx   = mapX(state, src.paintTx + offX)
                paintTy   = mapY(state, src.paintTy + offY)
                paintSx   = src.paintSx * state.sx
                paintSy   = src.paintSy * state.sy

                for srcPath in src.pathList.paths
                {
                    let path = list.newPath()
                    path.start(mapX(state, srcPath.startPoint.x + offX), mapY(state, srcPath.startPoint.y + offY))
                    for &element in srcPath.elements
                    {
                        switch element.type
                        {
                        case .Line:
                            path.lineTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY))

                        case .Bezier1:
                            path.bezierTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY), mapX(state, element.p1.x + offX), mapY(state, element.p1.y + offY))

                        case .Bezier2:
                            path.bezierTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY), mapX(state, element.p1.x + offX), mapY(state, element.p1.y + offY), mapX(state, element.p2.x + offX), mapY(state, element.p2.y + offY))

                        case .Arc:

                            // An arc stores its center in `position`, its angle
                            // interval in `p1`, and its radii in `p2`.
                            path.arcTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY), element.p2.x * state.sx, element.p2.y * state.sy, Math.Angle.fromRadians(element.p1.x), Math.Angle.fromRadians(element.p1.y))

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
            shape.pathList      = #move list
            shape.fillColor     = fillColor
            shape.fillPaintId   = #move fillPaintId
            shape.fillOpacity   = fillOpacity
            shape.strokeColor   = strokeColor
            shape.strokePaintId = #move strokePaintId
            shape.strokeOpacity = strokeOpacity
            shape.hasFill       = hasFill
            shape.hasStroke     = hasStroke
            shape.evenOdd       = evenOdd
            shape.strokeWidth   = strokeWidth
            shape.strokeOffset  = strokeOffset
            shape.strokeMiter   = strokeMiter
            shape.strokePattern = #move strokePattern
            shape.capStyle      = capStyle
            shape.joinStyle     = joinStyle
            shape.paintTx       = paintTx
            shape.paintTy       = paintTy
            shape.paintSx       = paintSx
            shape.paintSy       = paintSy
            shape.hidden        = state.inDefs
            shape.filterId      = #move filterId
            if !shape.hidden do
                .drawing.items.add(DrawingItem{.Shape, shapeIndex})
        }
    }
}

impl Drawing
{
    // Returns the number of parsed shapes.
    mtd const shapeCount()->u64 => .shapes.count

    // Parses an SVG document authored in the supported subset.
    //
    // The result owns its shapes and decoded images. Text supports one-level `tspan`
    // runs with `x`, `y`, `dx`, `dy`, size, anchor, weight, style, solid fill, and
    // opacity. Images stretch into their declared rectangle. Patterns repeat vector
    // shape tiles in user or object-bounding-box units. Filters support either a
    // Gaussian blur followed by offsets, or a standalone `feDropShadow`.
    //
    // `options` confines external image references and selects the typeface for text;
    // see [[Pixel.Svg.ParseOptions]]. Unknown elements and attributes are ignored.
    func parse(text: string, options: ParseOptions = {})->Drawing fail
    {
        var result: retval

        var parser = Parser{text: text, drawing: &result, options: options}

        var root: GroupState
        try parser.parseContent(root)
        parser.resolvePaints()
        result.patterns = #move parser.patterns
        result.filters  = #move parser.filters

        if result.width <= 0 or result.height <= 0 do
            fail Swag.SystemError{"SVG document has no valid dimensions"}

        return result
    }

    // Paints the drawing with its origin at `(x, y)` of the current path space,
    // its content multiplied by `scale`.
    //
    // Fills honor the winding of their contours (a counter-clockwise contour is a
    // hole), strokes honor width, caps, and joins scaled by `scale`.
    mtd const paint(painter: *Painter, x, y: f32, scale = 1.0'f32)
    {
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

    private mtd const paintText(painter: *Painter, text: const *SvgText, compensateAlpha: bool)
    {
        var x, baseline: f32
        for run in text.runs
        {
            if run.hasX do
                x = run.x
            if run.hasY do
                baseline = run.y
            x        += run.dx
            baseline += run.dy

            let size    = cast(u32) Math.max(Math.round(run.fontSize), 1.0'f32)
            let font    = painter.renderer().fontCache().createFont(run.typeFace, size, forceBold: run.forceBold, forceItalic: run.forceItalic)
            let metrics = Painter.measureString(run.text.toString(), font)
            var drawX   = x
            if run.anchor == .Middle do
                drawX -= metrics.width * 0.5
            elif run.anchor == .End do
                drawX -= metrics.width

            var color = run.color.withAlphaF32(run.opacity)
            if compensateAlpha do
                color.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) color.a / 255.0))
            painter.drawString(drawX, baseline - font.ascent, run.text.toString(), font, color)
            x += metrics.width
        }
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

        for item in .items
        {
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
                .paintText(painter, &.texts[item.index], compensateAlpha)

            case .Image:
                .paintImage(painter, &.images[item.index], compensateAlpha)
            }
        }
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
    // tolerance the two backends already carry elsewhere. Both the supersampled pass
    // and its downsample happen inside the renderer, so no supersampled buffer ever
    // crosses back to the caller: only the finished image does.
    //
    // The renderer must be ready to draw — its context selected and [[Pixel.IRenderer.init]]
    // called — because this records a complete painter submission and executes it.
    mtd const rasterize(renderer: IRenderer, width, height: s32, supersample: u8 = 2)->Image
    {
        Debug.assert(width > 0 and height > 0)

        let ss = cast(s32) Math.max(supersample, 1'u8)
        let bw = width * ss
        let bh = height * ss

        // Targets are created at the exact size instead of acquired from the pool, which
        // rounds up to a power of two: the resolve reads the sampled target as a whole,
        // and padding would land inside the box filter.
        var sampled = renderer.createRenderTarget(bw, bh)
        var resolved: RenderTarget
        if ss > 1 do
            resolved = renderer.createRenderTarget(width, height)

        // Antialiased and translucent shapes go through the overlap-safe pass, which
        // sacrifices the destination alpha channel; render into a target with the
        // alpha-preserving replay so the result carries a correct alpha mask.
        var painter = Painter.create(renderer)
        painter.begin()
        let directAlpha = .texts.count or .images.count or .patterns.count or .filters.count
        painter.bindRenderTarget(&sampled, paintAlpha: !directAlpha)
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.Zero))
        if !directAlpha do
            painter.setColorMaskColor()
        .paintImpl(&painter, 0, 0, cast(f32) bw / .width, !directAlpha)
        painter.unbindRenderTarget()

        // Box-filter the samples down with the renderer's own resolve program, the one
        // the layer pipeline already uses. Unbinding above has resolved the alpha plane,
        // so the sampled target is a plain texture by the time it is read here.
        if ss > 1
        {
            let dstRect = Math.Rectangle{0, 0, cast(f32) width, cast(f32) height}
            let srcRect = Math.Rectangle{0, 0, cast(f32) bw, cast(f32) bh}
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

        // Render-target readbacks follow the bottom-up row convention, which is also
        // the storage convention of [[Pixel.Image]] buffers, so the readback is kept
        // as is: flipping here would make the drawing render upside down as a texture.
        if ss == 1
        {
            var only = renderer.readRenderTarget(&sampled, 0, 0, bw, bh)
            renderer.deleteRenderTarget(&sampled)
            return only
        }

        var result = renderer.readRenderTarget(&resolved, 0, 0, width, height)
        renderer.deleteRenderTarget(&resolved)
        renderer.deleteRenderTarget(&sampled)

        // The resolve leaves a fully transparent pixel black; make it white instead, so a
        // consumer that tints the result, or a sampler that interpolates across the edge
        // of a shape, never blends a dark fringe in.
        result.setTransparentColor(Color.fromArgb(Argb.White))
        return result
    }
}

#global public
#global namespace Svg

using Core, Core.Math

private const RasterSampleTileSide = 1024's32
private const PaintBlockSize       = 64'u64
private const PaintBinCount        = 128'u64

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
//
// The serif default is the face a browser puts behind `serif` on Windows, so a figure checked in
// a browser lays out the same here. It also draws lining figures: a face with old-style figures,
// such as Georgia, sinks 3, 4, 5, 7 and 9 below the baseline and leaves 0, 1 and 2 at x-height,
// and a number placed to sit centered in a circle no longer does.
struct ParseOptions
{
    public
    {
        externalResourceRoot: string = ""     // Canonical containment root for relative image references; empty disables them.
        fontFileName:         string = "segoeui.ttf"        // Typeface used by text with no recognized or no serif/monospace family.
        serifFontFileName:    string = "times.ttf"          // Typeface used by a `serif` family; empty selects `fontFileName`.
        monoFontFileName:     string = "consola.ttf"        // Typeface used by a `monospace` family; empty selects `fontFileName`.
        maxImageBytes:        u64    = 16 * 1024 * 1024     // Maximum encoded bytes accepted for each embedded or external image.
    }
}

// Describes one filled or stroked shape of a parsed [[Pixel.Svg.Drawing]].
//
// The contours are stored in the drawing's user units, already transformed by the
// group transforms they were parsed under.
#[Swag.Opaque]
struct Shape
{
    internal
    {
        pathList: LinePathList     // Contours, in drawing user units.
        scanFill: u64     // Index plus one of the raster cache for a dense solid fill.

        fillGradient: u64         // Index plus one of the resolved gradient, or zero for solid paint.
        fillColor:    Color       // Solid fill color, including opacity once resolved.
        fillPaintId:  u64         // Interned fill paint identifier, or zero for a solid fill.
        fillOpacity:  f32 = 1     // Fill-only opacity multiplier.
        hasFill:      bool        // Whether the shape is filled.
        evenOdd:      bool        // Whether the fill uses the even-odd rule.

        hidden: bool     // Whether the shape is a reusable definition, not painted directly.

        strokeGradient: u64                      // Index plus one of the resolved gradient, or zero for solid paint.
        strokeColor:    Color                    // Solid stroke color, including opacity once resolved.
        strokePaintId:  u64                      // Interned stroke paint identifier, or zero for a solid stroke.
        strokeOpacity:  f32          = 1         // Stroke-only opacity multiplier.
        strokeWidth:    f32          = 1         // Stroke width, in user units.
        strokePattern:  Array'f32                // Alternating dash and gap lengths, in user units.
        strokeOffset:   f32                      // Offset into the dash sequence, in user units.
        strokeMiter:    f32          = 3         // Maximum miter length relative to stroke width.
        hasStroke:      bool                     // Whether the shape is stroked.
        capStyle:       LineCapStyle = None      // Cap applied to open subpath ends.
        joinStyle:      JoinStyle    = Miter     // Join between stroke segments.

        paintTransform: Math.Transform2 = Math.Transform2.Identity     // Element transform retained for user-space paint servers.

        filterId: u64     // Interned filter identifier, or zero without a reference.
    }
}

// Holds a parsed vector document, ready to paint at any scale.
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

    shapes:          Array'Shape                    // Parsed vector shapes, including hidden definitions.
    imageSize:       Vector2                        // Absolute root dimensions in CSS pixels, independent of view-box units.
    texts:           Array'SvgText                  // Parsed text blocks referenced by the paint-order list.
    images:          Array'SvgImage                 // Raster placements referenced by the paint-order list.
    rasterImages:    Array'Image                    // Decoded bitmaps shared by their placements.
    items:           Array'DrawingItem              // Visible elements in paint order.
    paintBins:       Array'PaintBin                 // Spatial buckets of paint item indices.
    paintBlocks:     Array'PaintBlock               // Bounds of consecutive runs of paint items.
    gradientBrushes: Array'Brush                    // Resolved fill and stroke gradient brushes.
    scanFills:       Array'ScanFill                 // Raster caches for dense solid fills.
    patterns:        HashTable'(u64, Pattern)       // Resolved repeating paint servers by their interned identifier.
    filters:         HashTable'(u64, SvgFilter)     // Resolved filter primitive chains by their interned identifier.
}

private enum DrawingItemKind
{
    Shape
    Text
    Image
}

#[Swag.Opaque]
internal struct DrawingItem
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

private struct PaintBlock
{
    minimum, maximum: Vector2
    bounded: bool
}

private func finitePoint(point: Vector2)->bool => Math.isFinite(point.x) and Math.isFinite(point.y)

private impl PaintBlock
{
    mtd const misses(transform: Math.Transform2, visible: Rectangle)->bool
    {
        if not .bounded do
            return false

        // The caller uses an axis-aligned transform, so these two corners enclose the block.
        let first = transform.transformPoint(.minimum)
        let last  = transform.transformPoint(.maximum)
        if not finitePoint(first) or not finitePoint(last) do
            return false

        let lower = Vector2.min(first, last)
        let upper = Vector2.max(first, last)
        if not finitePoint(upper - lower) do
            return false

        // Cover the rounding in individual transformed rectangles and their fringe inflation.
        let xMargin = InkFringeMargin + Math.max(Math.abs(lower.x), Math.abs(upper.x)) * 0.000001
        let yMargin = InkFringeMargin + Math.max(Math.abs(lower.y), Math.abs(upper.y)) * 0.000001
        return upper.x + xMargin < visible.x or
               lower.x - xMargin > visible.right() or
               upper.y + yMargin < visible.y or
               lower.y - yMargin > visible.bottom()
    }
}

private struct PaintBin
{
    bounds:  PaintBlock
    indices: Array'u64
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
    late typeFace: *TypeFace
    x, y:          f32
    dx, dy:        f32
    fontSize:      f32
    letterSpacing: f32
    wordSpacing:   f32
    rotation:      f32     // Direction the baseline runs in, from the element transform.
    color:         Color
    opacity:       f32 = 1
    anchor:        TextAnchor
    forceBold:     bool
    forceItalic:   bool
    hasX, hasY:    bool
}

#[Swag.Opaque]
internal struct SvgText
{
    runs: Array'SvgTextRun
}

#[Swag.Opaque]
internal struct SvgImage
{
    rasterIndex: u64
    rect:        Rectangle           // Destination in the user units of the element.
    transform:   Math.Transform2     // User units to drawing space.
    opacity:     f32 = 1
}

#[Swag.Opaque]
internal struct Pattern
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

#[Swag.Opaque]
internal struct SvgFilter
{
    primitives: Array'FilterPrimitive
}

// Attribute state inherited through `svg` and `g` elements.
// References borrow the SVG source. Shapes copy the references they keep after parsing.
private struct GroupState
{
    // User space to drawing space, composed down the element tree.
    //
    // It is a full affine matrix rather than a translation and a scale, because that is what
    // `transform` states: a rotated label, a `matrix(...)` from a drawing tool, and a skewed
    // shadow are ordinary authored content, and reducing them to a scale places their geometry
    // somewhere it was never meant to be.
    transform: Math.Transform2 = Math.Transform2.Identity

    fillColor:   Color  = Color.fromArgb(Argb.Black)     // Inherited fill color.
    fillPaintId: string = ""       // Inherited fill paint server.
    fillOpacity: f32    = 1        // Inherited fill-only opacity.
    hasFill:     bool   = true     // Whether fill is enabled.
    evenOdd:     bool              // Inherited fill rule.

    strokeColor:   Color                    // Inherited stroke color.
    strokePaintId: string       = ""        // Inherited stroke paint server.
    strokeOpacity: f32          = 1         // Inherited stroke-only opacity.
    strokeWidth:   f32          = 1         // Inherited stroke width, in user units.
    strokePattern: string       = ""        // Inherited authored dash and gap lengths.
    strokeOffset:  SvgLength                // Inherited offset into the dash sequence.
    strokeMiter:   f32          = 3         // Inherited miter limit.
    hasStroke:     bool                     // Whether stroke is enabled.
    capStyle:      LineCapStyle = None      // Inherited stroke cap.
    joinStyle:     JoinStyle    = Miter     // Inherited stroke join.

    markerStartId: string = ""     // Inherited `marker-start` reference.
    markerMidId:   string = ""     // Inherited `marker-mid` reference.
    markerEndId:   string = ""     // Inherited `marker-end` reference.

    clipPathId:    string = ""     // Inherited `clip-path` reference.
    clipTransform: Math.Transform2 = Math.Transform2.Identity     // Transform of the element that named the clip.

    currentColor: Color = Color.fromArgb(Argb.Black)     // Inherited `currentColor` value.

    isDisplayed: bool = true     // Whether an ancestor selected `display:none`.
    isVisible:   bool = true     // Inherited visibility state.

    opacity: f32 = 1     // Accumulated group opacity.
    inDefs:  bool        // Whether the element sits inside a `defs` scope.

    fontSize:      f32    = 16
    fontFamily:    FontFamilyKind
    letterSpacing: f32     // Extra space between glyphs, in the user units of this scope.
    wordSpacing:   f32     // Extra space added to each blank, in the user units of this scope.
    textAnchor:    TextAnchor
    forceBold:     bool
    forceItalic:   bool
    filterId:      string = ""
}

private impl GroupState
{
    #[Swag.Inline]
    mtd const drawsShape(strokeOnly = false)->bool =>
        .isDisplayed and .isVisible and (.hasStroke or (not strokeOnly and .hasFill))

    // Definitions keep their own geometry without placing markers on it.
    #[Swag.Inline]
    mtd const hasMarkers()->bool =>
        not .inDefs and (.markerStartId.count or .markerMidId.count or .markerEndId.count)
}

private struct ElementScope
{
    state:        GroupState
    firstShape, firstItem: u64
    pathLength:   f32
    definitionId: string?
    isSvg:        bool
}

private struct Parser
{
    text:    string     // Whole document.
    pos:     u64        // Read position.
    drawing: *Drawing

    // Shapes defined inside `defs`, by id, instantiated by `use` elements. The
    // ranges index the drawing's shape array: defs shapes are parsed in place and
    // withheld from painting. These lookup tables borrow identifiers from the source.
    defs:           HashTable'(string, { first: u64, count: u64 })
    clipPaths:      HashTable'(string, { first: u64, count: u64 })
    symbols:        HashTable'(string, SymbolViewport)
    markers:        HashTable'(string, MarkerDefinition)
    gradients:      HashTable'(string, Gradient)
    referenceIds:   HashTable'(string, u64)
    referenceNames: Array'string
    patterns:       HashTable'(u64, Pattern)
    filters:        HashTable'(u64, SvgFilter)
    styles:         StyleSheet
    dashPatterns:   HashTable'(string, Array'SvgLength)
    dashScratch:    Array'SvgLength
    embeddedImages: HashTable'(string, u64)     // Raster indices plus one, keyed by the authored URI.
    options:        ParseOptions
    typeFaces:      [FontFamilyKind.count] (*TypeFace?)
    svgDepth:       u32
    inDefs:         bool     // Whether parsing currently sits inside a `defs` element.
    dimensionsOnly: bool
}

private enum AttributeKind
{
    Unknown
    D
    X
    Y
    Dx
    Dy
    Width
    Height
    Rx
    Ry
    Cx
    Cy
    R
    Fx
    Fy
    Fr
    Points
    PathLength
    X1
    Y1
    X2
    Y2
    ViewBox
    Id
    Class
    Href
    XlinkHref
    GradientUnits
    GradientTransform
    SpreadMethod
    PatternUnits
    PatternContentUnits
    StdDeviation
    Offset
    StopColor
    StopOpacity
    FloodColor
    FloodOpacity
    MarkerWidth
    MarkerHeight
    RefX
    RefY
    Orient
    MarkerUnits
    Style
}

#assert(AttributeKind.count <= 64)

private struct AttributeValue
{
    value: string = ""
}

// Uses fixed slots for the attributes that consumers look up after scanning.
// A bit records presence separately from the borrowed source value, which may be empty.
private struct AttributeMap
{
    values:  Array'AttributeValue
    present: u64
}

private impl AttributeMap
{
    #[Swag.Inline]
    mtd clear()
    {
        .present = 0
    }

    #[Swag.Inline]
    mtd add(kind: AttributeKind, value: string)
    {
        if .values.isEmpty() do
            .values.resize(AttributeKind.count)

        let index = cast(u64, kind)
        .values[index].value = value
        .present |= 1'u64 << index
    }

    #[Swag.Inline]
    mtd const tryFind(kind: AttributeKind)->const *AttributeValue?
    {
        let index = cast(u64, kind)
        if not (.present & (1'u64 << index)) do
            return null
        return &.values[index]
    }
}

private func attributeKind(name: string)->AttributeKind
{
    switch name
    {
    case "d":                   return .D
    case "x":                   return .X
    case "y":                   return .Y
    case "dx":                  return .Dx
    case "dy":                  return .Dy
    case "width":               return .Width
    case "height":              return .Height
    case "rx":                  return .Rx
    case "ry":                  return .Ry
    case "cx":                  return .Cx
    case "cy":                  return .Cy
    case "r":                   return .R
    case "fx":                  return .Fx
    case "fy":                  return .Fy
    case "fr":                  return .Fr
    case "points":              return .Points
    case "pathLength":          return .PathLength
    case "x1":                  return .X1
    case "y1":                  return .Y1
    case "x2":                  return .X2
    case "y2":                  return .Y2
    case "viewBox":             return .ViewBox
    case "id":                  return .Id
    case "class":               return .Class
    case "href":                return .Href
    case "xlink:href":          return .XlinkHref
    case "gradientUnits":       return .GradientUnits
    case "gradientTransform":   return .GradientTransform
    case "spreadMethod":        return .SpreadMethod
    case "patternUnits":        return .PatternUnits
    case "patternContentUnits": return .PatternContentUnits
    case "stdDeviation":        return .StdDeviation
    case "offset":              return .Offset
    case "stop-color":          return .StopColor
    case "stop-opacity":        return .StopOpacity
    case "flood-color":         return .FloodColor
    case "flood-opacity":       return .FloodOpacity
    case "markerWidth":         return .MarkerWidth
    case "markerHeight":        return .MarkerHeight
    case "refX":                return .RefX
    case "refY":                return .RefY
    case "orient":              return .Orient
    case "markerUnits":         return .MarkerUnits
    case "style":               return .Style
    default:                    return .Unknown
    }
}

private struct StyleDeclaration
{
    name, value: string
}

private struct StyleRule
{
    first, count: u64
    next:         u64 = Swag.U64.Max
}

private struct StyleRuleList
{
    first:     u64 = Swag.U64.Max
    last:      u64 = Swag.U64.Max
    matchedIn: u64
}

// Each selector links rules in source order through the shared array.
private struct StyleSheet
{
    declarations: Array'StyleDeclaration
    rules:        Array'StyleRule
    byTag:        HashTable'(String, StyleRuleList)
    byClass:      HashTable'(string, StyleRuleList)
    byId:         HashTable'(string, StyleRuleList)

    classMatches:    Array'u64
    matchGeneration: u64
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

    href:      string = ""           // Gradient this one inherits from, without its `#`.
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

    // Most user-space references in a group share one transform and opacity.
    cachedBrush:     u64
    cachedTransform: Math.Transform2
    cachedOpacity:   f32
}

// Numeric scanning /////////////////////////////////////////////////////////////

private func isNumberStart(c: u8)->bool => (c >= '0' and c <= '9') or c == '-' or c == '+' or c == '.'

private func skipNumberSeparators(text: string, start: u64)->u64
{
    var pos = start
    while pos < text.count
    {
        let c = text[pos]
        if c != ' ' and c != ',' and c != '\t' and c != '\n' and c != '\r' do
            break
        pos += 1
    }

    return pos
}

// Scans one floating-point number at the current position.
private func readNumber(s: string, pos: *u64)->f32
{
    let len   = s.count
    var i     = pos[]
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
    return catch StrConv.toF32(s[start until i]) orelse 0
}

private func scanNumber(s: string, pos: *u64)->f32
{
    pos[] = skipNumberSeparators(s, pos[])
    return readNumber(s, pos)
}

private func parseLength(value: string, defaultValue: SvgLength = {})->SvgLength
{
    var pos = 0'u64
    while pos < value.count and (value[pos] == ' ' or value[pos] == '\t' or value[pos] == '\n' or value[pos] == '\r') do
        pos += 1
    if pos >= value.count or not isNumberStart(value[pos]) do
        return defaultValue

    var result: #returntype
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

// Image dimensions have no containing viewport or font against which to resolve relative units.
private func parseImageLength(value: string)->f32
{
    let text = Latin1.trim(value)
    if not text.count or not isNumberStart(text[0]) do
        return 0
    var pos    = 0'u64
    let number = scanNumber(text, &pos)
    if number <= 0 do
        return 0
    switch Latin1.trim(text[pos to])
    {
    case "", "px": return number
    case "in":     return number * 96
    case "cm":     return number * (96 / 2.54)
    case "mm":     return number * (96 / 25.4)
    case "Q", "q": return number * (96 / 101.6)
    case "pt":     return number * (96 / 72.0)
    case "pc":     return number * 16
    default:       return 0
    }
}

private func parsePaintId(value: string)->string
{
    let trimmed = Latin1.trim(value)
    if trimmed.count < 7 or Latin1.compare(trimmed[until 5], "url(#", ignoreCase: true) do
        return ""

    var end = 5'u64
    while end < trimmed.count and trimmed[end] != ')' do
        end += 1
    return trimmed[5 until end]
}

// Reduces a `font-family` list to the class a host can honour.
//
// A list is a preference order over faces the machine may or may not carry, so the
// first recognized name decides and an unrecognized one is skipped. The table is the
// one [[Gui.HtmlView]] reads, for the same reason: a themed application answers with a
// class, not with a face.
private func parseFontFamily(value: string)->{ kind: FontFamilyKind, matched: bool }
{
    var result: #returntype

    var scan = value
    while scan.count
    {
        var stop = 0'u64
        while stop < scan.count and scan[stop] != ',' do
            stop += 1

        var name = Latin1.trim(scan[until stop])
        if name.count >= 2 and (name[0] == '"' or name[0] == '\'') do
            name = Latin1.trim(name[1 until name.count - 1])

        var lowered = String.from(name)
        lowered = lowered.toLower()
        switch lowered.toString()
        {
        case "monospace", "ui-monospace", "consolas", "menlo",
             "courier", "courier new", "cascadia mono", "cascadia code",
             "sfmono-regular", "dejavu sans mono", "liberation mono":
            result.kind    = .Mono
            result.matched = true
            return result

        case "serif", "ui-serif", "georgia", "times", "times new roman", "cambria", "garamond":
            result.kind    = .Serif
            result.matched = true
            return result

        case "sans-serif", "ui-sans-serif", "system-ui", "-apple-system", "segoe ui",
             "roboto", "arial", "helvetica", "helvetica neue", "inter", "noto sans":
            result.kind    = .Sans
            result.matched = true
            return result
        }

        if stop == scan.count do
            break
        scan = scan[stop + 1 until scan.count]
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
    if not Latin1.compare(text, "normal", ignoreCase: true) do
        return 0

    var pos = 0'u64
    if text.count == 0 or not isNumberStart(text[0]) do
        return 0

    let amount = scanNumber(text, &pos)
    while pos < text.count and text[pos] == ' ' do
        pos += 1
    if pos >= text.count do
        return amount

    let unit = text[pos until text.count]
    if unit[0] == '%' do
        return amount * 0.01 * fontSize
    if not Latin1.compare(unit, "em", ignoreCase: true) or not Latin1.compare(unit, "rem", ignoreCase: true) do
        return amount * fontSize
    return amount
}

private func normalizedText(value: string)->String
{
    var result: #returntype
    var pendingSpace = false
    for c in value
    {
        if c == ' ' or c == '\t' or c == '\r' or c == '\n'
        {
            pendingSpace = not result.isEmpty()
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

// The named-color search uses the alphabetical order of the reflected ARGB names.
private const ArgbNamesSorted = #run
{
    var previous = ""
    for entry in #typeof(Argb).values
    {
        let name = entry.name orelse ""
        if Latin1.compare(previous, name, ignoreCase: true) >= 0 do
            return false
        previous = name
    }

    return true
}

#assert(ArgbNamesSorted)

// Parses a solid paint value. Returns the color and whether painting is enabled.
private func parseColor(value: string)->{ color: Color, enabled: bool }
{
    var result: #returntype
    result.color   = Color.fromArgb(Argb.Black)
    result.enabled = true

    let text = Latin1.trim(value)

    if not Latin1.compare(text, "none", ignoreCase: true)
    {
        result.enabled = false
        return result
    }

    if not Latin1.compare(text, "transparent", ignoreCase: true)
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

    let isRgb  = len > 4 and not Latin1.compare(text[until 4], "rgb(", ignoreCase: true)
    let isRgba = len > 5 and not Latin1.compare(text[until 5], "rgba(", ignoreCase: true)
    if isRgb or isRgba
    {
        var pos = isRgba ? 5'u64 : 4'u64
        let r   = scanCssComponent(text, &pos, 255)
        let g   = scanCssComponent(text, &pos, 255)
        let b   = scanCssComponent(text, &pos, 255)
        let a   = isRgba ? scanCssComponent(text, &pos, 1) : 1.0
        result.color = Color.fromArgb(cast(u8, Math.round(a * 255)),
                                      cast(u8, Math.round(r)),
                                      cast(u8, Math.round(g)),
                                      cast(u8, Math.round(b)))
        return result
    }

    let isHsl  = len > 4 and not Latin1.compare(text[until 4], "hsl(", ignoreCase: true)
    let isHsla = len > 5 and not Latin1.compare(text[until 5], "hsla(", ignoreCase: true)
    if isHsl or isHsla
    {
        var pos = isHsla ? 5'u64 : 4'u64
        var hue = scanNumber(text, &pos)
        hue -= Math.floor(hue / 360) * 360
        let saturation = scanCssComponent(text, &pos, 1)
        let lightness  = scanCssComponent(text, &pos, 1)
        let alpha      = isHsla ? scanCssComponent(text, &pos, 1) : 1.0
        result.color   = Color.fromHsl(hue / 360, saturation, lightness)
        result.color.a = cast(u8, Math.round(alpha * 255))
        return result
    }

    let entries = #typeof(Argb).values
    var first   = 0'u64
    var end     = cast(u64, entries.count)
    while first < end
    {
        let middle = first + (end - first) / 2
        let entry  = &entries[middle]
        let order  = Latin1.compare(unwrap entry.name, text, ignoreCase: true)
        if order < 0
        {
            first = middle + 1
        }
        elif order > 0
        {
            end = middle
        }
        else
        {
            result.color = Color.fromArgb(cast(const *Argb, unwrap entry.value)[])
            break
        }
    }

    return result
}

private func parseDashPattern(value: string)->Array'SvgLength
{
    var result: #returntype
    var total:  f32
    let text = Latin1.trim(value)
    if not Latin1.compare(text, "none", ignoreCase: true) do
        return result

    var pos = 0'u64
    while pos < text.count
    {
        while pos < text.count and
              (text[pos] == ' ' or
               text[pos] == ',' or
               text[pos] == '\t' or
               text[pos] == '\n' or
               text[pos] == '\r') do
            pos += 1
        if pos >= text.count or not isNumberStart(text[pos]) do
            break

        var length = SvgLength{value: scanNumber(text, &pos)}
        if pos < text.count and text[pos] == '%'
        {
            length.value     *= 0.01
            length.isPercent = true
            pos += 1
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
        if paintId.count
        {
            state.fillPaintId = paintId
            state.hasFill     = true
        }
        else
        {
            state.fillPaintId = ""
            if not Latin1.compare(Latin1.trim(value), "currentColor", ignoreCase: true)
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
        if paintId.count
        {
            state.strokePaintId = paintId
            state.hasStroke     = true
        }
        else
        {
            state.strokePaintId = ""
            if not Latin1.compare(Latin1.trim(value), "currentColor", ignoreCase: true)
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
        if not Latin1.compare(Latin1.trim(value), "none", ignoreCase: true) do
            state.isDisplayed = false

    case "visibility":
        let visibility = Latin1.trim(value)
        state.isVisible = Latin1.compare(visibility, "hidden", ignoreCase: true) != 0 and
                          Latin1.compare(visibility, "collapse", ignoreCase: true) != 0

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
        state.fontSize = Math.max(parseLength(value, SvgLength{state.fontSize, false}).value, 1)

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
        state.forceBold = not Latin1.compare(weight, "bold", ignoreCase: true) or number >= 600

    case "font-style":
        let style = Latin1.trim(value)
        state.forceItalic = not Latin1.compare(style, "italic", ignoreCase: true) or not Latin1.compare(style, "oblique", ignoreCase: true)

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
        state.strokePattern = value

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
        while pos < len and
              (value[pos] == ' ' or
               value[pos] == ',' or
               value[pos] == '\t' or
               value[pos] == '\n' or
               value[pos] == '\r') do
            pos += 1

        let nameStart = pos
        while pos < len and ((value[pos] >= 'a' and value[pos] <= 'z') or (value[pos] >= 'A' and value[pos] <= 'Z')) do
            pos += 1
        let name = value[nameStart until pos]
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
            while look < len and
                  (value[look] == ' ' or
                   value[look] == ',' or
                   value[look] == '\t' or
                   value[look] == '\n' or
                   value[look] == '\r') do
                look += 1
            if look >= len or not isNumberStart(value[look]) do
                break
            arguments[count] = scanNumber(value, &pos)
            count += 1
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
            if count > 2 do
                step = Math.Transform2.createRotation(angle, arguments[1], arguments[2])
            else do
                step = Math.Transform2.createRotation(angle, 0, 0)

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

// Reads the next name/value pair and leaves the cursor on the following declaration.
private func nextStyleDeclaration(text: string, cursor: *u64)->StyleDeclaration
{
    while cursor[] < text.count
    {
        let start = cursor[]
        var end   = start
        while end < text.count and text[end] != ';' do
            end += 1
        cursor[] = end < text.count ? end + 1 : end

        var colon = start
        while colon < end and text[colon] != ':' do
            colon += 1
        if colon == end do
            continue

        let name = Latin1.trim(text[start until colon])
        if name.count do
            return {name: name, value: Latin1.trim(text[colon + 1 until end])}
    }

    return {name: "", value: ""}
}

private func applyAttribute(state: *GroupState, name, value: string)
{
    if name == "style"
    {
        var cursor = 0'u64
        while cursor < value.count
        {
            let declaration = nextStyleDeclaration(value, &cursor)
            if declaration.name.count do
                applyStyleProperty(state, declaration.name, declaration.value)
        }

        return
    }

    applyStyleProperty(state, name, value)
}

private func styleValue(style, property: string)->string
{
    var cursor = 0'u64
    while cursor < style.count
    {
        let declaration = nextStyleDeclaration(style, &cursor)
        if not Latin1.compare(declaration.name, property, ignoreCase: true) do
            return declaration.value
    }

    return ""
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
private func mapPoint(state: *GroupState, x, y: f32)->Vector2 => state.transform.transformPoint(Vector2{x, y})

// The single length scale a transform applies, as the square root of the area it multiplies.
//
// A stroke width, a dash length and a dash offset are one number in user units, and an
// anisotropic transform has no exact answer for them; this is the value SVG's own
// `stroke-width` resolves to under such a transform, and it reduces to the plain factor
// whenever the transform is uniform.
private func transformScale(transform: Math.Transform2)->f32
    => Math.sqrt(Math.abs(transform.m11 * transform.m22 - transform.m12 * transform.m21))

// Reports whether a transform keeps the axes and their directions, so a shape can be built
// from its raw axis-aligned primitive instead of from curves.
//
// A mirror keeps the axes but reverses one: the mapped origin becomes the far corner and an
// arc runs the other way, which a primitive measured with positive extents cannot state.
#[Swag.Inline]
private func isAxisAligned(transform: Math.Transform2)->bool
    => Math.isZeroEpsilon(transform.m12) and
       Math.isZeroEpsilon(transform.m21) and
       transform.m11 > 0 and
       transform.m22 > 0

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
        let scale  = state.transform.axisScale()
        path.arcTo(mapped.x, mapped.y, radii.x * scale.x, radii.y * scale.y, Math.Angle.fromRadians(angles.x), Math.Angle.fromRadians(angles.y))
        return
    }

    // The stored parameterization runs clockwise from the top of the ellipse.
    let sweepAngle = angles.y - angles.x
    let segCount   = cast(s32, Math.max(Math.ceil(Math.abs(sweepAngle) / (Math.ConstF32.Pi * 0.5)), 1.0))
    let segAngle   = sweepAngle / cast(f32, segCount)
    let k          = 4.0 / 3.0 * Math.tan(segAngle * 0.25)

    var angle = angles.x
    for segCount
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
        let scale  = state.transform.axisScale()
        path.setEllipseRaw(center.x, center.y, rx * scale.x, ry * scale.y)
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

    // Round double-precision angles to path precision. Platform atan2f approximations
    // can otherwise change the quarter-turn segment count and the resulting raster.
    let startAngle = cast(f32, Math.atan2(cast(f64, (py - cyp) / ry), cast(f64, (px - cxp) / rx)))
    let endAngle   = cast(f32, Math.atan2(cast(f64, (-py - cyp) / ry), cast(f64, (-px - cxp) / rx)))

    var sweepAngle = endAngle - startAngle
    if sweep and sweepAngle < 0 do
        sweepAngle += 2 * Math.ConstF32.Pi
    elif not sweep and sweepAngle > 0 do
        sweepAngle -= 2 * Math.ConstF32.Pi

    // Split into segments no larger than a quarter turn and emit each as a cubic.
    let segCount = cast(s32, Math.max(Math.ceil(Math.abs(sweepAngle) / (Math.ConstF32.Pi * 0.5)), 1.0))
    let segAngle = sweepAngle / cast(f32, segCount)
    let k        = 4.0 / 3.0 * Math.tan(segAngle * 0.25)

    var angle = startAngle
    for segCount
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

// Records the vertex a segment just reached, and the direction it left the previous one along.
private func addMarkerVertex(vertices: *Array'MarkerVertex?, point, inDir, previousOutDir: Vector2)
{
    if not vertices do
        return
    if vertices.count and (previousOutDir.x != 0 or previousOutDir.y != 0) do
        vertices[vertices.count - 1].outDir = previousOutDir
    vertices.add(MarkerVertex{point, inDir, Vector2{}})
}

// Parses one `d` attribute into subpath contours, transformed by `state`.
//
// `vertices` collects the authored vertices markers are placed on; pass null when the element
// carries none, which is the common case and skips the bookkeeping entirely.
private func parsePathData(list: *LinePathList, data: string, state: *GroupState, vertices: *Array'MarkerVertex? = null)
{
    let len = data.count
    var pos = 0'u64

    var cmd:        u8
    var curX, curY: f32     // Current point, user units.
    var begX, begY: f32     // Subpath start, user units.
    var ctlX, ctlY: f32     // Last cubic/quadratic control point, for S/T reflection.
    var lastCurve:  u8      // 'c' when the previous command was cubic-ish, 'q' for quadratic.

    var path:    *LinePath?
    var started: bool

    func number(data: string, pos: *u64, valid: *bool)->f32
    {
        if not valid[] do
            return 0

        let start = skipNumberSeparators(data, pos[])
        if start >= data.count or not isNumberStart(data[start])
        {
            valid[] = false
            return 0
        }

        pos[] = start
        return readNumber(data, pos)
    }

    func flag(data: string, pos: *u64, valid: *bool)->bool
    {
        if not valid[] do
            return false

        pos[] = skipNumberSeparators(data, pos[])
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
            case 'M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c',
                 'S', 's', 'Q', 'q', 'T', 't', 'A', 'a', 'Z', 'z':
                discard c

            default: return
            }

            cmd = c
            pos += 1
            if cmd == 'Z' or cmd == 'z'
            {
                if not path do
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
        elif not isNumberStart(c)
        {
            return
        }

        if not path and cmd != 'M' and cmd != 'm' do
            return

        let rel   = cmd >= 'a'
        var valid = true
        switch cmd
        {
        case 'M', 'm':
            var x = number(data, &pos, &valid)
            var y = number(data, &pos, &valid)
            if not valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            let start = mapPoint(state, x, y)
            path = list.newPath()
            path.start(start.x, start.y)
            addMarkerVertex(vertices, Vector2{x, y}, {}, {})
            started = true
            curX    = x
            curY    = y
            begX    = x
            begY    = y

            // Following coordinate pairs are implicit line-to commands.
            cmd = rel ? cast(u8, 'l') : cast(u8, 'L')

        case 'L', 'l':
            var x = number(data, &pos, &valid)
            var y = number(data, &pos, &valid)
            if not valid do
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
                addMarkerVertex(vertices, Vector2{x, y}, Vector2{x - curX, y - curY}, Vector2{x - curX, y - curY})
            }

            curX = x
            curY = y

        case 'H', 'h':
            var x = number(data, &pos, &valid)
            if not valid do
                return
            if rel do
                x += curX
            let target = mapPoint(state, x, curY)
            path!.lineTo(target.x, target.y)
            addMarkerVertex(vertices, Vector2{x, curY}, Vector2{x - curX, 0}, Vector2{x - curX, 0})
            curX = x

        case 'V', 'v':
            var y = number(data, &pos, &valid)
            if not valid do
                return
            if rel do
                y += curY
            let target = mapPoint(state, curX, y)
            path!.lineTo(target.x, target.y)
            addMarkerVertex(vertices, Vector2{curX, y}, Vector2{0, y - curY}, Vector2{0, y - curY})
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
            if not valid do
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
            addMarkerVertex(vertices, Vector2{x, y}, Vector2{x - c2x, y - c2y}, Vector2{c1x - curX, c1y - curY})
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
            if not valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            let target  = mapPoint(state, x, y)
            let control = mapPoint(state, c1x, c1y)
            path!.bezierTo(target.x, target.y, control.x, control.y)
            addMarkerVertex(vertices, Vector2{x, y}, Vector2{x - c1x, y - c1y}, Vector2{c1x - curX, c1y - curY})
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
            if not valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            appendArc(unwrap path, state, curX, curY, rx, ry, rotation, largeArc, sweepF, x, y)
            addMarkerVertex(vertices, Vector2{x, y}, Vector2{x - curX, y - curY}, Vector2{x - curX, y - curY})
            curX = x
            curY = y

        default:
            return
        }

        lastCurve = 0
    }
}

// Elements /////////////////////////////////////////////////////////////////////

// Dense solid fills can scan-convert their original winding directly, avoiding both the
// contour-containment walk and the triangulation of regions with thousands of holes.
private func usesScanFill(list: const *LinePathList, state: const *GroupState)->bool
{
    if not state.hasFill or
       state.hasStroke or
       state.inDefs or
       state.fillPaintId.count or
       state.filterId.count do
        return false
    if list.paths.count >= 512 do
        return true
    var segments = 0'u64
    for path in list.paths
    {
        segments += path.elements.count
        if segments >= 8192 do
            return true
    }

    return false
}

#[Swag.Inline]
private func(Candidates) containerCount(paths: const *LinePathList, probe: Vector2, excluded: u64, candidates: Candidates)->s32
{
    var depth = 0
    for j in candidates where j != excluded
    {
        if paths.paths[j].polygon.contains(probe) do
            depth += 1
    }

    return depth
}

#[Swag.Inline]
private func(Candidates) appendHoles(group: *LinePathList, paths: const *LinePathList,
                             depth: const [..] s32, root: u64, candidates: Candidates)
{
    let outer     = &paths.paths[root].polygon
    let holeDepth = depth[root] + 1
    for j in candidates where depth[j] == holeDepth
    {
        let path = paths.paths[j]
        if path.polygon.points.count and outer.contains(path.polygon.points[0]) do
            group.paths.add(path)
    }
}

private impl Parser
{
    mtd strokeDashes(value: string)->const *Array'SvgLength?
    {
        if not value.count do
            return null

        let key = .sourceView(value)
        if let existing = .dashPatterns.tryFind(key) do
            return &existing.value

        var parsed = parseDashPattern(key)

        // Keep the cache small even when every shape declares a different dash array.
        if .dashPatterns.count >= 64 or parsed.count > 64
        {
            .dashScratch = #move parsed
            return &.dashScratch
        }

        return &.dashPatterns.add(key, #move parsed).value
    }

    mtd emitShape(list: #move LinePathList, state: *GroupState)
    {
        if list.paths.isEmpty() do
            return
        if not state.drawsShape() do
            return

        // A triangulated fill needs one outer contour followed by its holes. Split separate islands
        // by containment depth, keeping the source order of both islands and holes.
        let scanFill = usesScanFill(&list, state)
        if state.hasFill and list.paths.count > 1 and not scanFill
        {
            var work  = #move list
            let count = work.paths.count
            for path in work.paths do
                path.flatten(.Normal)

            let indexed = count >= MinIndexedContours
            var index: ContourIndex
            if indexed do
                index.build(&work)

            var depth: Array's32
            depth.resize(count)
            for i in count
            {
                let points = &work.paths[i].polygon.points
                if points.isEmpty() do
                    continue

                let probe = points[0]
                if indexed do
                    depth[i] = containerCount(&work, probe, i, index.candidateContainers(probe))
                else do
                    depth[i] = containerCount(&work, probe, i, count)
            }

            var roots = 0
            for i in count where depth[i] % 2 == 0 do
                roots += 1

            if roots <= 1
            {
                .emitShapeOne(#move work, state)
                return
            }

            for i in count where depth[i] % 2 == 0
            {
                var group: LinePathList
                group.paths.add(work.paths[i])
                if indexed do
                    appendHoles(&group, &work, depth.toSlice(), i, index.candidateHoles(i))
                else do
                    appendHoles(&group, &work, depth.toSlice(), i, count)
                .emitShape(#move group, state)
            }

            // The group lists now own the path pointers.
            work.paths.clear()
            return
        }

        .emitShapeOne(#move list, state, scanFill)
    }

    mtd emitShapeOne(list: #move LinePathList, state: *GroupState, scanFill = false)
    {
        let shapeIndex = .drawing.shapes.count
        let shape      = .drawing.shapes.emplaceInitAddress()
        if scanFill
        {
            .drawing.scanFills.add(ScanFill{bounds: list.controlBounds()})
            shape.scanFill = .drawing.scanFills.count
        }

        shape.pathList = #move list
        shape.hidden   = state.inDefs

        shape.hasFill = state.hasFill
        if state.hasFill
        {
            shape.fillColor   = state.fillColor
            shape.fillPaintId = .internReference(state.fillPaintId)
            shape.fillOpacity = state.fillOpacity * state.opacity
            shape.evenOdd     = state.evenOdd
        }

        shape.hasStroke = state.hasStroke
        if state.hasStroke
        {
            shape.strokeColor   = state.strokeColor
            shape.strokePaintId = .internReference(state.strokePaintId)
            shape.strokeOpacity = state.strokeOpacity * state.opacity
            let geometryScale = transformScale(state.transform)
            shape.strokeWidth = state.strokeWidth * geometryScale
            let viewportDiagonal = Math.sqrt(.drawing.width * .drawing.width + .drawing.height * .drawing.height) / Math.ConstF32.Sqrt2
            shape.strokeOffset = (state.strokeOffset.isPercent ? state.strokeOffset.value * viewportDiagonal : state.strokeOffset.value) * geometryScale
            shape.strokeMiter  = state.strokeMiter
            if let dashes = .strokeDashes(state.strokePattern)
            {
                shape.strokePattern.reserve(dashes.count)
                for value in dashes
                {
                    let length = value.isPercent ? value.value * viewportDiagonal : value.value
                    shape.strokePattern.add(length * geometryScale)
                }
            }

            shape.capStyle  = state.capStyle
            shape.joinStyle = state.joinStyle
        }

        shape.paintTransform = state.transform
        shape.filterId       = .internReference(state.filterId)

        if not shape.hidden do
            .drawing.items.add(DrawingItem{.Shape, shapeIndex})
    }

    mtd emitRect(state: *GroupState, x, y, w, h, rx, ry: f32)
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
            let scale  = state.transform.axisScale()
            let sx     = scale.x
            let sy     = scale.y
            if crx > 0 and cry > 0 do
                path.setRoundRectRaw(origin.x, origin.y, w * sx, h * sy, crx * sx, cry * sy)
            else do
                path.setRectRaw(origin.x, origin.y, w * sx, h * sy)
        }
        else
        {
            appendRectContour(path, state, x, y, w, h, crx, cry)
        }

        .emitShape(#move list, state)
    }

    mtd emitEllipse(state: *GroupState, cx, cy, rx, ry: f32)
    {
        if rx <= 0 or ry <= 0 do
            return

        var list: LinePathList
        let path = list.newPath()
        appendEllipse(path, state, cx, cy, rx, ry)
        .emitShape(#move list, state)
    }

    mtd emitPoly(state: *GroupState, points: string, closeIt: bool)
    {
        let drawsPath  = state.drawsShape(strokeOnly: not closeIt)
        let hasMarkers = state.hasMarkers()
        if not drawsPath and not hasMarkers do
            return

        var list:     LinePathList
        var vertices: Array'MarkerVertex
        let path  = drawsPath ? list.newPath() : null
        var pos   = 0'u64
        var count = 0'u64

        while pos < points.count
        {
            var look = pos
            while look < points.count and (points[look] == ' ' or points[look] == ',') do
                look += 1
            if look >= points.count or not isNumberStart(points[look]) do
                break

            let x = scanNumber(points, &pos)
            let y = scanNumber(points, &pos)
            if path
            {
                let point = mapPoint(state, x, y)
                if not count do
                    path.start(point.x, point.y)
                else do
                    path.lineTo(point.x, point.y)
            }

            if hasMarkers
            {
                let point = Vector2{x, y}
                var direction: Vector2
                if count
                {
                    let previous = vertices.backPtr()
                    direction       = Vector2{x - previous.point.x, y - previous.point.y}
                    previous.outDir = direction
                }

                vertices.add(MarkerVertex{point, direction, Vector2{}})
            }

            count += 1
        }

        if path and count >= 2
        {
            if closeIt
            {
                path.close()
                .emitShape(#move list, state)
            }
            else
            {
                var strokeOnly = state[]
                strokeOnly.hasFill = false
                .emitShape(#move list, &strokeOnly)
            }
        }

        if hasMarkers do
            .applyMarkers(state, vertices.toSlice())
    }
}

private impl StyleSheet
{
    mtd add(selector, declarations: string)
    {
        switch selector[0]
        {
        case '.':
            if selector.count > 1 do
                .appendRule(&.byClass.findOrAdd(selector[1 to]).value, declarations)

        case '#':
            if selector.count > 1 do
                .appendRule(&.byId.findOrAdd(selector[1 to]).value, declarations)

        default:
            .appendRule(&.byTag.findOrAdd(String.toLower(selector)).value, declarations)
        }
    }

    mtd appendRule(list: *StyleRuleList, declarations: string)
    {
        let index = .rules.count
        if list.last == Swag.U64.Max do
            list.first = index
        else do
            .rules[list.last].next = index
        list.last = index

        let first  = .declarations.count
        var cursor = 0'u64
        while cursor < declarations.count
        {
            let declaration = nextStyleDeclaration(declarations, &cursor)
            if declaration.name.count do
                .declarations.add(declaration)
        }

        .rules.add(StyleRule{first: first, count: .declarations.count - first})
    }

    mtd const applyRule(rule: const *StyleRule, state: *GroupState)
    {
        for i in rule.first until rule.first + rule.count
        {
            let declaration = &.declarations[i]
            applyStyleProperty(state, declaration.name, declaration.value)
        }
    }

    mtd const applyRules(list: const *StyleRuleList, state: *GroupState)
    {
        var index = list.first
        while index != Swag.U64.Max
        {
            let rule = &.rules[index]
            .applyRule(rule, state)
            index = rule.next
        }
    }

    mtd applyClassRules(value: string, state: *GroupState)
    {
        .matchGeneration += 1
        .classMatches.clear()

        var classes      = value
        var matchedLists = 0'u64
        while classes.count
        {
            var end = 0'u64
            while end < classes.count and
                  classes[end] != ' ' and
                  classes[end] != '\t' and
                  classes[end] != '\n' and
                  classes[end] != '\r' do
                end += 1

            // A class may appear more than once on an element. Apply its rules once.
            let entry = .byClass.tryFind(classes[until end])
            if entry and entry.value.matchedIn != .matchGeneration
            {
                entry.value.matchedIn = .matchGeneration
                matchedLists += 1
                var index = entry.value.first
                while index != Swag.U64.Max
                {
                    .classMatches.add(index)
                    index = .rules[index].next
                }
            }

            if end == classes.count do
                break
            classes = Latin1.trim(classes[end to])
        }

        // Different classes have equal specificity; their rules follow stylesheet order.
        if matchedLists > 1 do
            .classMatches.sort()
        for index in .classMatches do
            .applyRule(&.rules[index], state)
    }

    mtd apply(elementName: string, geo: *AttributeMap, state: *GroupState)
    {
        // Apply the indexed rules in increasing selector specificity.
        if .byTag.count
        {
            if let rules = .byTag.tryFind(String.toLower(elementName)) do
                .applyRules(&rules.value, state)
        }

        if .byClass.count
        {
            if let classAttr = geo.tryFind(.Class) do
                .applyClassRules(classAttr.value, state)
        }

        if .byId.count
        {
            if let idAttr = geo.tryFind(.Id)
            {
                if let rules = .byId.tryFind(idAttr.value) do
                    .applyRules(&rules.value, state)
            }
        }
    }
}

private impl Parser
{
    // Returns an attribute value as a view into the SVG source.
    mtd const sourceView(value: string)->string
    {
        if not value.count do
            return ""
        let start = cast(u64, value.buffer - .text.buffer)
        return .text[start until start + value.count]
    }

    mtd internReference(value: string)->u64
    {
        if not value.count do
            return 0

        let name  = .sourceView(value)
        let entry = .referenceIds.findOrAdd(name)
        if not entry.value
        {
            .referenceNames.add(name)
            entry.value = .referenceNames.count
        }

        return entry.value
    }

    mtd skipUntil(c: u8)
    {
        let len = (.text).count
        if .pos >= len or .text[.pos] == c do
            return
        let end = Utf8.indexOf(.text, cast(rune, c), .pos)
        .pos = end == Swag.U64.Max ? len : end
    }

    mtd parseStyleSheet()
    {
        let contentStart = .pos
        var contentEnd   = .pos
        while contentEnd + 7 < (.text).count
        {
            if .text[contentEnd] == '<' and
               .text[contentEnd + 1] == '/' and
               not Latin1.compare(.text[contentEnd + 2 until contentEnd + 7], "style", ignoreCase: true) do
                break
            contentEnd += 1
        }

        let content = .text[contentStart until contentEnd]
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
            let selector = Latin1.trim(content[selectorStart until pos])
            pos += 1
            let declarationsStart = pos
            while pos < content.count and content[pos] != '}' do
                pos += 1
            if pos >= content.count do
                break

            if selector.count and selector[0] != '@' do
                .styles.add(selector, Latin1.trim(content[declarationsStart until pos]))
            pos += 1
        }

        .pos = contentEnd
        .skipUntil('>')
        if .pos < (.text).count do
            .pos += 1
    }

    mtd applyStyles(elementName: string, geo: *AttributeMap, state: *GroupState)
    {
        if .styles.rules.count do
            .styles.apply(elementName, geo, state)
        if let inlineStyle = geo.tryFind(.Style) do
            applyAttribute(state, "style", inlineStyle.value)
    }

    // Applies presentation attributes and collects slices of the remaining supported attributes.
    // Each nesting level reuses its map for siblings.
    mtd scanAttributes(state: *GroupState, geo: *AttributeMap)->{ selfClosed: bool }
    {
        geo.clear()

        var result: #returntype
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
                .pos += 1
                continue
            }

            if .text[.pos] == '>'
            {
                .pos += 1
                break
            }

            let nameStart = .pos
            while .pos < len and
                  .text[.pos] != '=' and
                  .text[.pos] != ' ' and
                  .text[.pos] != '>' and
                  .text[.pos] != '/' do
                .pos += 1
            let name = .text[nameStart until .pos]

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
            .skipUntil(quote)
            let value = .text[valueStart until .pos]
            .pos += 1

            let kind = attributeKind(name)
            switch kind
            {
            case .Unknown:
                applyAttribute(state, name, value)

            case .Style:
                geo.add(kind, value)
                applyAttribute(state, name, value)

            default:
                geo.add(kind, value)
            }
        }

        return result
    }

    mtd geoNumber(geo: *AttributeMap, kind: AttributeKind, defaultValue = 0.0'f32)->f32
    {
        let here = geo.tryFind(kind)
        if not here do
            return defaultValue
        var pos = 0'u64
        return scanNumber(here.value, &pos)
    }

    mtd geoLength(geo: *AttributeMap, kind: AttributeKind, defaultValue: SvgLength)->SvgLength
    {
        let here = geo.tryFind(kind)
        if not here do
            return defaultValue
        return parseLength(here.value, defaultValue)
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
        var geo: AttributeMap
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
            while .pos < len and
                  .text[.pos] != ' ' and
                  .text[.pos] != '>' and
                  .text[.pos] != '/' and
                  .text[.pos] != '\t' and
                  .text[.pos] != '\n' and
                  .text[.pos] != '\r' do
                .pos += 1
            let name = .text[nameStart until .pos]

            var state: GroupState
            let {selfClosed} = .scanAttributes(&state, &geo)
            if name == "stop"
            {
                var offset     = SvgLength{}
                let offsetAttr = geo.tryFind(.Offset)
                if offsetAttr do
                    offset = parseLength(offsetAttr.value)

                var color      = Color.fromArgb(Argb.Black)
                var colorValue = ""
                let colorAttr  = geo.tryFind(.StopColor)
                if colorAttr do
                    colorValue = colorAttr.value
                let style = geo.tryFind(.Style)
                if style
                {
                    let styled = styleValue(style.value, "stop-color")
                    if styled.count do
                        colorValue = styled
                }

                if colorValue.count do
                    color = parseColor(colorValue).color

                var opacity     = 1.0'f32
                let opacityAttr = geo.tryFind(.StopOpacity)
                if opacityAttr
                {
                    let parsed = parseLength(opacityAttr.value, {1, false})
                    opacity = Math.saturate(parsed.value)
                }

                if style
                {
                    let styled = styleValue(style.value, "stop-opacity")
                    if styled.count
                    {
                        let parsed = parseLength(styled, {1, false})
                        opacity = Math.saturate(parsed.value)
                    }
                }

                color.a = cast(u8, Math.round(cast(f32, color.a) * opacity))
                var normalizedOffset = Math.saturate(offset.value)
                if not gradient.stops.isEmpty() do
                    normalizedOffset = Math.max(normalizedOffset, gradient.stops.back().offset)
                gradient.stops.add(GradientStop{normalizedOffset, color})
            }

            if not selfClosed do
                try .parseGradientStops(gradient)
        }
    }

    mtd parseGradient(kind: GradientKind, geo: *AttributeMap, selfClosed: bool) fail
    {
        var gradient: Gradient

        // The reference is kept rather than followed: a document may name a gradient defined
        // further down, and only the finished document knows every identifier.
        var href = geo.tryFind(.Href)
        if not href do
            href = geo.tryFind(.XlinkHref)
        if href
        {
            var baseId = href.value
            if baseId.count and baseId[0] == '#' do
                baseId = baseId[1 until baseId.count]
            gradient.href = .sourceView(baseId)
        }

        gradient.kind = kind
        switch kind
        {
        case .Linear:
            gradient.x1 = .geoLength(geo, .X1, gradient.x1)
            gradient.y1 = .geoLength(geo, .Y1, gradient.y1)
            gradient.x2 = .geoLength(geo, .X2, gradient.x2)
            gradient.y2 = .geoLength(geo, .Y2, gradient.y2)

            gradient.specified.x1 = geo.tryFind(.X1) != null
            gradient.specified.y1 = geo.tryFind(.Y1) != null
            gradient.specified.x2 = geo.tryFind(.X2) != null
            gradient.specified.y2 = geo.tryFind(.Y2) != null

        case .Radial:
            gradient.cx = .geoLength(geo, .Cx, gradient.cx)
            gradient.cy = .geoLength(geo, .Cy, gradient.cy)
            gradient.r  = .geoLength(geo, .R, gradient.r)
            gradient.fx = .geoLength(geo, .Fx, gradient.cx)
            gradient.fy = .geoLength(geo, .Fy, gradient.cy)
            gradient.fr = .geoLength(geo, .Fr, gradient.fr)

            gradient.specified.cx = geo.tryFind(.Cx) != null
            gradient.specified.cy = geo.tryFind(.Cy) != null
            gradient.specified.r  = geo.tryFind(.R) != null
            gradient.specified.fx = geo.tryFind(.Fx) != null
            gradient.specified.fy = geo.tryFind(.Fy) != null
            gradient.specified.fr = geo.tryFind(.Fr) != null
        }

        let units = geo.tryFind(.GradientUnits)
        if units
        {
            gradient.userSpace       = units.value == "userSpaceOnUse"
            gradient.specified.units = true
        }

        let spread = geo.tryFind(.SpreadMethod)
        if spread
        {
            switch spread.value
            {
            case "repeat":  gradient.spread = .Repeat
            case "reflect": gradient.spread = .Mirror
            default:        gradient.spread = .Clamp
            }

            gradient.specified.spread = true
        }

        let transform = geo.tryFind(.GradientTransform)
        if transform
        {
            gradient.transform = composeTransformList(transform.value, Math.Transform2.Identity)
            gradient.specified.transform = true
        }

        if not selfClosed
        {
            gradient.stops.clear()
            try .parseGradientStops(&gradient)
            gradient.specified.stops = not gradient.stops.isEmpty()
        }

        let id = geo.tryFind(.Id)
        if id do
            .gradients.add(.sourceView(id.value), #move gradient)
    }

    mtd loadRaster(href: string)->u64 fail
    {
        let index = .drawing.rasterImages.count
        if Utf8.startsWith(href, "data:")
        {
            // Check the Base64 byte limit before hashing or decoding the URI.
            if (href.count / 4) * 3 > .options.maxImageBytes do
                fail Swag.SystemError{"embedded SVG image exceeds the configured byte limit"}

            let entry = .embeddedImages.findOrAdd(.sourceView(href))
            if entry.value do
                return entry.value - 1

            var raster = #move try Image.fromDataUri(href)
            .drawing.rasterImages.add(#move raster)
            entry.value = index + 1
            return index
        }

        if (.options.externalResourceRoot).count == 0 do
            fail Swag.SystemError{"external SVG image references are disabled"}
        if Path.isRooted(href) do
            fail Swag.SystemError{"absolute SVG image references are not allowed"}

        let combined = Path.combine(.options.externalResourceRoot, href)
        let fullPath = try Path.absolute(combined.toString())
        if not Env.isInsideDirectory(.options.externalResourceRoot, fullPath.toString()) do
            fail Swag.SystemError{"SVG image reference escapes its configured resource root"}
        let info = try File.info(fullPath.toString())
        if info.size > .options.maxImageBytes do
            fail Swag.SystemError{"external SVG image exceeds the configured byte limit"}
        var raster = #move try Image.load(fullPath.toString())
        .drawing.rasterImages.add(#move raster)
        return index
    }

    mtd emitImage(state: *GroupState, geo: *AttributeMap) fail
    {
        if not state.isDisplayed or not state.isVisible do
            return

        var href = geo.tryFind(.Href)
        if not href do
            href = geo.tryFind(.XlinkHref)
        if not href do
            return

        let width  = .geoNumber(geo, .Width)
        let height = .geoNumber(geo, .Height)
        if width <= 0 or height <= 0 do
            return

        let index = .drawing.images.count
        let item  = .drawing.images.emplaceInitAddress()
        item.rasterIndex = try .loadRaster(href.value)

        // The rectangle stays in user units and carries its transform, so a mirrored or turned
        // picture is painted through the same matrix as its siblings instead of being
        // flattened into an upright rectangle.
        item.rect      = Rectangle{.geoNumber(geo, .X), .geoNumber(geo, .Y), width, height}
        item.transform = state.transform
        item.opacity   = state.opacity
        if not state.inDefs do
            .drawing.items.add(DrawingItem{.Image, index})
    }

    // Loads, once per document, the typeface a family class resolves to.
    //
    // A machine that does not carry the configured serif or monospace file still has to
    // draw the text, so a family that cannot be loaded falls back to the default face
    // instead of failing the document; only a document with no usable face at all fails.
    mtd typeFaceFor(kind: FontFamilyKind)->*TypeFace fail
    {
        let slot = cast(u64, kind)
        if .typeFaces[slot] do
            return unwrap .typeFaces[slot]

        var fileName = .options.fontFileName
        switch kind
        {
        case .Sans:  break
        case .Serif: fileName = .options.serifFontFileName
        case .Mono:  fileName = .options.monoFontFileName
        }

        if fileName.count == 0 or not TypeFace.exists(fileName) do
            fileName = .options.fontFileName
        if fileName.count == 0 do
            fail Swag.SystemError{"SVG text requires a configured font file"}

        let face = try TypeFace.load(fileName)
        .typeFaces[slot] = face
        return face
    }

    mtd addTextRun(text: string, state: *GroupState, geo: *AttributeMap, block: *SvgText, first: bool) fail
    {
        if not state.isDisplayed or not state.isVisible or not state.hasFill do
            return

        let normalized = normalizedText(text)
        if normalized.isEmpty() do
            return

        let typeFace = try .typeFaceFor(state.fontFamily)

        let x   = geo.tryFind(.X)
        let y   = geo.tryFind(.Y)
        let dx  = .geoNumber(geo, .Dx)
        let dy  = .geoNumber(geo, .Dy)
        let run = block.runs.emplaceInitAddress()
        run.text     = #move normalized
        run.typeFace = typeFace
        run.hasX     = first or x != null
        run.hasY     = first or y != null
        let anchor = mapPoint(state, x ? .geoNumber(geo, .X) : 0, y ? .geoNumber(geo, .Y) : 0)
        let offset = state.transform.transformVector(Vector2{dx, dy})
        run.x  = anchor.x
        run.y  = anchor.y
        run.dx = offset.x
        run.dy = offset.y
        let scale = state.transform.axisScale()
        run.fontSize      = state.fontSize * scale.y
        run.letterSpacing = state.letterSpacing * scale.x
        run.wordSpacing   = state.wordSpacing * scale.x
        run.rotation      = transformRotation(state.transform)
        run.color         = state.fillColor
        run.opacity       = state.fillOpacity * state.opacity
        run.anchor        = state.textAnchor
        run.forceBold     = state.forceBold
        run.forceItalic   = state.forceItalic
    }

    mtd parseText(state: GroupState, geo: *AttributeMap, selfClosed: bool) fail
    {
        if selfClosed do
            return

        let len   = (.text).count
        var first = true
        var block:    SvgText
        var childGeo: AttributeMap
        while .pos < len
        {
            let textStart = .pos
            .skipUntil('<')
            if .pos > textStart
            {
                let content = .text[textStart until .pos]
                try .addTextRun(content, &state, geo, &block, first)
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
            while .pos < len and
                  .text[.pos] != ' ' and
                  .text[.pos] != '>' and
                  .text[.pos] != '/' and
                  .text[.pos] != '\t' and
                  .text[.pos] != '\n' and
                  .text[.pos] != '\r' do
                .pos += 1
            let name = .text[nameStart until .pos]

            var childState = state
            let {selfClosed: childClosed} = .scanAttributes(&childState, &childGeo)
            .applyStyles(name, &childGeo, &childState)
            if name != "tspan"
            {
                if not childClosed do
                    try .parseContent(childState)
                continue
            }

            let childStart = .pos
            .skipUntil('<')
            let childText = .text[childStart until .pos]
            try .addTextRun(childText, &childState, &childGeo, &block, first)
            first = false
            if not childClosed
            {
                .skipUntil('>')
                .pos += 1
            }
        }

        if block.runs.count and not state.inDefs
        {
            let index = .drawing.texts.count
            .drawing.texts.add(#move block)
            .drawing.items.add(DrawingItem{.Text, index})
        }
    }

    mtd parsePattern(state: GroupState, geo: *AttributeMap, selfClosed: bool) fail
    {
        let first        = .drawing.shapes.count
        var contentState = state
        contentState.inDefs = true
        if not selfClosed do
            try .parseContent(contentState)

        let id = geo.tryFind(.Id)
        if not id do
            return

        var pattern: Pattern
        pattern.first  = first
        pattern.count  = .drawing.shapes.count - first
        pattern.x      = .geoLength(geo, .X, {})
        pattern.y      = .geoLength(geo, .Y, {})
        pattern.width  = .geoLength(geo, .Width, {})
        pattern.height = .geoLength(geo, .Height, {})
        let units = geo.tryFind(.PatternUnits)
        pattern.userSpace = units != null and units.value == "userSpaceOnUse"
        .patterns.add(.internReference(id.value), #move pattern)
    }

    mtd parseFilter(geo: *AttributeMap, selfClosed: bool) fail
    {
        var filter: SvgFilter
        if not selfClosed
        {
            let len = (.text).count
            var attrs: AttributeMap
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
                while .pos < len and
                      .text[.pos] != ' ' and
                      .text[.pos] != '>' and
                      .text[.pos] != '/' and
                      .text[.pos] != '\t' and
                      .text[.pos] != '\n' and
                      .text[.pos] != '\r' do
                    .pos += 1
                let name = .text[nameStart until .pos]
                var state: GroupState
                let {selfClosed: childClosed} = .scanAttributes(&state, &attrs)

                var primitive: FilterPrimitive
                var keep = true
                switch name
                {
                case "feGaussianBlur":
                    primitive.kind   = .GaussianBlur
                    primitive.radius = Math.max(.geoNumber(&attrs, .StdDeviation), 0)

                case "feOffset":
                    primitive.kind = .Offset
                    primitive.x    = .geoNumber(&attrs, .Dx)
                    primitive.y    = .geoNumber(&attrs, .Dy)

                case "feDropShadow":
                    primitive.kind   = .DropShadow
                    primitive.x      = .geoNumber(&attrs, .Dx)
                    primitive.y      = .geoNumber(&attrs, .Dy)
                    primitive.radius = Math.max(.geoNumber(&attrs, .StdDeviation), 0)
                    let flood = attrs.tryFind(.FloodColor)
                    if flood do
                        primitive.color = parseColor(flood.value).color
                    let opacity = attrs.tryFind(.FloodOpacity)
                    if opacity do
                        primitive.color = primitive.color.withAlphaF32(Math.saturate(parseLength(opacity.value).value))

                default:
                    keep = false
                }

                if keep do
                    filter.primitives.add(primitive)
                if not childClosed do
                    try .parseContent(state)
            }
        }

        let id = geo.tryFind(.Id)
        if id do
            .filters.add(.internReference(id.value), #move filter)
    }

    // Parses the elements between the current position and the parent's close tag.
    mtd parseContent(parent: GroupState) fail
    {
        let len       = (.text).count
        var geo:    AttributeMap
        var scopes: Array'ElementScope
        var inherited = &parent
        while .pos < len
        {
            .skipUntil('<')
            if .pos >= len do
                break
            .pos += 1
            if .pos >= len do
                break

            if .text[.pos] == '/'
            {
                .skipUntil('>')
                .pos += 1
                if scopes.isEmpty() do
                    return
                .closeScope(&scopes)
                inherited = scopes.isEmpty() ? &parent : &scopes.backPtr().state
                continue
            }

            // Declarations and comments.
            if .text[.pos] == '?' or .text[.pos] == '!'
            {
                .skipUntil('>')
                .pos += 1
                continue
            }

            let nameStart = .pos
            while .pos < len and
                  .text[.pos] != ' ' and
                  .text[.pos] != '>' and
                  .text[.pos] != '/' and
                  .text[.pos] != '\t' and
                  .text[.pos] != '\n' and
                  .text[.pos] != '\r' do
                .pos += 1
            let name = .text[nameStart until .pos]

            var state = inherited[]

            // The property is not inherited. Ancestor clips are applied to the completed
            // subtree below, after any clip that a descendant declares for itself.
            state.clipPathId = ""
            let {selfClosed} = .scanAttributes(&state, &geo)
            .applyStyles(name, &geo, &state)

            // A clip is stated in the user space of the element that names it, and children may
            // add transforms of their own; remembering that space here is what keeps an
            // inherited clip where the group put it.
            if state.clipPathId.count do
                state.clipTransform = state.transform

            let firstShape = .drawing.shapes.count
            let firstItem  = .drawing.items.count
            var isSvg, consumedChildren: bool

            switch name
            {
            case "svg":
                let isRoot = .svgDepth == 0
                .svgDepth += 1
                isSvg     = true
                if isRoot
                {
                    if let width = geo.tryFind(.Width) do
                        .drawing.imageSize.x = parseImageLength(width.value)
                    if let height = geo.tryFind(.Height) do
                        .drawing.imageSize.y = parseImageLength(height.value)
                    let vb = geo.tryFind(.ViewBox)
                    if vb
                    {
                        var pos   = 0'u64
                        let viewX = scanNumber(vb.value, &pos)
                        let viewY = scanNumber(vb.value, &pos)
                        .drawing.width  = scanNumber(vb.value, &pos)
                        .drawing.height = scanNumber(vb.value, &pos)
                        state.transform = prependTranslation(state.transform, -viewX, -viewY)
                    }
                    else
                    {
                        .drawing.width  = .geoNumber(&geo, .Width, 0)
                        .drawing.height = .geoNumber(&geo, .Height, 0)
                    }

                    if .dimensionsOnly do
                        return
                }
                else
                {
                    state.transform = prependTranslation(state.transform, .geoNumber(&geo, .X), .geoNumber(&geo, .Y))
                }

            case "g", "a":
                break

            case "path":
                let d = geo.tryFind(.D)
                let hasMarkers = state.hasMarkers()
                if d and (state.drawsShape() or hasMarkers)
                {
                    var list:     LinePathList
                    var vertices: Array'MarkerVertex
                    parsePathData(&list, d.value, &state, hasMarkers ? &vertices : null)
                    .emitShape(#move list, &state)
                    if hasMarkers do
                        .applyMarkers(&state, vertices.toSlice())
                }

            case "rect":
                var rx = .geoNumber(&geo, .Rx, -1)
                var ry = .geoNumber(&geo, .Ry, -1)
                if rx < 0 do
                    rx = ry
                if ry < 0 do
                    ry = rx
                .emitRect(&state,
                          .geoNumber(&geo, .X),
                          .geoNumber(&geo, .Y),
                          .geoNumber(&geo, .Width),
                          .geoNumber(&geo, .Height),
                          Math.max(rx, 0),
                          Math.max(ry, 0))

            case "circle":
                let r = .geoNumber(&geo, .R)
                .emitEllipse(&state, .geoNumber(&geo, .Cx), .geoNumber(&geo, .Cy), r, r)

            case "ellipse":
                .emitEllipse(&state,
                             .geoNumber(&geo, .Cx),
                             .geoNumber(&geo, .Cy),
                             .geoNumber(&geo, .Rx),
                             .geoNumber(&geo, .Ry))

            case "line":
                let drawsLine  = state.drawsShape(strokeOnly: true)
                let hasMarkers = state.hasMarkers()
                if drawsLine or hasMarkers
                {
                    let x1 = .geoNumber(&geo, .X1)
                    let y1 = .geoNumber(&geo, .Y1)
                    let x2 = .geoNumber(&geo, .X2)
                    let y2 = .geoNumber(&geo, .Y2)
                    if drawsLine
                    {
                        var list: LinePathList
                        let path   = list.newPath()
                        let from   = mapPoint(&state, x1, y1)
                        let target = mapPoint(&state, x2, y2)
                        path.start(from.x, from.y)
                        path.lineTo(target.x, target.y)
                        var strokeOnly = state
                        strokeOnly.hasFill = false
                        .emitShape(#move list, &strokeOnly)
                    }

                    if hasMarkers
                    {
                        let direction = Vector2{x2 - x1, y2 - y1}
                        let vertices  = [MarkerVertex{Vector2{x1, y1}, Vector2{}, direction},
                                         MarkerVertex{Vector2{x2, y2}, direction, Vector2{}}]
                        .applyMarkers(&state, vertices)
                    }
                }

            case "defs":
                consumedChildren = true

                // Definitions are parsed in local coordinates and withheld from
                // painting; `use` elements instantiate them.
                var defState: GroupState
                defState.inDefs = true
                if not selfClosed do
                    try .parseContent(defState)

            case "clipPath":
                consumedChildren = true

                // A clip is geometry, not paint: its children are parsed in their own
                // coordinates and kept out of the paint order, and every element that names the
                // clip instantiates a copy under its own transform.
                var clipState: GroupState
                clipState.inDefs = true
                let clipFirst = .drawing.shapes.count
                if not selfClosed do
                    try .parseContent(clipState)

                let clipId = geo.tryFind(.Id)
                if clipId and .drawing.shapes.count > clipFirst do
                    .clipPaths.add(.sourceView(clipId.value), {first: clipFirst, count: .drawing.shapes.count - clipFirst})

            case "symbol":
                consumedChildren = true

                // A symbol is a definition with a viewport. Its children are parsed like any
                // other definition, and the view box it declares is what a `use` fits into the
                // size it asks for.
                var symbolState: GroupState
                symbolState.inDefs = true
                let symbolFirst = .drawing.shapes.count
                if not selfClosed do
                    try .parseContent(symbolState)

                let symbolId = geo.tryFind(.Id)
                if symbolId and .drawing.shapes.count > symbolFirst
                {
                    let id = .sourceView(symbolId.value)
                    .defs.add(id, {first: symbolFirst, count: .drawing.shapes.count - symbolFirst})

                    var viewport: SymbolViewport
                    let box = geo.tryFind(.ViewBox)
                    if box
                    {
                        var boxPos = 0'u64
                        viewport.viewX      = scanNumber(box.value, &boxPos)
                        viewport.viewY      = scanNumber(box.value, &boxPos)
                        viewport.viewWidth  = scanNumber(box.value, &boxPos)
                        viewport.viewHeight = scanNumber(box.value, &boxPos)
                        viewport.hasViewBox = true
                    }

                    .symbols.add(id, viewport)
                }

            case "marker":
                consumedChildren = true

                // A marker is a definition with its own viewport and its own orientation rule.
                // Its children are parsed in that viewport's coordinates and kept out of the
                // paint order; the elements that reference it place copies on their vertices.
                var markerState: GroupState
                markerState.inDefs = true
                let markerFirst = .drawing.shapes.count
                if not selfClosed do
                    try .parseContent(markerState)

                let markerId = geo.tryFind(.Id)
                if markerId and .drawing.shapes.count > markerFirst do
                    .markers.add(.sourceView(markerId.value), .readMarkerDefinition(&geo, markerFirst, .drawing.shapes.count - markerFirst))

            case "linearGradient":
                consumedChildren = true
                try .parseGradient(.Linear, &geo, selfClosed)

            case "radialGradient":
                consumedChildren = true
                try .parseGradient(.Radial, &geo, selfClosed)

            case "pattern":
                consumedChildren = true
                try .parsePattern(state, &geo, selfClosed)

            case "filter":
                consumedChildren = true
                try .parseFilter(&geo, selfClosed)

            case "style":
                consumedChildren = true
                if not selfClosed do
                    .parseStyleSheet()

            case "text":
                consumedChildren = true
                try .parseText(state, &geo, selfClosed)

            case "image":
                try .emitImage(&state, &geo)

            case "use":
                var href = geo.tryFind(.Href)
                if not href do
                    href = geo.tryFind(.XlinkHref)
                if href
                {
                    var target = href.value
                    if target.count and target[0] == '#' do
                        target = target[1 until target.count]
                    let here = .defs.tryFind(target)
                    if here
                    {
                        var useState = state
                        useState.transform = prependTranslation(state.transform, .geoNumber(&geo, .X), .geoNumber(&geo, .Y))

                        // A referenced `symbol` brings its own viewport: its view box is fitted
                        // into the width and height the instance states, which is what makes one
                        // symbol usable at several sizes.
                        let symbol = .symbols.tryFind(target)
                        if symbol and symbol.value.hasViewBox
                        {
                            let width  = .geoNumber(&geo, .Width, symbol.value.viewWidth)
                            let height = .geoNumber(&geo, .Height, symbol.value.viewHeight)
                            if symbol.value.viewWidth > 0 and
                               symbol.value.viewHeight > 0 and
                               width > 0 and
                               height > 0
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

            case "polygon", "polyline":
                let pts = geo.tryFind(.Points)
                if pts do
                    .emitPoly(&state, pts.value, name == "polygon")
            }

            if not selfClosed and not consumedChildren
            {
                if .dimensionsOnly
                {
                    try .parseContent(state)
                }
                else
                {
                    let frame = scopes.emplaceInitAddress()
                    frame.state        = #move state
                    frame.firstShape   = firstShape
                    frame.firstItem    = firstItem
                    frame.pathLength   = .geoNumber(&geo, .PathLength, -1)
                    frame.definitionId = .elementDefinitionId(&frame.state, &geo)
                    frame.isSvg        = isSvg
                    inherited          = &frame.state
                    continue
                }
            }

            if isSvg do
                .svgDepth -= 1
            .finishElement(&state, firstShape, firstItem, .geoNumber(&geo, .PathLength, -1), .elementDefinitionId(&state, &geo))
        }

        // As before, end of input completes any open scopes from the innermost out.
        while not scopes.isEmpty() do
            .closeScope(&scopes)
    }

    mtd closeScope(scopes: *Array'ElementScope)
    {
        let frame = scopes.backPtr()
        if frame.isSvg do
            .svgDepth -= 1
        .finishElement(&frame.state, frame.firstShape, frame.firstItem, frame.pathLength, frame.definitionId)
        scopes.removeBack()
    }

    mtd const elementDefinitionId(state: const *GroupState, geo: const *AttributeMap)->string?
    {
        if state.inDefs do
            if let id = geo.tryFind(.Id) do
                return .sourceView(id.value)
        return null
    }

    mtd finishElement(state: *GroupState, firstShape, firstItem: u64, pathLength: f32, definitionId: string?)
    {
        if .drawing.shapes.count > firstShape
        {
            let count = .drawing.shapes.count - firstShape
            if pathLength > 0 do
                .applyPathLength(firstShape, count, pathLength, transformScale(state.transform))

            // Register the shapes a defs child emitted under its id.
            if definitionId != null do
                .defs.add(.sourceView(definitionId), {first: firstShape, count: count})
        }

        .applyClipPath(state, firstItem)
    }

    // Reads a `marker` element's viewport, reference point and orientation rule.
    mtd readMarkerDefinition(geo: *AttributeMap, first, count: u64)->MarkerDefinition
    {
        var result: #returntype
        result.first  = first
        result.count  = count
        result.refX   = .geoNumber(geo, .RefX)
        result.refY   = .geoNumber(geo, .RefY)
        result.width  = .geoNumber(geo, .MarkerWidth, 3)
        result.height = .geoNumber(geo, .MarkerHeight, 3)

        let units = geo.tryFind(.MarkerUnits)
        if units do
            result.scaleWithWidth = units.value != "userSpaceOnUse"

        let box = geo.tryFind(.ViewBox)
        if box
        {
            var boxPos = 0'u64
            result.viewX      = scanNumber(box.value, &boxPos)
            result.viewY      = scanNumber(box.value, &boxPos)
            result.viewWidth  = scanNumber(box.value, &boxPos)
            result.viewHeight = scanNumber(box.value, &boxPos)
            result.hasViewBox = true
        }

        let orient = geo.tryFind(.Orient)
        if orient
        {
            let text = Latin1.trim(orient.value)
            if not Latin1.compare(text, "auto-start-reverse", ignoreCase: true)
            {
                result.orientAuto         = true
                result.orientStartReverse = true
            }
            elif not Latin1.compare(text, "auto", ignoreCase: true)
            {
                result.orientAuto = true
            }
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
        if not vertices.count or not state.hasMarkers() do
            return

        for vertex, index in vertices
        {
            let isStart = index == 0
            var id      = state.markerMidId
            if isStart do
                id = state.markerStartId
            elif index == vertices.count - 1 do
                id = state.markerEndId
            if not id.count do
                continue

            let definition = .markers.tryFind(id)
            if not definition or definition.value.count == 0 do
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

            let reference = placement.transformPoint(Vector2{definition.refX, definition.refY})
            placement.multiply(Math.Transform2.createTranslation(-reference.x, -reference.y))
        }
        else
        {
            placement = Math.Transform2.createTranslation(-definition.refX, -definition.refY)
        }

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
        if state.inDefs or not state.clipPathId.count or .drawing.items.count == firstItem do
            return

        let definition = .clipPaths.tryFind(state.clipPathId)
        if not definition or definition.value.count == 0 do
            return

        var clipState: GroupState
        clipState.transform = state.clipTransform
        let clip = .instantiate(definition.value.first, definition.value.count, &clipState, hidden: true)
        if clip.count == 0 do
            return

        var intersections: HashTable'(u64, u64)
        for i in .drawing.items.count - firstItem
        {
            let item = &.drawing.items[firstItem + i]
            if item.clipCount
            {
                let previous = item.clipFirst
                let found    = intersections.tryFind(previous)
                if found
                {
                    item.clipFirst = found.value
                }
                else
                {
                    var inner = .clipGeometry(item.clipFirst, item.clipCount)
                    var outer = .clipGeometry(clip.first, clip.count)
                    inner.intersect(&outer)
                    var shape: Shape
                    shape.pathList = #move inner
                    shape.hidden   = true
                    item.clipFirst = .drawing.shapes.count
                    .drawing.shapes.add(#move shape)
                    intersections.add(previous, item.clipFirst)
                }

                // An empty intersection is still a clip; zero would mean unbounded ink.
                item.clipCount = 1
                continue
            }

            item.clipFirst = clip.first
            item.clipCount = clip.count
        }
    }

    // Normalize each clip shape before unioning its contours, so independently authored
    // winding directions do not turn overlapping clip shapes into holes.
    mtd clipGeometry(first, count: u64)->LinePathList
    {
        var result: #returntype
        for index in first until first + count
        {
            var shape = .drawing.shapes[index].pathList
            shape.flatten(.High)
            shape.clean(.drawing.shapes[index].evenOdd ? .EvenOdd : .NonZero)
            for path in shape.paths do
                result.newPath()[] = path[]
        }

        return result
    }

    mtd shapeBounds(shape: const *Shape)->{ min, max: Vector2 }
    {
        var result: #returntype
        result.min = Vector2.Max
        result.max = Vector2.Min
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
            return shape.paintTransform.transformPoint(gradient.transform.transformPoint(Vector2{px, py}))

        // An object-bounding-box stop is a fraction of the shape's extent, and the gradient
        // transform applies in that unit square before it is stretched back over the bounds.
        let unit = gradient.transform.transformPoint(Vector2{(px - boundsMin.x) / Math.max(boundsSize.x, 0.000001), (py - boundsMin.y) / Math.max(boundsSize.y, 0.000001)})
        return Vector2{boundsMin.x + unit.x * boundsSize.x, boundsMin.y + unit.y * boundsSize.y}
    }

    mtd gradientBrush(gradient: const *Gradient, shape: const *Shape)->Brush
    {
        if gradient.stops.isEmpty() do
            return Brush.createSolid(Color.fromArgb(Argb.Zero))

        let {min, max} = .shapeBounds(shape)
        let size       = max - min

        var result: #returntype
        result.color = Color.fromArgb(Argb.White)
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

        // Parsing already clamps the offsets and keeps them in nondecreasing order.
        result.gradientStops = gradient.stops
        return result
    }

    // Fills every gradient's unstated attributes from the chain of gradients it references.
    //
    // The chain is followed after the whole document is read, so a gradient may name one defined
    // further down, and it is bounded: a reference that loops back on itself stops contributing
    // instead of hanging, and a reference to nothing leaves the gradient with its own values.
    mtd resolveGradientInheritance()
    {
        const MaxInheritanceDepth = 16'u64

        // Values can be edited in slot order while the keys and table capacity stay fixed.
        let lookup: const *HashTable'(string, Gradient) = &.gradients
        for &id, resolved in .gradients where resolved.href.count and resolved.href != id[]
        {
            var visited: StaticArray'(const *Gradient?, MaxInheritanceDepth + 1)
            visited.add(resolved)

            var current = resolved.href
            while current.count and visited.count <= MaxInheritanceDepth
            {
                let base = lookup.tryFind(current)
                if not base do
                    break

                let from = &base.value
                if visited.contains(from) do
                    break
                visited.add(from)

                if not resolved.specified.x1
                {
                    resolved.x1 = from.x1
                    resolved.specified.x1 = from.specified.x1
                }

                if not resolved.specified.y1
                {
                    resolved.y1 = from.y1
                    resolved.specified.y1 = from.specified.y1
                }

                if not resolved.specified.x2
                {
                    resolved.x2 = from.x2
                    resolved.specified.x2 = from.specified.x2
                }

                if not resolved.specified.y2
                {
                    resolved.y2 = from.y2
                    resolved.specified.y2 = from.specified.y2
                }

                if not resolved.specified.cx
                {
                    resolved.cx = from.cx
                    resolved.specified.cx = from.specified.cx
                }

                if not resolved.specified.cy
                {
                    resolved.cy = from.cy
                    resolved.specified.cy = from.specified.cy
                }

                if not resolved.specified.r
                {
                    resolved.r = from.r
                    resolved.specified.r = from.specified.r
                }

                if not resolved.specified.fx
                {
                    resolved.fx = from.fx
                    resolved.specified.fx = from.specified.fx
                }

                if not resolved.specified.fy
                {
                    resolved.fy = from.fy
                    resolved.specified.fy = from.specified.fy
                }

                if not resolved.specified.fr
                {
                    resolved.fr = from.fr
                    resolved.specified.fr = from.specified.fr
                }

                if not resolved.specified.units
                {
                    resolved.userSpace       = from.userSpace
                    resolved.specified.units = from.specified.units
                }

                if not resolved.specified.spread
                {
                    resolved.spread = from.spread
                    resolved.specified.spread = from.specified.spread
                }

                if not resolved.specified.transform
                {
                    resolved.transform = from.transform
                    resolved.specified.transform = from.specified.transform
                }

                if not resolved.specified.stops and from.stops.count
                {
                    resolved.stops = from.stops
                    resolved.specified.stops = true
                }

                current = from.href
            }
        }
    }

    mtd storeGradient(gradient: *Gradient, shape: *Shape, opacity: f32)->u64
    {
        shape.pathList.flatten(.Normal)

        // User-space coordinates depend on the transform, independently of the shape bounds.
        if gradient.userSpace and
           gradient.cachedBrush and
           gradient.cachedOpacity == opacity and
           Memory.compare(&gradient.cachedTransform, &shape.paintTransform, #sizeof(Math.Transform2)) == 0 do
            return gradient.cachedBrush

        var brush = .gradientBrush(gradient, shape)
        brush.multiplyOpacity(opacity)
        .drawing.gradientBrushes.add(#move brush)
        let index = .drawing.gradientBrushes.count
        if gradient.userSpace
        {
            gradient.cachedBrush     = index
            gradient.cachedTransform = shape.paintTransform
            gradient.cachedOpacity   = opacity
        }

        return index
    }

    mtd resolvePaints()
    {
        func applyOpacity(color: Color, opacity: f32)->Color
        {
            return color.withAlphaF32((cast(f32, color.a) / 255.0) * Math.saturate(opacity))
        }

        for &shape in .drawing.shapes
        {
            if shape.hasFill
            {
                if not shape.fillPaintId do
                    shape.fillColor = applyOpacity(shape.fillColor, shape.fillOpacity)
                elif let gradient = .gradients.tryFind(.referenceNames[shape.fillPaintId - 1]) do
                    shape.fillGradient = .storeGradient(&gradient.value, shape, shape.fillOpacity)
                elif .patterns.tryFind(shape.fillPaintId) do
                    shape.fillColor = applyOpacity(Color.fromArgb(Argb.White), shape.fillOpacity)
                else do
                    shape.hasFill = false
            }

            if shape.hasStroke
            {
                if not shape.strokePaintId do
                    shape.strokeColor = applyOpacity(shape.strokeColor, shape.strokeOpacity)
                elif let gradient = .gradients.tryFind(.referenceNames[shape.strokePaintId - 1]) do
                    shape.strokeGradient = .storeGradient(&gradient.value, shape, shape.strokeOpacity)
                else do
                    shape.hasStroke = false
            }
        }
    }

    // Appends transformed copies of a definition's shapes and reports the range they occupy.
    //
    // `state` carries the complete transform the copies are placed under, so a `use` offset, a
    // `symbol` viewport and a clip reference all reach here the same way. `hidden` withholds the
    // copies from the paint order, which is what a clip needs: its shapes exist as geometry and
    // are never drawn.
    mtd instantiate(first, count: u64, state: *GroupState, hidden = false)->{ first: u64, count: u64 }
    {
        var result: #returntype
        result.first = .drawing.shapes.count

        for i in count
        {
            // Build the transformed copy fully before appending: appending can
            // reallocate the array and invalidate the source borrow.
            var list:                        LinePathList
            var fillColor, strokeColor:      Color
            var fillPaintId, strokePaintId, filterId: u64
            var fillOpacity, strokeOpacity:  f32
            var hasFill, hasStroke, evenOdd: bool
            var strokeWidth, strokeOffset:   f32
            var strokeMiter:                 f32
            var strokePattern:               Array'f32
            var capStyle:                    LineCapStyle = None
            var joinStyle:                   JoinStyle    = Miter
            var paintTransform:              Math.Transform2

            scope
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
                            Swag.assert(false, "definition uses an unsupported segment type")
                        }
                    }

                    if srcPath.isClosed do
                        path.close()
                }
            }

            let shapeIndex = .drawing.shapes.count
            with let shape = .drawing.shapes.emplaceInitAddress()
            {
                .pathList       = #move list
                .fillColor      = fillColor
                .fillPaintId    = fillPaintId
                .fillOpacity    = fillOpacity
                .strokeColor    = strokeColor
                .strokePaintId  = strokePaintId
                .strokeOpacity  = strokeOpacity
                .hasFill        = hasFill
                .hasStroke      = hasStroke
                .evenOdd        = evenOdd
                .strokeWidth    = strokeWidth
                .strokeOffset   = strokeOffset
                .strokeMiter    = strokeMiter
                .strokePattern  = #move strokePattern
                .capStyle       = capStyle
                .joinStyle      = joinStyle
                .paintTransform = paintTransform
                .hidden         = hidden or state.inDefs
                .filterId       = filterId
            }

            if not shape.hidden do
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
        var result: #returntype = .pathList.controlBounds()
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

// Parses the root viewport's natural image size in CSS pixels without decoding its contents.
//
// The same width, height and view-box rules as [[Pixel.Svg.Drawing.naturalSize]] apply.
// Missing, nonpositive, or unrepresentable natural dimensions fail. Child elements and their
// resources are deliberately not validated; use [[Pixel.Svg.Drawing.parse]] to prepare the complete drawing.
func parseImageSize(text: string)->Vector2 fail
{
    var drawing: Drawing
    var parser = Parser{text: text, drawing: &drawing, dimensionsOnly: true}
    var root:    GroupState
    try parser.parseContent(root)
    if drawing.width <= 0 or drawing.height <= 0 do
        fail Swag.SystemError{"SVG document has no valid dimensions"}
    let size = drawing.naturalSize()
    if not validNaturalSize(size) do
        fail Swag.SystemError{"SVG document has no finite image size"}
    return size
}

private func validNaturalSize(size: Vector2)->bool =>
    size.x > 0 and size.y > 0 and Math.isFinite(size.x) and Math.isFinite(size.y)

impl Drawing
{
    // Returns the number of parsed shapes.
    mtd const shapeCount()->u64 => .shapes.count

    // Returns the preferred image dimensions in CSS pixels.
    //
    // Absolute root `width` and `height` attributes determine this size. A missing or relative
    // dimension is inferred from the other dimension and the view-box aspect ratio; if neither
    // dimension is absolute, the view-box size is returned. Nonpositive dimensions are treated
    // as unspecified. This query does not change the user-space coordinates used by
    // [[Pixel.Svg.Drawing.paint]] and [[Pixel.Svg.Drawing.rasterize]].
    mtd const naturalSize()->Vector2
    {
        if .imageSize.x > 0 and .imageSize.y > 0 do
            return .imageSize
        if .imageSize.x > 0 and .width > 0 do
            return Vector2{.imageSize.x,
                           cast(f32, cast(f64, .imageSize.x) * cast(f64, .height) / cast(f64, .width))}
        if .imageSize.y > 0 and .height > 0 do
            return Vector2{cast(f32, cast(f64, .imageSize.y) * cast(f64, .width) / cast(f64, .height)),
                           .imageSize.y}
        return Vector2{.width, .height}
    }

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
    // Missing, nonpositive, or unrepresentable natural dimensions fail.
    //
    // `options` confines external image references and selects the typefaces for text;
    // see [[Pixel.Svg.ParseOptions]]. Unknown elements and attributes are ignored.
    func parse(text: string, options: ParseOptions = {})->Drawing fail
    {
        var result: #returntype

        var parser = Parser{text: text, drawing: &result, options: options}

        var root: GroupState
        try parser.parseContent(root)
        parser.resolveGradientInheritance()
        parser.resolvePaints()
        result.patterns = #move parser.patterns
        result.filters  = #move parser.filters

        if result.width <= 0 or result.height <= 0 do
            fail Swag.SystemError{"SVG document has no valid dimensions"}
        if not validNaturalSize(result.naturalSize()) do
            fail Swag.SystemError{"SVG document has no finite image size"}

        result.measureItems()
        result.measurePaintBlocks()
        result.measurePaintBins()
        return result
    }

    // Records what each item can ink, so painting can reject the ones a viewport misses.
    //
    // Shapes and pictures are bounded from the geometry the parser produced. A text block is
    // left unmeasured: its runs are placed by the advances of the runs before them, which only
    // shaping can give, so the first paint measures it and every later one rejects it.
    private mtd measureItems()
    {
        var clipFirst, clipCount: u64
        var clipBounds: Rectangle
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
                let image = &.images[item.index]
                item.bounds    = image.transform.transformBounds(image.rect)
                item.hasBounds = true

            case .Text:
                break
            }

            if item.hasBounds and item.clipCount
            {
                // A group can apply the same complex clip to every one of its children.
                if item.clipFirst != clipFirst or item.clipCount != clipCount
                {
                    clipFirst  = item.clipFirst
                    clipCount  = item.clipCount
                    clipBounds = .clipRangeBounds(clipFirst, clipCount)
                }

                item.bounds.intersect(clipBounds)
            }
        }
    }

    private mtd const measurePaintBlock(first: u64)->PaintBlock
    {
        let end = first + Math.min(PaintBlockSize, .items.count - first)
        var result: #returntype = {minimum: Vector2.Max, maximum: Vector2.Min, bounded: true}
        for i in first until end
        {
            let item = &.items[i]
            if not item.hasBounds do
                return {}

            let corner   = Vector2{item.bounds.x, item.bounds.y}
            let opposite = Vector2{item.bounds.right(), item.bounds.bottom()}
            if not finitePoint(corner) or not finitePoint(opposite) do
                return {}
            result.minimum = Vector2.min(result.minimum, Vector2.min(corner, opposite))
            result.maximum = Vector2.max(result.maximum, Vector2.max(corner, opposite))
        }

        return result
    }

    private mtd measurePaintBlocks()
    {
        if .items.count < PaintBlockSize * 8 do
            return

        var first = 0'u64
        while first < .items.count
        {
            .paintBlocks.add(.measurePaintBlock(first))
            first += Math.min(PaintBlockSize, .items.count - first)
        }
    }

    // Bucket items by their centre along the wider axis when authored runs do not cull well.
    private mtd measurePaintBins()
    {
        if .items.count < PaintBlockSize * 64 do
            return

        var minimum = Vector2.Max
        var maximum = Vector2.Min
        var spanX, spanY: f64
        for &block in .paintBlocks
        {
            if not block.bounded do
                return
            minimum = Vector2.min(minimum, block.minimum)
            maximum = Vector2.max(maximum, block.maximum)
            spanX   += cast(f64, block.maximum.x) - block.minimum.x
            spanY   += cast(f64, block.maximum.y) - block.minimum.y
        }

        let width  = cast(f64, maximum.x) - minimum.x
        let height = cast(f64, maximum.y) - minimum.y
        let useY   = height > width
        let origin = cast(f64, useY ? minimum.y : minimum.x)
        let extent = useY ? height : width
        let span   = useY ? spanY : spanX
        if extent <= 0 or span < extent * cast(f64, .paintBlocks.count) * 0.25 do
            return

        .paintBins.resize(PaintBinCount)
        let density  = cast(f64, PaintBinCount) / extent
        var occupied = 0
        for &item, index in .items
        {
            let first  = Vector2{item.bounds.x, item.bounds.y}
            let last   = Vector2{item.bounds.right(), item.bounds.bottom()}
            let centre = useY ? (cast(f64, first.y) + last.y) * 0.5 : (cast(f64, first.x) + last.x) * 0.5
            let bucket = cast(u64, Math.clamp((centre - origin) * density, 0.0'f64, cast(f64, PaintBinCount - 1)))
            let bin    = &.paintBins[bucket]
            let lower  = Vector2.min(first, last)
            let upper  = Vector2.max(first, last)
            if bin.indices.isEmpty()
            {
                bin.bounds = PaintBlock{minimum: lower, maximum: upper, bounded: true}
                occupied   += 1
            }
            else
            {
                bin.bounds.minimum = Vector2.min(bin.bounds.minimum, lower)
                bin.bounds.maximum = Vector2.max(bin.bounds.maximum, upper)
            }

            bin.indices.add(index)
        }

        if occupied <= 1 do
            .paintBins.free()
    }

    // Collect the spatial candidates in authored order when only a small portion is visible.
    private mtd const collectPaintCandidates(transform: Transform2, visible: Rectangle, candidates: *Array'u64)->bool
    {
        if .paintBins.isEmpty() do
            return false

        var selected: StaticArray'(u64, PaintBinCount)
        var count = 0'u64
        for &bin, index in .paintBins where bin.indices.count and not bin.bounds.misses(transform, visible)
        {
            count += bin.indices.count
            if count > .items.count / 4 do
                return false
            selected.add(index)
        }

        candidates.reserve(count)
        for index in selected do
            candidates.add(.paintBins[index].indices.toSlice())
        if selected.count > 1 do
            candidates.sort()
        return true
    }

    // Returns the rectangle a clip range can keep, which is the union of its shapes.
    private mtd const clipRangeBounds(first, count: u64)->Rectangle
    {
        var result: #returntype
        for i in count
        {
            let bounds = .shapes[first + i].pathList.controlBounds()
            if not i do
                result = bounds
            else do
                result.expandToInclude(bounds)
        }

        return result
    }

    // Paints the drawing with its origin at `(x, y)` of the current path space, scaled by `scale`.
    //
    // Fills follow the fill rule of each shape, normalized when the document is parsed, and
    // strokes honor width, caps, and joins scaled by `scale`.
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

        .paintImpl(painter, x, y, scale)
    }

    private mtd const paintShapeCore(painter: *Painter, shape: *Shape, paintFill = true)
    {
        if paintFill and shape.hasFill
        {
            if shape.scanFill do
                .scanFills[shape.scanFill - 1].paint(painter, &shape.pathList, shape.fillColor, shape.evenOdd)
            elif shape.fillGradient do
                painter.fillPath(&shape.pathList, .gradientBrushes[shape.fillGradient - 1])
            else do
                painter.fillPath(&shape.pathList, shape.fillColor)
        }

        if shape.hasStroke
        {
            var pen: Pen
            if shape.strokeGradient do
                pen.brush = .gradientBrushes[shape.strokeGradient - 1]
            else do
                pen.brush.color = shape.strokeColor

            pen.size           = shape.strokeWidth
            pen.begCapStyle    = shape.capStyle
            pen.endCapStyle    = shape.capStyle
            pen.joinStyle      = shape.joinStyle
            pen.joinMiterLimit = shape.strokeMiter
            pen.dashOffset     = shape.strokeOffset
            if not shape.strokePattern.isEmpty()
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

    private mtd const paintPattern(painter: *Painter, shape: *Shape, pattern: const *Pattern)
    {
        shape.pathList.flatten(.Normal)
        var min = Vector2.Max
        var max = Vector2.Min
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
        let pixelWidth          = cast(s32, Math.max(Math.ceil(tileWidth * rasterScale), 1.0'f32))
        let pixelHeight         = cast(s32, Math.max(Math.ceil(tileHeight * rasterScale), 1.0'f32))
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
                let offsetX       = cast(f32, (cast(s32, copyX) - 1)) * tileWidth
                let offsetY       = cast(f32, (cast(s32, copyY) - 1)) * tileHeight
                var tileTransform = Math.Transform2.createTranslation(-tileX - phaseX + offsetX, -tileY - phaseY + offsetY)
                tileTransform.multiply(Math.Transform2.createScale(rasterScale, rasterScale, 0, 0))
                tilePainter.setTransform(tileTransform)
                for i in pattern.count do
                    .paintShapeCore(&tilePainter, &.shapes[pattern.first + i])
            }
        }

        tilePainter.unbindRenderTarget()
        tilePainter.end()
        expect renderer.draw(&tilePainter)

        let tileImage = renderer.readRenderTarget(&target, 0, 0, pixelWidth, pixelHeight)
        renderer.deleteRenderTarget(&target)
        renderer.end()

        let texture = painter.renderer().addImage(tileImage)
        var brush   = Brush.createTiled(texture)

        painter.fillPath(&shape.pathList, brush)
        painter.releaseTexture(texture)
    }

    // Paints one text block and returns the drawing-space rectangle its runs covered.
    private mtd const paintText(painter: *Painter, text: const *SvgText)->Rectangle
    {
        // The pen is a point plus a distance along the baseline, because a rotated element
        // runs its text along a direction rather than along the drawing's x axis. With no
        // rotation the direction is the x axis and this is the ordinary running position.
        var origin:  Vector2
        var advance: f32

        var inked:    #returntype
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

            let size = cast(u32, Math.max(Math.round(run.fontSize), 1.0'f32))
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

            if not hasInked
            {
                inked    = runBox
                hasInked = true
            }
            else
            {
                inked.expandToInclude(runBox)
            }

            painter.drawShapedRun(origin.x + offset, origin.y - font.ascent, &shaped, font, Brush.createSolid(color))
            if rotated do
                painter.popState()
            advance += metrics.width
        }

        return inked
    }

    private mtd const paintImage(painter: *Painter, image: const *SvgImage)
    {
        // Embedded pictures follow the SVG transform, so nearest-neighbor sampling loses
        // their antialiased detail when the document scales them to its viewport.
        let interpolation = painter.interpolationMode()
        painter.setInterpolationMode(.Linear)
        defer painter.setInterpolationMode(interpolation)
        var alpha = image.opacity

        let drawingToSurface = painter.transform()
        var placed = image.transform
        placed.multiply(drawingToSurface)
        painter.setTransform(placed)
        defer painter.setTransform(drawingToSurface)

        let texture = painter.renderer().addImage(.rasterImages[image.rasterIndex])
        painter.drawTexture(image.rect, texture, Color.fromArgb(Argb.White).withAlphaF32(alpha))
        painter.releaseTexture(texture)
    }

    private mtd const paintFilteredShape(painter: *Painter, shape: *Shape, filter: const *SvgFilter, x, y, scale: f32, outerTransform, drawingTransform: Transform2)
    {
        var layer: Layer
        var begin: LayerBeginInfo
        begin.width      = cast(s32, Math.ceil(.width * scale))
        begin.height     = cast(s32, Math.ceil(.height * scale))
        begin.paintAlpha = false

        painter.setTransform(Math.Transform2.createScale(scale, scale, 0, 0))
        layer.begin(painter, begin)
        painter.setColorMaskFull()
        let pattern = .patterns.tryFind(shape.fillPaintId)
        if pattern
        {
            .paintPattern(painter, shape, &pattern.value)
            .paintShapeCore(painter, shape, false)
        }
        else
        {
            .paintShapeCore(painter, shape)
        }

        layer.end()

        var offsetX, offsetY: f32
        var shadow: LayerShadowInfo
        for primitive in filter.primitives
        {
            switch primitive.kind
            {
            case .GaussianBlur:
                layer.blur(primitive.radius * scale)

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
        draw.dstRect = Rectangle{x + offsetX, y + offsetY, .width * scale, .height * scale}
        draw.shadow  = shadow
        layer.draw(draw)
        painter.setTransform(drawingTransform)
    }

    internal mtd const paintImpl(painter: *Painter, x, y: f32, scale: f32)
    {
        #[Swag.Inline]
        func transformAxisAlignedBounds(transform: Transform2, rect: Rectangle)->Rectangle
        {
            // Under an axis-aligned transform, two opposite corners give the full extent.
            let first = transform.transformPoint(Vector2{rect.x, rect.y})
            let last  = transform.transformPoint(Vector2{rect.right(), rect.bottom()})
            if not finitePoint(first) or not finitePoint(last) do
                return transform.transformBounds(rect)

            let minimum = Vector2.min(first, last)
            let size    = Vector2.max(first, last) - minimum
            return Rectangle{minimum.x, minimum.y, size.x, size.y}
        }

        // A drawing is mostly stroke, and a stroke is mostly the bands extruded along it, so its
        // coverage is measured from the centre line instead: two triangles a segment rather than
        // eighteen vertices. On a 1724 by 15036 document fitted to a 4K window that is 4.53
        // million vertices down to 1.76, the frame from 112 ms to 74, and the adapter's share of
        // it from 18 ms to half of one, for the same weight of ink to a third of a percent.
        //
        // Both ways in run through here, which is what keeps them the same picture: a viewport
        // painted small and the same drawing rasterized whole are compared against each other.
        let previousDistanceStrokes = painter.params() & .DistanceStrokes
        painter.setDistanceStrokes(true)
        defer painter.setDistanceStrokes(previousDistanceStrokes != 0)

        painter.pushState()
        defer painter.popState()

        // Local drawing space: scale then translate, applied before the current transform.
        let outerTransform = painter.transform()
        var tr = Math.Transform2.createScale(scale, scale, 0, 0)
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

        let useBlocks    = .paintBlocks.count and painter.hasClippingRect() and tr.m12 == 0 and tr.m21 == 0
        var candidates: Array'u64
        let useBins      = useBlocks and .collectPaintCandidates(tr, visible, &candidates)
        let useRuns      = useBlocks and not useBins
        var measuredText = false
        for blockIndex in (useRuns ? .paintBlocks.count : 1'u64)
        {
            var first = 0'u64
            var end   = useBins ? candidates.count : .items.count
            if useRuns
            {
                if .paintBlocks[blockIndex].misses(tr, visible) do
                    continue
                first = blockIndex * PaintBlockSize
                end   = first + Math.min(PaintBlockSize, .items.count - first)
            }

            for i in first until end
            {
                let itemIndex = useBins ? candidates[i] : i
                let item      = &.items[itemIndex]
                if item.hasBounds
                {
                    var painted = useBlocks ? transformAxisAlignedBounds(tr, item.bounds) : tr.transformBounds(item.bounds)
                    painted.inflate(InkFringeMargin)
                    if not visible.intersects(painted) do
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
                        .paintFilteredShape(painter, shape, &filter.value, x, y, scale, outerTransform, tr)
                        continue
                    }

                    let pattern = .patterns.tryFind(shape.fillPaintId)
                    if pattern
                    {
                        .paintPattern(painter, shape, &pattern.value)
                        .paintShapeCore(painter, shape, false)
                    }
                    else
                    {
                        .paintShapeCore(painter, shape)
                    }

                case .Text:
                    let inked = .paintText(painter, &.texts[item.index])

                    // Where the runs landed is what the block covers, and it is the same at every
                    // scale because a run is shaped in its own upright space.
                    if not item.hasBounds
                    {
                        item.bounds = inked
                        if item.clipCount do
                            item.bounds.intersect(.clipRangeBounds(item.clipFirst, item.clipCount))
                        item.hasBounds = true
                        measuredText   = true
                    }

                case .Image:
                    .paintImage(painter, &.images[item.index])
                }
            }
        }

        .exchangeClip(painter, activeFirst, activeCount, 0, 0)

        // Use the new text bounds to cull blocks on subsequent paints.
        if measuredText
        {
            for &block, index in .paintBlocks where not block.bounded do
                block[] = .measurePaintBlock(index * PaintBlockSize)
        }
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
        Swag.assert(width > 0 and height > 0)

        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        cpu.begin(width, height)
        var result = .rasterize(renderer, width, height, supersample)
        renderer.end()
        return result
    }

    // Rasterizes the drawing through `renderer` into an owned image of exactly `width` by `height` pixels.
    //
    // The result is identical whichever backend produces it, up to the raster-edge
    // tolerance the two backends already carry elsewhere. Supersampled work is split
    // into aligned tiles, so the renderer never retains a target larger than 1024 by
    // 1024 samples; only the finished image crosses back to the caller.
    //
    // The renderer must be ready to draw — its context selected and [[Pixel.IRenderer.init]]
    // called — because this records a complete painter submission and executes it.
    // Returns an invalid image when the backend cannot allocate, draw, or read a tile.
    mtd const rasterize(renderer: IRenderer, width, height: s32, supersample: u8 = 2)->Image
    {
        Swag.assert(width > 0 and height > 0)
        return .rasterizeWithSampleTileSide(renderer, width, height, supersample, RasterSampleTileSide)
    }

    // Rasterizes with an explicit sampled-tile bound for module tests.
    internal mtd const rasterizeWithSampleTileSide(renderer: IRenderer, width, height: s32, supersample: u8, sampleTileSide: s32)->Image
    {
        Swag.assert(width > 0 and height > 0)
        Swag.assert(sampleTileSide > 0)

        let ss            = cast(s32, Math.max(supersample, 1'u8))
        let tileWidth     = Math.min(width, Math.max(sampleTileSide / ss, 1))
        let tileHeight    = Math.min(height, Math.max(sampleTileSide / ss, 1))
        let sampledWidth  = tileWidth * ss
        let sampledHeight = tileHeight * ss
        let whiteMask     = .hasOnlyWhiteShapes()

        // Strokes use destination alpha as scratch. Recover source-over coverage from two
        // opaque mattes instead: white minus black is the uncovered fraction. Both passes
        // paint the authored colors and clips normally, including translucent overlaps.
        var result = Image.create(width, height, .BGRA8)

        // Targets are created at the exact size instead of acquired from the pool, which
        // rounds up to a power of two: the resolve reads the sampled target as a whole,
        // and padding would land inside the box filter. Every tile reuses these same two
        // target sizes, including a partial tile at the right or bottom edge.
        var sampled = renderer.createRenderTarget(sampledWidth, sampledHeight)
        defer renderer.deleteRenderTarget(&sampled)
        if not sampled.colorBuffer.isValid() do
            return {}
        var resolved: RenderTarget
        if ss > 1 do
            resolved = renderer.createRenderTarget(tileWidth, tileHeight)
        defer if ss > 1 do
            renderer.deleteRenderTarget(&resolved)
        if ss > 1 and not resolved.colorBuffer.isValid() do
            return {}

        var tileY = 0
        while tileY < height
        {
            let copyHeight = Math.min(tileHeight, height - tileY)
            var tileX      = 0
            while tileX < width
            {
                let copyWidth = Math.min(tileWidth, width - tileX)
                var mattes: [2] Image
                for matte in (whiteMask ? 1 : 2)
                {
                    var painter = Painter.create(renderer)
                    painter.begin()
                    painter.bindRenderTarget(&sampled)
                    painter.setColorMaskFull()
                    painter.clear(Color.fromArgb(matte == 0 ? Argb.Black : Argb.White))
                    painter.setColorMaskColor()
                    painter.pushClippingSurfaceRect({0, 0, cast(f32, sampledWidth), cast(f32, sampledHeight)})
                    .paintImpl(&painter, cast(f32, (-tileX * ss)), cast(f32, (-tileY * ss)), cast(f32, (width * ss)) / .width)
                    painter.popClippingRect()

                    // Restore opaque coverage after stroke scratch, so the resolve averages
                    // matte colors without unpremultiplying them by a discarded alpha plane.
                    painter.setColorMaskAlpha()
                    painter.setBlendingMode(.Copy)
                    painter.fillRect(Rectangle{0, 0, cast(f32, sampledWidth), cast(f32, sampledHeight)}, Argb.White)
                    painter.unbindRenderTarget()

                    // Average each matte before recovering straight RGB; averaging straight
                    // translucent colors would introduce a fringe along antialiased contours.
                    if ss > 1
                    {
                        let dstRect = Math.Rectangle{0, 0, cast(f32, tileWidth), cast(f32, tileHeight)}
                        let srcRect = Math.Rectangle{0, 0, cast(f32, sampledWidth), cast(f32, sampledHeight)}
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
                    catch renderer.draw(&painter) { return {} }

                    // Render-target readbacks and images share the bottom-up row convention. Copy
                    // each tile into the matching bottom-up rows of the complete result.
                    mattes[matte] = ss == 1 ? renderer.readRenderTarget(&sampled, 0, 0, copyWidth, copyHeight) : renderer.readRenderTarget(&resolved, 0, 0, copyWidth, copyHeight)
                    if not mattes[matte].isValid() do
                        return {}
                }

                for row in copyHeight
                {
                    let black       = mattes[0].pixels.storage() + cast(u64, row) * cast(u64, mattes[0].rowStride)
                    let resultRow   = result.height - tileY - copyHeight + row
                    let destination = result.pixels.storage() + cast(u64, resultRow) * cast(u64, result.rowStride) + cast(u64, tileX) * result.bytesPerPixel

                    // White source-over ink leaves the white matte unchanged. The black
                    // matte alone carries its coverage, including overlaps and stroke scratch.
                    if whiteMask
                    {
                        for column in copyWidth
                        {
                            let offset = cast(u64, column) * 4
                            destination[offset], destination[offset + 1], destination[offset + 2] = 255
                            destination[offset + 3] = black[offset]
                        }

                        continue
                    }

                    let white = mattes[1].pixels.storage() + cast(u64, row) * cast(u64, mattes[1].rowStride)
                    for column in copyWidth
                    {
                        let offset = cast(u64, column) * 4
                        var uncovered: s32
                        for channel in 3 do
                            uncovered += cast(s32, white[offset + channel]) - cast(s32, black[offset + channel])
                        let alpha = Math.clamp(255 - (uncovered + 1) / 3, 0, 255)
                        destination[offset + 3] = cast(u8, alpha)
                        for channel in 3 do
                            destination[offset + channel] = alpha == 0 ? 255'u8 : cast(u8, Math.min((cast(s32, black[offset + channel]) * 255 + alpha / 2) / alpha, 255))
                    }
                }

                tileX += tileWidth
            }

            tileY += tileHeight
        }

        return result
    }

    // White masks need one matte. Keep pictures, text, paint servers and filters on the
    // general path: their final color cannot be established from a solid brush alone.
    private mtd const hasOnlyWhiteShapes()->bool
    {
        for item in .items
        {
            if item.kind != .Shape do
                return false
            let shape = &.shapes[item.index]
            if shape.filterId or shape.fillPaintId or shape.strokePaintId do
                return false
            if shape.hasFill and (shape.fillColor.argb & 0xFFFFFF) != 0xFFFFFF do
                return false
            if shape.hasStroke and (shape.strokeColor.argb & 0xFFFFFF) != 0xFFFFFF do
                return false
        }

        return true
    }
}

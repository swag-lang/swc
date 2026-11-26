#global public
#global namespace Svg

using Core, Core.Math

private const RasterSampleTileSide = 1024's32
private const PaintBlockSize       = 64'u64
private const PaintBinCount        = 128'u64
private const PaintGridColumns     = 16'u64

private const ContourChunkSize = 512'u64

private enum RasterMask
{
    Color
    White
    Black
}

// Controls SVG geometry preparation and external resource resolution.
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

        // Preserves the authored contours of eligible solid paths for scan conversion.
        //
        // Use this when preparing a drawing for bitmap output. The scan converter samples
        // coverage at the pixel scale, so edge alpha can differ from the tessellated path.
        preferScanFills: bool
    }
}

private enum DeferredKind: u8
{
    None
    Rect
    Ellipse
    Line
    Instance
}

private struct DeferredContours
{
    paths: *LinePathList?
}

private impl DeferredContours
{
    mtd release()
    {
        if .paths do
            Memory.delete(.paths)
    }

    mtd duplicate()
    {
        if let original = .paths
        {
            let copy = Memory.new'LinePathList()
            copy[] = original[]
            .paths = copy
        }
    }
}

private struct DeferredGeometry
{
    kind:          DeferredKind
    first, second: Vector2     // Corners, ellipse center and radii, or ordered line endpoints.
    contours:      DeferredContours
}

private struct InstanceBounds
{
    min, max:   Vector2
    arcPadding: Vector2
}

private struct DeferredInstance
{
    source:    u64
    transform: Math.Transform2
    min, max:  Vector2
    contours:  DeferredContours
}

private struct DashRange
{
    first, count: u64
}

private struct DashScaling
{
    source, result: DashRange
    scale: u32
}

private struct ShapeStroke
{
    gradient: u64
    paintId:  u64
    color:    Color
    opacity:  f32 = 1

    width:   f32 = 1
    pattern: DashRange
    offset:  f32
    miter:   f32 = 3

    sharedPattern: bool
    sharedStyle:   bool
    enabled:       bool         = true
    capStyle:      LineCapStyle = None
    joinStyle:     JoinStyle    = Miter
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
        geometry: u64     // Index plus one of the contour list, primitive or instance.
        scanFill: u64     // Index plus one of the raster cache for a dense solid fill.

        fillGradient: u64     // Resolved gradient index plus one, or zero for solid paint.
        #[Swag.Offset("fillGradient")]
        paintTransform: u64     // Transform index during parsing, before brushes are resolved.

        fillColor: Color     // Resolved solid fill color, including opacity.
        #[Swag.Offset("fillColor")]
        fillOpacity: f32     // Opacity of a referenced fill before paint resolution.

        hasFill:  bool             // Whether the shape is filled.
        evenOdd:  bool             // Whether the fill uses the even-odd rule.
        hidden:   bool             // Whether the shape is a reusable definition, not painted directly.
        deferred: DeferredKind     // Selects the stored bounds and the contour builder.

        fillPaintId: u64     // Interned fill paint identifier, or zero for a solid fill.
        stroke:      u64     // Index plus one of authored stroke properties.
        filterId:    u64     // Interned filter identifier, or zero without a reference.
    }
}

private struct SvgGradientBrush
{
    brush: Brush
    stops: u64
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

    shapes:          Array'Shape                  // Parsed vector shapes, including hidden definitions.
    imageSize:       Vector2                      // Absolute root dimensions in CSS pixels, independent of view-box units.
    texts:           Array'SvgText                // Parsed text blocks referenced by the paint-order list.
    images:          Array'SvgImage               // Raster placements referenced by the paint-order list.
    rasterImages:    Array'Image                  // Decoded bitmaps shared by their placements.
    items:           Array'DrawingItem            // Visible elements in paint order.
    clipRanges:      Array'ClipRange              // Clips with more than one shape.
    paintIndex:      Array'PaintIndex             // Owned spatial index, mutable when text is first measured.
    paintBlocks:     Array'PaintBlock             // Bounds of consecutive runs of paint items.
    strokes:         Array'ShapeStroke            // Paint and line style for stroked shapes.
    dashValues:      Array'f32                    // Resolved dash lengths, shared where possible.
    gradientBrushes: Array'SvgGradientBrush       // Resolved gradient geometry and tint.
    gradientStops:   Array'Array'GradientStop     // Stops shared by placements of the same gradient.
    scanFills:       Array'ScanFill               // Raster caches for dense solid fills.
    instances:       Array'DeferredInstance       // Affine placements materialized only when used.
    primitives:      Array'DeferredGeometry       // Geometry of primitives without contour lists.
    contours:        Array'Array'LinePathList     // Geometry constructed during parsing, in fixed-capacity chunks.
    contourCount:    u64
    patterns:        HashTable'(u64, Pattern)       // Resolved repeating paint servers by their interned identifier.
    filters:         HashTable'(u64, SvgFilter)     // Resolved filter primitive chains by their interned identifier.
    preferScanFills: bool
}

private struct ClipRange
{
    first, count: u64
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
    kind: DrawingItemKind

    // Whether `bounds` has been established.
    //
    // A shape or a picture is measured once the document is parsed. Text is measured the
    // first time it is painted, because where a run lands depends on the shaping of the runs
    // before it, and shaping needs the painter's font cache.
    hasBounds:    bool
    refineBounds: bool     // An instance starts with conservative bounds until first seen.
    index:        u64

    // Zero for no clip, a positive shape index plus one, or a negative range index minus one.
    //
    // A `clip-path` is instantiated once per element it applies to, under the transform of the
    // element that named it, so a group's clip stays where the group put it however its
    // children are transformed.
    clip: s64

    // Drawing-space rectangle outside which the item cannot lay ink, already reduced by the
    // clip it is drawn under.
    //
    // A painter whose clipping rectangle misses it skips the item whole, which is what keeps
    // a pan or a zoom proportional to what a window shows rather than to what the document
    // holds. The rectangle is never narrower than the ink and may be wider.
    bounds: Rectangle
}

private struct PatternTileKey
{
    id:    u64
    origin, phase, size: Vector2
    scale: f32
}

private struct PatternRaster
{
    key:   PatternTileKey
    image: Image
}

private struct PaintBlock
{
    minimum, maximum: Vector2
    bounded: bool
}

private func finitePoint(point: Vector2)->bool => Math.isFinite(point.x) and Math.isFinite(point.y)

private impl PaintBlock
{
    mtd const misses(transform: Math.Transform2, visible: Rectangle, axisAligned: bool)->bool
    {
        if not .bounded do
            return false

        let first = transform.transformPoint(.minimum)
        let last  = transform.transformPoint(.maximum)
        if not finitePoint(first) or not finitePoint(last) do
            return false

        var lower = Vector2.min(first, last)
        var upper = Vector2.max(first, last)

        // Under a rotation or shear an extremum can be at either remaining corner.
        if not axisAligned
        {
            let topRight   = transform.transformPoint(Vector2{.maximum.x, .minimum.y})
            let bottomLeft = transform.transformPoint(Vector2{.minimum.x, .maximum.y})
            if not finitePoint(topRight) or not finitePoint(bottomLeft) do
                return false
            lower = Vector2.min(lower, Vector2.min(topRight, bottomLeft))
            upper = Vector2.max(upper, Vector2.max(topRight, bottomLeft))
        }

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
    indices: Array'u32
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

private struct PaintIndex
{
    bins: Array'PaintBin
}

private struct SvgTextMeasure
{
    font:    *Font?
    metrics: StringMetrics
    letterSpacing, wordSpacing: u32
}

private const TextMeasureCacheSize = 128

private struct SvgTextScratch
{
    shaped:           ShapedRun
    measurements:     HashTable'(string, SvgTextMeasure)
    remainingLookups: u32 = TextMeasureCacheSize
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
    hasClip:       bool            // Whether this element or an ancestor names a clip.

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

    #[Swag.Inline]
    mtd const canDeferPrimitive(allowPaintServer = false)->bool =>
        .drawsShape() and
        not .inDefs and
        not .filterId.count and
        (allowPaintServer or (not .fillPaintId.count and not .strokePaintId.count))

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

private const MaxCachedRasterBytes = 1024 * 1024
private const MaxCachedRasterFiles = 4

private struct CachedExternalRaster
{
    encoded: Array'u8
    index:   u64
}

private struct ParsedDashPattern
{
    lengths:          Array'SvgLength
    resolved:         DashRange
    geometryScale:    u32
    viewportDiagonal: u32
}

private struct ClipPlacement
{
    definition: ClipRange
    placement:  ClipRange
    transform:  Math.Transform2
    shareable:  bool
}

private struct Parser
{
    text:    string     // Whole document.
    pos:     u64        // Read position.
    drawing: *Drawing

    // Shapes defined inside `defs`, by id, instantiated by `use` elements. The
    // ranges index the drawing's shape array: defs shapes are parsed in place and
    // withheld from painting. These lookup tables borrow identifiers from the source.
    defs:            HashTable'(string, { first: u64, count: u64 })
    clipPaths:       HashTable'(string, { first: u64, count: u64 })
    lastClip:        ClipPlacement
    symbols:         HashTable'(string, SymbolViewport)
    markers:         HashTable'(string, MarkerDefinition)
    gradients:       HashTable'(string, Gradient)
    referenceIds:    HashTable'(string, u64)
    referenceNames:  Array'string
    patterns:        HashTable'(u64, Pattern)
    filters:         HashTable'(u64, SvgFilter)
    styles:          StyleSheet
    dashPatterns:    HashTable'(string, ParsedDashPattern)
    lastDashScaling: DashScaling
    lastSolidStroke: u64
    embeddedImages:  HashTable'(string, u64)     // Raster indices plus one, keyed by the authored URI.
    externalImages:  HashTable'(string, CachedExternalRaster)     // Encoded bytes and raster indices for small files.
    options:         ParseOptions
    typeFaces:       [FontFamilyKind.count] (*TypeFace?)
    svgDepth:        u32
    inDefs:          bool     // Whether parsing currently sits inside a `defs` element.
    dimensionsOnly:  bool

    paintTransforms: Array'Math.Transform2     // Element transforms used to resolve paint references.
    instanceBounds:  HashTable'(u64, InstanceBounds)     // Bounds of reused definitions before placement.

    lastTransform:       string = ""
    lastTransformParent: Math.Transform2
    lastTransformResult: Math.Transform2
    transformMisses:     u8
    transformCooldown:   u8

    lastInlineStyle:    string = ""
    inlineDeclarations: Array'StyleDeclaration
    inlineCacheReady:   bool
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
    Transform
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
    case "transform":           return .Transform
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

private struct StyleApplication
{
    tag, classes, id: string = ""
    input, output:    GroupState
    valid:            bool
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
    lastApplication: StyleApplication
    replayMisses:    u8
    replayDelay:     u8
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

    cachedStops: u64     // Index plus one of the stop list shared by the gradient's brushes.

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
    if i >= len do
        return 0
    let negative = s[i] == '-'
    if negative or s[i] == '+' do
        i += 1

    let digits   = i
    let exactEnd = i + Math.min(15'u64, len - i)
    var integral = 0'u64
    while i < exactEnd and Latin1.isDigit(s[i])
    {
        integral = integral * 10 + cast(u64, s[i] - '0')
        i        += 1
    }

    if i == exactEnd
    {
        while i < len and Latin1.isDigit(s[i]) do
            i += 1
    }

    let integerDigits = i - digits
    var divisor       = 1'u64
    var exact         = i <= exactEnd
    if i < len and s[i] == '.'
    {
        i += 1
        let budget      = 15 - Math.min(15'u64, integerDigits)
        let fractionEnd = i + Math.min(budget, len - i)
        while i < fractionEnd and Latin1.isDigit(s[i])
        {
            integral = integral * 10 + cast(u64, s[i] - '0')
            divisor  *= 10
            i        += 1
        }

        if i == fractionEnd
        {
            while i < len and Latin1.isDigit(s[i]) do
                i += 1
        }

        exact = exact and i <= fractionEnd
    }

    let mantissaEnd = i

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

    // The integer mantissa and decimal divisor of a short coordinate are exact in f64.
    if exact and i == mantissaEnd and (integerDigits or divisor > 1)
    {
        let value = divisor == 1 ? cast(f32, integral) : cast(f32, cast(f64, integral) / cast(f64, divisor))
        return negative ? -value : value
    }

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
    result.value = readNumber(value, &pos)
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
    let number = readNumber(text, &pos)
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

private func parsePaintId(value: string)->string => readPaintId(Latin1.trim(value))

private func readPaintId(trimmed: string)->string
{
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

    let amount = readNumber(text, &pos)
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

// Decodes a trimmed hexadecimal paint, including the optional alpha digits.
private func readHexPaint(text: string)->Color
{
    let len = text.count
    if len == 4 or len == 5
    {
        let r = hexNibble(text[1]) * 17
        let g = hexNibble(text[2]) * 17
        let b = hexNibble(text[3]) * 17
        let a = len == 5 ? hexNibble(text[4]) * 17 : 255'u8
        return Color.fromArgb(a, r, g, b)
    }

    if len == 7 or len == 9
    {
        let r = hexNibble(text[1]) * 16 + hexNibble(text[2])
        let g = hexNibble(text[3]) * 16 + hexNibble(text[4])
        let b = hexNibble(text[5]) * 16 + hexNibble(text[6])
        let a = len == 9 ? hexNibble(text[7]) * 16 + hexNibble(text[8]) : 255'u8
        return Color.fromArgb(a, r, g, b)
    }

    return Color.fromArgb(Argb.Black)
}

// Parses a solid paint value. Returns the color and whether painting is enabled.
private func parseColor(value: string)->{ color: Color, enabled: bool } => readColor(Latin1.trim(value))

private func readColor(text: string)->{ color: Color, enabled: bool }
{
    var result: #returntype
    result.color   = Color.fromArgb(Argb.Black)
    result.enabled = true

    let len = text.count
    if len and text[0] == '#'
    {
        result.color = readHexPaint(text)
        return result
    }

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
        pos = skipNumberSeparators(text, pos)
        if pos >= text.count or not isNumberStart(text[pos]) do
            break

        var length = SvgLength{value: readNumber(text, &pos)}
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

private func readStylePaint(value: string, currentColor, previousColor: Color)->{ id: string, color: Color, enabled: bool }
{
    let text = Latin1.trim(value)
    if text.count and text[0] == '#' do
        return {id: "", color: readHexPaint(text), enabled: true}

    let reference = readPaintId(text)
    if reference.count do
        return {id: reference, color: previousColor, enabled: true}
    if not Latin1.compare(text, "currentColor", ignoreCase: true) do
        return {id: "", color: currentColor, enabled: true}

    let {color, enabled} = readColor(text)
    return {id: "", color: enabled ? color : previousColor, enabled: enabled}
}

private func applyStyleProperty(state: *GroupState, name, value: string)
{
    switch name
    {
    case "fill":
        let paint = readStylePaint(value, state.currentColor, state.fillColor)
        state.fillPaintId = paint.id
        state.fillColor   = paint.color
        state.hasFill     = paint.enabled

    case "stroke":
        let paint = readStylePaint(value, state.currentColor, state.strokeColor)
        state.strokePaintId = paint.id
        state.strokeColor   = paint.color
        state.hasStroke     = paint.enabled

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
        pos = skipNumberSeparators(value, pos)

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
            let look = skipNumberSeparators(value, pos)
            if look >= len or not isNumberStart(value[look]) do
                break
            pos   = look
            arguments[count] = readNumber(value, &pos)
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

    var angle    = angles.x
    var sinAngle = Math.sin(angle)
    var cosAngle = Math.cos(angle)
    for segCount
    {
        let nextAngle = angle + segAngle
        let sinNext   = Math.sin(nextAngle)
        let cosNext   = Math.cos(nextAngle)

        let p0x = cx + sinAngle * radii.x
        let p0y = cy - cosAngle * radii.y
        let p1x = cx + sinNext * radii.x
        let p1y = cy - cosNext * radii.y

        let control0 = mapPoint(state, p0x + k * cosAngle * radii.x, p0y + k * sinAngle * radii.y)
        let control1 = mapPoint(state, p1x - k * cosNext * radii.x, p1y - k * sinNext * radii.y)
        let end      = mapPoint(state, p1x, p1y)
        path.bezierTo(end.x, end.y, control0.x, control0.y, control1.x, control1.y)
        angle    = nextAngle
        sinAngle = sinNext
        cosAngle = cosNext
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
    let cosPhi = phi == 0 ? 1.0 : Math.cos(phi)
    let sinPhi = phi == 0 ? phi : Math.sin(phi)

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

    var angle    = startAngle
    var sinAngle = Math.sin(angle)
    var cosAngle = Math.cos(angle)
    for segCount
    {
        let nextAngle = angle + segAngle
        let sinNext   = Math.sin(nextAngle)
        let cosNext   = Math.cos(nextAngle)
        let p1x       = rx * cosNext
        let p1y       = ry * sinNext
        let c0x       = rx * cosAngle - k * rx * sinAngle
        let c0y       = ry * sinAngle + k * ry * cosAngle
        let c1x       = p1x + k * rx * sinNext
        let c1y       = p1y - k * ry * cosNext

        let end      = placeArcPoint(state, cx, cy, cosPhi, sinPhi, p1x, p1y)
        let control0 = placeArcPoint(state, cx, cy, cosPhi, sinPhi, c0x, c0y)
        let control1 = placeArcPoint(state, cx, cy, cosPhi, sinPhi, c1x, c1y)
        path.bezierTo(end.x, end.y, control0.x, control0.y, control1.x, control1.y)
        angle    = nextAngle
        sinAngle = sinNext
        cosAngle = cosNext
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

private func readPathNumber(data: string, pos: *u64, valid: *bool)->f32
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

// A single open segment can keep its two endpoints until it is painted.
private func readStraightStroke(data: string, state: *GroupState)->DeferredGeometry
{
    var pos = skipNumberSeparators(data, 0)
    if pos >= data.count or data[pos] != 'M' do
        return {}
    pos += 1

    var valid  = true
    let startX = readPathNumber(data, &pos, &valid)
    let startY = readPathNumber(data, &pos, &valid)
    pos = skipNumberSeparators(data, pos)
    if not valid or pos >= data.count do
        return {}

    let command = data[pos]
    pos += 1
    var endX = startX
    var endY = startY
    switch command
    {
    case 'H', 'h':
        endX = readPathNumber(data, &pos, &valid)
        if command == 'h' do
            endX += startX

    case 'V', 'v':
        endY = readPathNumber(data, &pos, &valid)
        if command == 'v' do
            endY += startY

    case 'L', 'l':
        endX = readPathNumber(data, &pos, &valid)
        endY = readPathNumber(data, &pos, &valid)
        if command == 'l'
        {
            endX += startX
            endY += startY
        }

        if Math.abs(endX - startX) <= 0.0005 and Math.abs(endY - startY) <= 0.0005 do
            return {}

    default:
        return {}
    }

    if not valid or skipNumberSeparators(data, pos) != data.count do
        return {}

    let start = mapPoint(state, startX, startY)
    let end   = mapPoint(state, endX, endY)
    if not start.isFinite() or not end.isFinite() or not (end - start).isFinite() do
        return {}

    return DeferredGeometry{.Line, start, end}
}

// The compact builder only accepts straight segments. Exponents are consumed by
// the number reader, so their e and E do not denote curves.
private func hasPathCurveCommand(data: string)->bool
{
    const Width = #sizeof(Simd.U8x16)
    let lower       = Simd.splat(0x20'u8)
    let arc         = Simd.splat(cast(u8, 'a'))
    let cubic       = Simd.splat(cast(u8, 'c'))
    let quad        = Simd.splat(cast(u8, 'q'))
    let smoothCubic = Simd.splat(cast(u8, 's'))
    let smoothQuad  = Simd.splat(cast(u8, 't'))
    var cursor      = 0'u64
    while data.count - cursor >= Width
    {
        let letters = Simd.load(data.buffer + cursor) | lower
        let curves  = Simd.bitmask(letters == arc) | Simd.bitmask(letters == cubic) |
                      Simd.bitmask(letters == quad) | Simd.bitmask(letters == smoothCubic) |
                      Simd.bitmask(letters == smoothQuad)
        if curves do
            return true
        cursor += Width
    }

    for pos in cursor until data.count
    {
        switch data[pos]
        {
        case 'C', 'c', 'S', 's', 'Q', 'q', 'T', 't', 'A', 'a': return true
        default: break
        }
    }

    return false
}

#[Swag.Inline]
private func appendPathLine(path: *LinePath, target: Vector2, linear: bool, segments: *u64)
{
    if linear
    {
        if path.appendLinear(target) do
            segments[] += 1
    }
    else
    {
        path.lineTo(target.x, target.y)
    }
}

// Parses one `d` attribute into subpath contours, transformed by `state`.
//
// `vertices` collects the authored vertices markers are placed on; pass null when the element
// carries none, which is the common case and skips the bookkeeping entirely.
private func parsePathData(list: *LinePathList, data: string, state: *GroupState, vertices: *Array'MarkerVertex?, linear: bool, segments: *u64)
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
                if started
                {
                    if linear
                    {
                        if path.closeLinear() do
                            segments[] += 1
                    }
                    else
                    {
                        path.close()
                    }
                }

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
            var x = readPathNumber(data, &pos, &valid)
            var y = readPathNumber(data, &pos, &valid)
            if not valid do
                return
            if rel
            {
                x += curX
                y += curY
            }

            let start = mapPoint(state, x, y)
            path = list.newPath()
            if linear do
                path.startLinear(start)
            else do
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
            var x = readPathNumber(data, &pos, &valid)
            var y = readPathNumber(data, &pos, &valid)
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
                appendPathLine(unwrap path, target, linear, segments)
                addMarkerVertex(vertices, Vector2{x, y}, Vector2{x - curX, y - curY}, Vector2{x - curX, y - curY})
            }

            curX = x
            curY = y

        case 'H', 'h':
            var x = readPathNumber(data, &pos, &valid)
            if not valid do
                return
            if rel do
                x += curX
            let target = mapPoint(state, x, curY)
            appendPathLine(unwrap path, target, linear, segments)
            addMarkerVertex(vertices, Vector2{x, curY}, Vector2{x - curX, 0}, Vector2{x - curX, 0})
            curX = x

        case 'V', 'v':
            var y = readPathNumber(data, &pos, &valid)
            if not valid do
                return
            if rel do
                y += curY
            let target = mapPoint(state, curX, y)
            appendPathLine(unwrap path, target, linear, segments)
            addMarkerVertex(vertices, Vector2{curX, y}, Vector2{0, y - curY}, Vector2{0, y - curY})
            curY = y

        case 'C', 'c', 'S', 's':
            var c1x, c1y: f32
            if cmd == 'C' or cmd == 'c'
            {
                c1x = readPathNumber(data, &pos, &valid)
                c1y = readPathNumber(data, &pos, &valid)
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

            var c2x = readPathNumber(data, &pos, &valid)
            var c2y = readPathNumber(data, &pos, &valid)
            var x   = readPathNumber(data, &pos, &valid)
            var y   = readPathNumber(data, &pos, &valid)
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
                c1x = readPathNumber(data, &pos, &valid)
                c1y = readPathNumber(data, &pos, &valid)
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

            var x = readPathNumber(data, &pos, &valid)
            var y = readPathNumber(data, &pos, &valid)
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
            let rx       = readPathNumber(data, &pos, &valid)
            let ry       = readPathNumber(data, &pos, &valid)
            let rotation = readPathNumber(data, &pos, &valid)
            let largeArc = flag(data, &pos, &valid)
            let sweepF   = flag(data, &pos, &valid)
            var x        = readPathNumber(data, &pos, &valid)
            var y        = readPathNumber(data, &pos, &valid)
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
private func usesScanFill(list: const *LinePathList, state: const *GroupState, linearSegments: u64, preferScanFills: bool)->bool
{
    if not state.hasFill or
       state.hasStroke or
       state.inDefs or
       state.fillPaintId.count or
       state.filterId.count do
        return false
    if preferScanFills and not state.hasClip and not state.hasMarkers() do
        return true
    if list.paths.count >= 512 or linearSegments >= 8192 do
        return true
    var segments = linearSegments
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

private func applyPaintOpacity(color: Color, opacity: f32)->Color
{
    return color.withAlphaF32((cast(f32, color.a) / 255.0) * Math.saturate(opacity))
}

private impl Parser
{
    mtd appendDashValues(lengths: const [..] SvgLength, geometryScale, viewportDiagonal: f32)->DashRange
    {
        let first = .drawing.dashValues.count
        .drawing.dashValues.resize(first + lengths.count)
        for value, index in lengths
        {
            let length = value.isPercent ? value.value * viewportDiagonal : value.value
            .drawing.dashValues[first + index] = length * geometryScale
        }

        return DashRange{first, lengths.count}
    }

    mtd resolveStrokePattern(stroke: *ShapeStroke, value: string, geometryScale, viewportDiagonal: f32)
    {
        if not value.count do
            return

        let key   = .sourceView(value)
        var entry = .dashPatterns.tryFind(key)
        if not entry
        {
            var lengths = parseDashPattern(key)

            // Bound the cache for artwork with a unique pattern on each shape.
            if .dashPatterns.count >= 64 or lengths.count > 64
            {
                stroke.pattern = .appendDashValues(lengths.toSlice(), geometryScale, viewportDiagonal)
                return
            }

            entry = .dashPatterns.add(key, {lengths: #move lengths})
        }

        let pattern = &entry.value
        if pattern.lengths.isEmpty() do
            return

        let scaleBits    = cast #bit(u32, geometryScale)
        let diagonalBits = cast #bit(u32, viewportDiagonal)

        // Keep the first resolution of each pattern so calibration has a single stable
        // source even when successive shapes use different transforms.
        if not pattern.resolved.count
        {
            pattern.resolved         = .appendDashValues(pattern.lengths.toSlice(), geometryScale, viewportDiagonal)
            pattern.geometryScale    = scaleBits
            pattern.viewportDiagonal = diagonalBits
        }

        if pattern.geometryScale == scaleBits and pattern.viewportDiagonal == diagonalBits
        {
            stroke.pattern       = pattern.resolved
            stroke.sharedPattern = true
        }
        else
        {
            stroke.pattern = .appendDashValues(pattern.lengths.toSlice(), geometryScale, viewportDiagonal)
        }
    }

    mtd scaleDashValues(stroke: *ShapeStroke, scale: f32)
    {
        let range = stroke.pattern
        if not range.count or scale == 1 do
            return

        if stroke.sharedPattern
        {
            let factor = cast #bit(u32, scale)
            let last   = &.lastDashScaling
            if last.source.first == range.first and
               last.source.count == range.count and
               last.scale == factor
            {
                stroke.pattern = last.result
                return
            }

            let first = .drawing.dashValues.count
            .drawing.dashValues.resize(first + range.count)
            for i in range.count do
                .drawing.dashValues[first + i] = .drawing.dashValues[range.first + i] * scale

            stroke.pattern.first = first
            last[] = DashScaling{range, stroke.pattern, factor}
        }
        else
        {
            for i in range.count do
                .drawing.dashValues[range.first + i] *= scale
        }
    }

    mtd emitShape(list: #move LinePathList, state: *GroupState, linearSegments = 0'u64)
    {
        if list.paths.isEmpty() do
            return
        if not state.drawsShape() do
            return

        // A triangulated fill needs one outer contour followed by its holes. Split separate islands
        // by containment depth, keeping the source order of both islands and holes.
        let scanFill = usesScanFill(&list, state, linearSegments, .options.preferScanFills)
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

    mtd storeStroke(state: const *GroupState)->u64
    {
        var stroke: ShapeStroke
        stroke.color   = state.strokeColor
        stroke.paintId = .internReference(state.strokePaintId)
        stroke.opacity = state.strokeOpacity * state.opacity

        let geometryScale = transformScale(state.transform)
        stroke.width = state.strokeWidth * geometryScale
        let diagonal = state.strokePattern.count or state.strokeOffset.isPercent ?
                       Math.sqrt(.drawing.width * .drawing.width + .drawing.height * .drawing.height) / Math.ConstF32.Sqrt2 :
                       0'f32
        stroke.offset = (state.strokeOffset.isPercent ? state.strokeOffset.value * diagonal : state.strokeOffset.value) * geometryScale
        stroke.miter  = state.strokeMiter
        .resolveStrokePattern(&stroke, state.strokePattern, geometryScale, diagonal)
        stroke.capStyle  = state.capStyle
        stroke.joinStyle = state.joinStyle

        if not stroke.paintId
        {
            stroke.color = applyPaintOpacity(stroke.color, stroke.opacity)
            if not stroke.pattern.count and stroke.offset == 0
            {
                stroke.sharedStyle = true
                if .lastSolidStroke
                {
                    let previous = &.drawing.strokes[.lastSolidStroke - 1]
                    if previous.color.argb == stroke.color.argb and
                       cast #bit(u32, previous.width) == cast #bit(u32, stroke.width) and
                       cast #bit(u32, previous.miter) == cast #bit(u32, stroke.miter) and
                       previous.capStyle == stroke.capStyle and
                       previous.joinStyle == stroke.joinStyle do
                        return .lastSolidStroke
                }

                .lastSolidStroke = .drawing.strokes.count + 1
            }
        }

        .drawing.strokes.add(stroke)
        return .drawing.strokes.count
    }

    mtd emitShapeOne(list: #move LinePathList, state: *GroupState, scanFill = false, geometry: DeferredGeometry = {})
    {
        let shapeIndex = .drawing.shapes.count
        let shape      = .drawing.shapes.emplaceInitAddress()
        if scanFill
        {
            let cache = .drawing.scanFills.emplaceInitAddress()
            cache.measureGeometry(&list)
            shape.scanFill = .drawing.scanFills.count
        }

        shape.hidden   = state.inDefs
        shape.deferred = geometry.kind
        if geometry.kind != .None
        {
            .drawing.primitives.add(geometry)
            shape.geometry = .drawing.primitives.count
        }
        else
        {
            .drawing.storeContours(shape, #move list)
        }

        shape.hasFill = state.hasFill
        if state.hasFill
        {
            shape.fillPaintId = .internReference(state.fillPaintId)
            shape.evenOdd     = state.evenOdd
            let opacity = state.fillOpacity * state.opacity
            if shape.fillPaintId do
                shape.fillOpacity = opacity
            else do
                shape.fillColor = applyPaintOpacity(state.fillColor, opacity)
        }

        if state.hasStroke do
            shape.stroke = .storeStroke(state)

        let stroke = .drawing.strokeFor(shape)
        if shape.fillPaintId or (stroke and stroke.paintId) do
            shape.paintTransform = .storePaintTransform(&state.transform)
        shape.filterId = .internReference(state.filterId)

        if not shape.hidden do
            .drawing.items.add(DrawingItem{kind: .Shape, index: shapeIndex})
    }

    mtd emitRect(state: *GroupState, x, y, w, h, rx, ry: f32)
    {
        if w <= 0 or h <= 0 do
            return

        var list: LinePathList
        let crx = Math.min(rx, w * 0.5)
        let cry = Math.min(ry, h * 0.5)

        if crx >= w * 0.5 - 0.001 and cry >= h * 0.5 - 0.001
        {
            // Full horizontal and vertical corner radii form an ellipse.
            appendEllipse(list.newPath(), state, x + w * 0.5, y + h * 0.5, w * 0.5, h * 0.5)
        }
        elif isAxisAligned(state.transform)
        {
            let origin   = mapPoint(state, x, y)
            let scale    = state.transform.axisScale()
            let rect     = Rectangle{origin.x, origin.y, w * scale.x, h * scale.y}
            let opposite = Vector2{rect.right(), rect.bottom()}
            if crx > 0 and cry > 0
            {
                list.newPath().setRoundRectRaw(rect.x, rect.y, rect.width, rect.height, crx * scale.x, cry * scale.y)
            }
            // A gradient's object bounds come from the flattened path. Each edge must
            // survive the flattening duplicate threshold for those bounds to be exact.
            elif state.canDeferPrimitive(allowPaintServer: true) and
                 finitePoint(origin) and
                 finitePoint(opposite) and
                 not Math.isEqualEpsilon(rect.x, opposite.x) and
                 not Math.isEqualEpsilon(rect.y, opposite.y) and
                 ((not state.fillPaintId.count and not state.strokePaintId.count) or
                  (opposite.x - origin.x >= 0.0001 and opposite.y - origin.y >= 0.0001))
            {
                .emitShapeOne(#move list, state, geometry: DeferredGeometry{.Rect, origin, opposite})
                return
            }
            else
            {
                list.newPath().setRectRaw(rect.x, rect.y, rect.width, rect.height)
            }
        }
        else
        {
            appendRectContour(list.newPath(), state, x, y, w, h, crx, cry)
        }

        .emitShapeOne(#move list, state)
    }

    mtd emitEllipse(state: *GroupState, cx, cy, rx, ry: f32)
    {
        if rx <= 0 or ry <= 0 do
            return

        var list: LinePathList
        if isAxisAligned(state.transform)
        {
            let center = mapPoint(state, cx, cy)
            let scale  = state.transform.axisScale()
            let radii  = Vector2{rx * scale.x, ry * scale.y}
            if state.canDeferPrimitive()
            {
                if finitePoint(center - radii) and finitePoint(center + radii)
                {
                    .emitShapeOne(#move list, state, geometry: DeferredGeometry{.Ellipse, center, radii})
                    return
                }
            }

            list.newPath().setEllipseRaw(center.x, center.y, radii.x, radii.y)
        }
        else
        {
            appendEllipse(list.newPath(), state, cx, cy, rx, ry)
        }

        .emitShapeOne(#move list, state)
    }

    mtd emitPoly(state: *GroupState, points: string, closeIt: bool)
    {
        let drawsPath  = state.drawsShape(strokeOnly: not closeIt)
        let hasMarkers = state.hasMarkers()
        if not drawsPath and not hasMarkers do
            return

        var list:     LinePathList
        var vertices: Array'MarkerVertex
        let path   = drawsPath ? list.newPath() : null
        let linear = path and points.count >= 1024 and not hasMarkers and state.canDeferPrimitive()
        var pos, count, linearSegments: u64

        while pos < points.count
        {
            var look = pos
            while look < points.count and (points[look] == ' ' or points[look] == ',') do
                look += 1
            if look >= points.count or not isNumberStart(points[look]) do
                break

            pos = look
            let x = readNumber(points, &pos)
            let y = scanNumber(points, &pos)
            if path
            {
                let point = mapPoint(state, x, y)
                if linear
                {
                    if not count do
                        path.startLinear(point)
                    elif path.appendLinear(point) do
                        linearSegments += 1
                }
                elif not count
                {
                    path.start(point.x, point.y)
                }
                else
                {
                    path.lineTo(point.x, point.y)
                }
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
                if linear
                {
                    if path.closeLinear() do
                        linearSegments += 1
                }
                else
                {
                    path.close()
                }

                .emitShape(#move list, state, linearSegments)
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
        .lastApplication.valid = false
        .replayMisses = 0
        .replayDelay  = 0
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
        let tag       = .byTag.count ? elementName : ""
        let classAttr = .byClass.count ? geo.tryFind(.Class) : null
        let idAttr    = .byId.count ? geo.tryFind(.Id) : null
        let classes   = classAttr ? classAttr.value : ""
        let id        = idAttr ? idAttr.value : ""
        if not tag.count and not classes.count and not id.count do
            return

        if .replayDelay
        {
            .replayDelay -= 1
            .applyIndexed(tag, classes, id, state)
            return
        }

        // Adjacent shapes often inherit the same presentation and match the same rules.
        let last = &.lastApplication
        if last.valid
        {
            if last.tag == tag and
               last.classes == classes and
               last.id == id and
               Memory.compare(&last.input, state, #sizeof(GroupState)) == 0
            {
                state[]       = last.output
                .replayMisses = 0
                return
            }

            // Pause comparisons when consecutive elements use distinct styles.
            .replayMisses += 1
            if .replayMisses >= 4
            {
                last.valid    = false
                .replayMisses = 0
                .replayDelay  = 64
                .applyIndexed(tag, classes, id, state)
                return
            }
        }

        last.tag     = tag
        last.classes = classes
        last.id      = id
        last.input   = state[]
        .applyIndexed(tag, classes, id, state)
        last.output = state[]
        last.valid  = true
    }

    mtd applyIndexed(tag, classes, id: string, state: *GroupState)
    {
        // Apply the indexed rules in increasing selector specificity.
        if tag.count
        {
            if let rules = .byTag.tryFind(String.toLower(tag)) do
                .applyRules(&rules.value, state)
        }

        if classes.count do
            .applyClassRules(classes, state)
        if id.count
        {
            if let rules = .byId.tryFind(id) do
                .applyRules(&rules.value, state)
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

    mtd applyInlineStyle(state: *GroupState, value: string)
    {
        // Cache repeated styles with enough declarations to benefit from a saved scan.
        if value.count < 32 or value.count > 1024
        {
            applyAttribute(state, "style", value)
            return
        }

        if value != .lastInlineStyle
        {
            .lastInlineStyle  = .sourceView(value)
            .inlineCacheReady = false
        }

        if not .inlineCacheReady and value.buffer == .lastInlineStyle.buffer
        {
            applyAttribute(state, "style", value)
            return
        }

        // A second authored attribute uses the same declaration list.
        if not .inlineCacheReady
        {
            .inlineDeclarations.clear()
            var cursor = 0'u64
            while cursor < value.count
            {
                let declaration = nextStyleDeclaration(value, &cursor)
                if declaration.name.count do
                    .inlineDeclarations.add(declaration)
            }

            .inlineCacheReady = true
        }

        for &declaration in .inlineDeclarations do
            applyStyleProperty(state, declaration.name, declaration.value)
    }

    mtd applyStyles(elementName: string, geo: *AttributeMap, state: *GroupState)
    {
        if .styles.rules.count do
            .styles.apply(elementName, geo, state)
        if let inlineStyle = geo.tryFind(.Style) do
            .applyInlineStyle(state, inlineStyle.value)
    }

    mtd applyTransform(state: *GroupState, value: string)
    {
        // Simple translations and scales are cheap to parse. Cache longer lists while
        // successive elements reuse them, with a short pause if their values keep changing.
        if value.count < 24 or value.count > 1024
        {
            state.transform = composeTransformList(value, state.transform)
            return
        }

        if .transformCooldown
        {
            .transformCooldown -= 1
            state.transform    = composeTransformList(value, state.transform)
            return
        }

        if value == .lastTransform and
           Memory.compare(&state.transform, &.lastTransformParent, #sizeof(Math.Transform2)) == 0
        {
            state.transform  = .lastTransformResult
            .transformMisses = 0
            return
        }

        .lastTransform       = .sourceView(value)
        .lastTransformParent = state.transform
        state.transform      = composeTransformList(value, state.transform)
        .lastTransformResult = state.transform
        .transformMisses     += 1
        if .transformMisses == 4
        {
            .transformCooldown = 16
            .transformMisses   = 0
        }
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
                .applyInlineStyle(state, value)

            case .Transform:
                .applyTransform(state, value)

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

    mtd accumulatePathLength(shape: *Shape, length: *f32)
    {
        if shape.deferred == .Rect or shape.deferred == .Line
        {
            let primitive = &.drawing.primitives[shape.geometry - 1]
            let first     = primitive.first
            let last      = primitive.second
            let size      = last - first
            if shape.deferred == .Line
            {
                if Math.abs(size.x) >= 0.0001 or Math.abs(size.y) >= 0.0001 do
                    length[] += first.distanceTo(last)
                return
            }

            // These edges survive flattening. Add them in contour order so the
            // rounding of a group with many paths stays the same.
            if size.isFinite() and size.x >= 0.0001 and size.y >= 0.0001
            {
                let horizontal = first.distanceTo(Vector2{last.x, first.y})
                let vertical   = first.distanceTo(Vector2{first.x, last.y})
                length[] += horizontal
                length[] += vertical
                length[] += horizontal
                length[] += vertical
                return
            }
        }

        let paths = .drawing.materializeShape(shape)
        paths.flatten(.Normal)
        for path in paths.paths
        {
            let pointCount = path.polygon.points.count
            for j in 1 until pointCount do
                length[] += path.polygon.points[j - 1].distanceTo(path.polygon.points[j])
            if path.isClosed and pointCount > 1 do
                length[] += path.polygon.points[pointCount - 1].distanceTo(path.polygon.points[0])
        }
    }

    mtd applyPathLength(first, count: u64, authoredLength, geometryScale: f32)
    {
        if authoredLength <= 0 or Math.abs(geometryScale) <= 0.000001 do
            return

        // The calibrated length only affects a stroke's dash pattern and offset.
        var calibrateStroke = false
        for i in count
        {
            let stroke = .drawing.strokeFor(&.drawing.shapes[first + i])
            if stroke and (stroke.pattern.count or stroke.offset != 0)
            {
                calibrateStroke = true
                break
            }
        }

        if not calibrateStroke
        {
            // Keep the original tolerance for curves before a draft-quality paint.
            for i in count
            {
                let shape = &.drawing.shapes[first + i]
                if shape.deferred == .Rect or shape.deferred == .Line do
                    continue
                let paths = .drawing.materializeShape(shape)
                for path in paths.paths where path.hasCurves() do
                    path.flatten(.Normal)
            }

            return
        }

        var actualLength: f32
        for i in count do
            .accumulatePathLength(&.drawing.shapes[first + i], &actualLength)

        if actualLength <= 0 do
            return
        let scale = actualLength / (authoredLength * Math.abs(geometryScale))
        for i in count
        {
            let shape  = &.drawing.shapes[first + i]
            let stroke = .drawing.strokeFor(shape)
            if stroke and not stroke.sharedStyle
            {
                .scaleDashValues(stroke, scale)
                stroke.offset *= scale
            }
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
        if info.size <= MaxCachedRasterBytes
        {
            let key    = .sourceView(href)
            let cached = .externalImages.tryFind(key)
            if (cached or .externalImages.count < MaxCachedRasterFiles) and Image.canLoad(fullPath.toString())
            {
                let file     = try File.MappedFile.open(fullPath.toString())
                let fileSize = try file.size()
                if fileSize <= MaxCachedRasterBytes
                {
                    let region  = try file.mapAll()
                    let encoded = region.bytes()

                    // Check the contents of the current file before reusing earlier pixels.
                    if cached and
                       encoded.count == cached.value.encoded.count and
                       not Memory.compare(encoded.buffer, cached.value.encoded.storage(), encoded.count) do
                        return cached.value.index

                    var raster = #move try Image.decode(fullPath.toString(), encoded)
                    .drawing.rasterImages.add(#move raster)
                    let entry = .externalImages.findOrAdd(key)
                    entry.value.index = index
                    entry.value.encoded.clear()
                    entry.value.encoded.add(encoded)
                    return index
                }
            }
        }

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
            .drawing.items.add(DrawingItem{kind: .Image, index: index})
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
            .drawing.items.add(DrawingItem{kind: .Text, index: index})
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
            if state.clipPathId.count
            {
                state.clipTransform = state.transform
                state.hasClip       = true
            }

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
                    var segment: DeferredGeometry
                    if not hasMarkers and
                       not state.hasFill and
                       state.hasStroke and
                       state.canDeferPrimitive() and
                       d.value.count <= 64 do
                        segment = readStraightStroke(d.value, &state)
                    if segment.kind == .Line
                    {
                        var list: LinePathList
                        .emitShapeOne(#move list, &state, geometry: segment)
                    }
                    else
                    {
                        var list:     LinePathList
                        var vertices: Array'MarkerVertex

                        let linear = d.value.count >= 1024 and
                                     not hasMarkers and
                                     state.canDeferPrimitive() and
                                     not hasPathCurveCommand(d.value)
                        var segments: u64
                        parsePathData(&list, d.value, &state, hasMarkers ? &vertices : null, linear, &segments)
                        .emitShape(#move list, &state, segments)
                        if hasMarkers do
                            .applyMarkers(&state, vertices.toSlice())
                    }
                }

            case "rect":
                if state.drawsShape()
                {
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
                }

            case "circle":
                if state.drawsShape()
                {
                    let r = .geoNumber(&geo, .R)
                    .emitEllipse(&state, .geoNumber(&geo, .Cx), .geoNumber(&geo, .Cy), r, r)
                }

            case "ellipse":
                if state.drawsShape()
                {
                    .emitEllipse(&state,
                                 .geoNumber(&geo, .Cx),
                                 .geoNumber(&geo, .Cy),
                                 .geoNumber(&geo, .Rx),
                                 .geoNumber(&geo, .Ry))
                }

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
                        let from       = mapPoint(&state, x1, y1)
                        let target     = mapPoint(&state, x2, y2)
                        var strokeOnly = state
                        strokeOnly.hasFill = false
                        if strokeOnly.canDeferPrimitive() and
                           from.isFinite() and
                           target.isFinite() and
                           (target - from).isFinite()
                        {
                            .emitShapeOne(#move list, &strokeOnly, geometry: DeferredGeometry{.Line, from, target})
                        }
                        else
                        {
                            let path = list.newPath()
                            path.start(from.x, from.y)
                            path.lineTo(target.x, target.y)
                            .emitShape(#move list, &strokeOnly)
                        }
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

                        discard .instantiate(here.value.first, here.value.count, &useState, deferGeometry: true)
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
        discard .instantiate(definition.first, definition.count, &markerState, deferGeometry: true)
    }

    func clipHasCurves(paths: const *LinePathList)->bool
    {
        for path in paths.paths where path.hasCurves() do
            return true
        return false
    }

    // A clip made only of straight solid contours can reuse identical transformed geometry.
    // Keep the hidden shapes in parse order because a parent pathLength traverses that range.
    mtd instantiateClip(first, count: u64, state: *GroupState)->ClipRange
    {
        let previous       = &.lastClip
        let sameDefinition = previous.definition.first == first and previous.definition.count == count
        if sameDefinition and
           previous.shareable and
           Memory.compare(&previous.transform, &state.transform, #sizeof(Math.Transform2)) == 0
        {
            let firstCopy = .drawing.shapes.count
            for i in previous.placement.count
            {
                let shape = .drawing.shapes[previous.placement.first + i]
                .drawing.shapes.add(shape)
            }

            return ClipRange{firstCopy, previous.placement.count}
        }

        let range = .instantiate(first, count, state, hidden: true)
        if not sameDefinition
        {
            previous.definition = ClipRange{first, count}
            previous.shareable  = true
            for i in range.count
            {
                let shape = &.drawing.shapes[range.first + i]
                if shape.stroke or shape.fillPaintId or shape.filterId
                {
                    previous.shareable = false
                    break
                }

                if clipHasCurves(.drawing.pathsFor(shape))
                {
                    previous.shareable = false
                    break
                }
            }
        }

        previous.transform = state.transform
        previous.placement = ClipRange{range.first, range.count}
        return previous.placement
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
        let clip = .instantiateClip(definition.value.first, definition.value.count, &clipState)
        if clip.count == 0 do
            return

        let outer      = .drawing.storeClip(clip.first, clip.count)
        var intersections: HashTable'(s64, s64)
        var outside:       LinePathList
        var hasOutside = false
        for i in .drawing.items.count - firstItem
        {
            let item = &.drawing.items[firstItem + i]
            if not item.clip
            {
                item.clip = outer
                continue
            }

            let previous = item.clip
            if let found = intersections.tryFind(previous)
            {
                item.clip = found.value
                continue
            }

            let range  = .drawing.clipRange(previous)
            var inside = .clipGeometry(range.first, range.count)
            if not hasOutside
            {
                outside    = .clipGeometry(clip.first, clip.count)
                hasOutside = true
            }

            inside.intersect(&outside)
            var shape: Shape
            .drawing.storeContours(shape, #move inside)
            shape.hidden = true

            // An empty intersection is still a clip; zero would mean unbounded ink.
            item.clip = .drawing.storeClip(.drawing.shapes.count, 1)
            .drawing.shapes.add(#move shape)
            intersections.add(previous, item.clip)
        }
    }

    // Normalize each clip shape before unioning its contours, so independently authored
    // winding directions do not turn overlapping clip shapes into holes.
    mtd clipGeometry(first, count: u64)->LinePathList
    {
        var result: #returntype
        for index in first until first + count
        {
            var shape = .drawing.pathsFor(&.drawing.shapes[index])[]
            shape.flatten(.High)
            shape.clean(.drawing.shapes[index].evenOdd ? .EvenOdd : .NonZero)
            for path in shape.paths do
                result.newPath()[] = path[]
        }

        return result
    }

    mtd const paintTransformAt(index: u64)->Math.Transform2
    {
        return index ? .paintTransforms[index - 1] : Math.Transform2.Identity
    }

    mtd storePaintTransform(transform: const *Math.Transform2)->u64
    {
        let identity = Math.Transform2.Identity
        if Memory.compare(transform, &identity, #sizeof(Math.Transform2)) == 0 do
            return 0

        let count = .paintTransforms.count
        if count and Memory.compare(transform, &.paintTransforms[count - 1], #sizeof(Math.Transform2)) == 0 do
            return count

        .paintTransforms.add(transform[])
        return count + 1
    }

    mtd gradientCoordinate(length: SvgLength, begin, extent, viewportExtent: f32, userSpace: bool)->f32
    {
        if userSpace do
            return length.isPercent ? length.value * viewportExtent : length.value
        return begin + length.value * extent
    }

    mtd gradientPoint(gradient: const *Gradient, transform: const *Math.Transform2, x, y: SvgLength, boundsMin, boundsSize: Vector2)->Vector2
    {
        let px = .gradientCoordinate(x, boundsMin.x, boundsSize.x, .drawing.width, gradient.userSpace)
        let py = .gradientCoordinate(y, boundsMin.y, boundsSize.y, .drawing.height, gradient.userSpace)

        // A user-space stop is a point of the element's own coordinate system, so it goes
        // through the gradient's transform and then through the element's.
        if gradient.userSpace do
            return transform.transformPoint(gradient.transform.transformPoint(Vector2{px, py}))

        // An object-bounding-box stop is a fraction of the shape's extent, and the gradient
        // transform applies in that unit square before it is stretched back over the bounds.
        let unit = gradient.transform.transformPoint(Vector2{(px - boundsMin.x) / Math.max(boundsSize.x, 0.000001), (py - boundsMin.y) / Math.max(boundsSize.y, 0.000001)})
        return Vector2{boundsMin.x + unit.x * boundsSize.x, boundsMin.y + unit.y * boundsSize.y}
    }

    mtd gradientBrush(gradient: const *Gradient, transform: const *Math.Transform2, min, max: Vector2)->Brush
    {
        if gradient.stops.isEmpty() do
            return Brush.createSolid(Color.fromArgb(Argb.Zero))

        let size = max - min

        var result: #returntype
        result.color = Color.fromArgb(Argb.White)
        result.gradientSpread = gradient.spread
        switch gradient.kind
        {
        case .Linear:
            result.type          = .LinearGradient
            result.gradientStart = .gradientPoint(gradient, transform, gradient.x1, gradient.y1, min, size)
            result.gradientEnd   = .gradientPoint(gradient, transform, gradient.x2, gradient.y2, min, size)

        case .Radial:
            result.type          = .RadialGradient
            result.gradientStart = .gradientPoint(gradient, transform, gradient.cx, gradient.cy, min, size)
            result.gradientEnd   = result.gradientStart

            if gradient.userSpace
            {
                let viewportDiagonal = Math.sqrt(.drawing.width * .drawing.width + .drawing.height * .drawing.height) / Math.ConstF32.Sqrt2
                let radius           = gradient.r.isPercent ? gradient.r.value * viewportDiagonal : gradient.r.value
                let inner            = gradient.fr.isPercent ? gradient.fr.value * viewportDiagonal : gradient.fr.value
                let radiusScale      = transformScale(gradient.transform) * transformScale(transform[])
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

    mtd storeGradient(gradient: *Gradient, shape: *Shape, opacity: f32, paintTransform: u64)->u64
    {
        var min = Vector2.Max
        var max = Vector2.Min
        if shape.deferred == .Rect
        {
            let rect = &.drawing.primitives[shape.geometry - 1]
            min = rect.first
            max = rect.second
        }
        elif gradient.userSpace
        {
            // Preserve the decode-time curve tolerance for the first paint at draft quality.
            for path in .drawing.pathsFor(shape).paths where path.hasCurves() do
                path.flattenPoints(.Normal, 1)
        }
        else
        {
            // A bounding-box gradient needs the flattened bounds. Polygon simplicity, winding
            // and tessellation are only needed when the contour is actually painted.
            for path in .drawing.pathsFor(shape).paths
            {
                path.flattenPoints(.Normal, 1)
                min = Vector2.min(min, path.minBounds)
                max = Vector2.max(max, path.maxBounds)
            }
        }

        let transform = .paintTransformAt(paintTransform)

        // User-space coordinates depend on the transform, independently of the shape bounds.
        if gradient.userSpace and
           gradient.cachedBrush and
           gradient.cachedOpacity == opacity and
           Memory.compare(&gradient.cachedTransform, &transform, #sizeof(Math.Transform2)) == 0 do
            return gradient.cachedBrush

        var entry: SvgGradientBrush
        entry.brush = .gradientBrush(gradient, &transform, min, max)
        entry.brush.multiplyOpacity(opacity)
        if gradient.stops.count
        {
            if not gradient.cachedStops
            {
                .drawing.gradientStops.add(gradient.stops)
                gradient.cachedStops = .drawing.gradientStops.count
            }

            entry.stops = gradient.cachedStops
        }

        .drawing.gradientBrushes.add(#move entry)
        let index = .drawing.gradientBrushes.count
        if gradient.userSpace
        {
            gradient.cachedBrush     = index
            gradient.cachedTransform = transform
            gradient.cachedOpacity   = opacity
        }

        return index
    }

    mtd resolvePaints()
    {
        for &shape in .drawing.shapes
        {
            let paintTransform = shape.paintTransform
            if paintTransform do
                shape.fillGradient = 0
            if shape.hasFill and shape.fillPaintId
            {
                if let gradient = .gradients.tryFind(.referenceNames[shape.fillPaintId - 1]) do
                    shape.fillGradient = .storeGradient(&gradient.value, shape, shape.fillOpacity, paintTransform)
                elif .patterns.tryFind(shape.fillPaintId) do
                    shape.fillColor = applyPaintOpacity(Color.fromArgb(Argb.White), shape.fillOpacity)
                else do
                    shape.hasFill = false
            }

            let stroke = .drawing.strokeFor(shape)
            if stroke and stroke.paintId
            {
                if let gradient = .gradients.tryFind(.referenceNames[stroke.paintId - 1]) do
                    stroke.gradient = .storeGradient(&gradient.value, shape, stroke.opacity, paintTransform)
                else do
                    stroke.enabled = false
            }
        }
    }

    // Appends transformed copies of a definition's shapes and reports the range they occupy.
    //
    // `state` carries the complete transform the copies are placed under, so a `use` offset, a
    // `symbol` viewport and a clip reference all reach here the same way. `hidden` withholds the
    // copies from the paint order, which is what a clip needs: its shapes exist as geometry and
    // are never drawn.
    mtd deferInstance(source: u64, paths: const *LinePathList, transform: Math.Transform2)->u64
    {
        if paths.paths.isEmpty() do
            return 0

        var bounds: InstanceBounds
        if let cached = .instanceBounds.tryFind(source)
        {
            bounds = cached.value
        }
        else
        {
            let rect  = paths.controlBounds()
            let first = Vector2{rect.x, rect.y}
            let last  = Vector2{rect.right(), rect.bottom()}

            // The rectangle stores extent instead of the upper corner. Expand both ends
            // enough to cover its reconstruction and the arithmetic of an authored arc.
            let extent  = Vector2.max(Vector2{Math.abs(first.x), Math.abs(first.y)}, Vector2{Math.abs(last.x), Math.abs(last.y)})
            let padding = extent * (8 * Math.ConstF32.Epsilon) + Vector2{0.0001, 0.0001}
            bounds.min = first - padding
            bounds.max = last + padding

            // A turned or sheared ellipse uses cubic controls. Their tangent component is
            // at most 0.553 radii, so they stay within 1.143 radii on either source axis.
            for path in paths.paths
            {
                for &element in path.elements where element.type == .Arc do
                    bounds.arcPadding = Vector2.max(bounds.arcPadding, Vector2{Math.abs(element.p2.x), Math.abs(element.p2.y)} * 0.25)
            }

            .instanceBounds.add(source, bounds)
        }

        var min, max: Vector2
        if transform.m12 == 0 and transform.m21 == 0 and transform.m11 > 0 and transform.m22 > 0
        {
            min = transform.transformPoint(bounds.min)
            max = transform.transformPoint(bounds.max)
        }
        else
        {
            let low  = bounds.min - bounds.arcPadding
            let high = bounds.max + bounds.arcPadding
            let p0   = transform.transformPoint(low)
            let p1   = transform.transformPoint(Vector2{low.x, high.y})
            let p2   = transform.transformPoint(Vector2{high.x, low.y})
            let p3   = transform.transformPoint(high)
            if not p0.isFinite() or not p1.isFinite() or not p2.isFinite() or not p3.isFinite() do
                return 0
            min = Vector2.min(Vector2.min(p0, p1), Vector2.min(p2, p3))
            max = Vector2.max(Vector2.max(p0, p1), Vector2.max(p2, p3))
        }

        if not min.isFinite() or not max.isFinite() or not (max - min).isFinite() do
            return 0

        .drawing.instances.add(DeferredInstance{source, transform, min, max})
        return .drawing.instances.count
    }

    mtd instantiate(first, count: u64, state: *GroupState, hidden = false, deferGeometry = false)->{ first: u64, count: u64 }
    {
        var result: #returntype
        result.first = .drawing.shapes.count

        let deferPlacement = deferGeometry and not hidden and not state.inDefs
        for i in count
        {
            // Build the transformed copy fully before appending: appending can
            // reallocate the array and invalidate the source borrow.
            var list:             LinePathList
            var fillColor:        Color
            var fillPaintId, filterId, strokeIndex: u64
            var fillOpacity:      f32
            var hasFill, evenOdd: bool
            var paintTransform:   u64
            var instance:         u64

            scope
            {
                let src = &.drawing.shapes[first + i]
                fillPaintId = src.fillPaintId
                filterId    = src.filterId
                if fillPaintId do
                    fillOpacity = src.fillOpacity
                else do
                    fillColor = src.fillColor
                hasFill = src.hasFill
                evenOdd = src.evenOdd
                var hasPaintReference = fillPaintId != 0
                if let original = .drawing.strokeFor(src)
                {
                    let scale = transformScale(state.transform)
                    hasPaintReference = hasPaintReference or original.paintId != 0
                    if original.sharedStyle and scale == 1
                    {
                        strokeIndex = src.stroke
                    }
                    else
                    {
                        var stroke = original[]
                        stroke.sharedStyle = false
                        stroke.width       *= scale
                        stroke.offset      *= scale
                        if stroke.pattern.count
                        {
                            // A copied range can be the source of a cached calibration.
                            // Later calibrations must leave that source unchanged.
                            stroke.sharedPattern   = true
                            original.sharedPattern = true
                            .scaleDashValues(&stroke, scale)
                        }

                        .drawing.strokes.add(stroke)
                        strokeIndex = .drawing.strokes.count
                    }
                }

                if hasPaintReference
                {
                    // Compose the definition's paint space with the instance's, including its offset.
                    var transform = .paintTransformAt(src.paintTransform)
                    transform.multiply(state.transform)
                    paintTransform = .storePaintTransform(&transform)
                }

                let paths = .drawing.pathsFor(src)
                if deferPlacement and
                   (hasFill or strokeIndex) and
                   not hasPaintReference and
                   not filterId
                {
                    instance = .deferInstance(first + i, paths, state.transform)
                }

                if not instance do
                    copyContours(&list, paths, state)
            }

            let shapeIndex = .drawing.shapes.count
            with let shape = .drawing.shapes.emplaceInitAddress()
            {
                .fillPaintId = fillPaintId
                if fillPaintId do
                    .fillOpacity = fillOpacity
                else do
                    .fillColor = fillColor
                .hasFill        = hasFill
                .evenOdd        = evenOdd
                .stroke         = strokeIndex
                .paintTransform = paintTransform
                .hidden         = hidden or state.inDefs
                .filterId       = filterId
                if instance
                {
                    .deferred = .Instance
                    .geometry = instance
                }
                else
                {
                    me.drawing.storeContours(shape, #move list)
                }
            }

            if not shape.hidden do
                .drawing.items.add(DrawingItem{kind: .Shape, index: shapeIndex, refineBounds: instance != 0})
        }

        result.count = .drawing.shapes.count - result.first
        return result
    }
}

#[Swag.Inline]
private func copyContours(destination: *LinePathList, source: const *LinePathList, state: *GroupState)
{
    for srcPath in source.paths
    {
        let path   = destination.newPath()
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

// How far outside its geometry an antialiased edge lays its fringe, which a rectangle tested
// against a viewport is widened by so an item touching the edge is never rejected.
private const InkFringeMargin = 2.0'f32

private impl Drawing
{
    mtd const pathsFor(shape: const *Shape)->*LinePathList
    {
        let index = shape.geometry - 1
        return &.contours[index / ContourChunkSize][index % ContourChunkSize]
    }

    mtd storeContours(shape: *Shape, paths: #move LinePathList)
    {
        if .contourCount % ContourChunkSize == 0 do
            .contours.emplaceInitAddress().reserve(ContourChunkSize)
        .contours.backPtr().add(#move paths)
        .contourCount  += 1
        shape.geometry = .contourCount
    }

    mtd const materializeShape(shape: const *Shape)->*LinePathList
    {
        if shape.deferred == .None do
            return .pathsFor(shape)

        if shape.deferred == .Instance
        {
            let instance = &.instances[shape.geometry - 1]
            if not instance.contours.paths
            {
                let paths = Memory.new'LinePathList()
                var state = GroupState{transform: instance.transform}
                copyContours(paths, .pathsFor(&.shapes[instance.source]), &state)
                instance.contours.paths = paths
            }

            return instance.contours.paths
        }

        let primitive = &.primitives[shape.geometry - 1]
        if not primitive.contours.paths
        {
            let paths  = Memory.new'LinePathList()
            let first  = primitive.first
            let second = primitive.second
            let path   = paths.newPath()
            if shape.deferred == .Rect
            {
                path.setRectCornersRaw(first.x, first.y, second.x, second.y)
            }
            elif shape.deferred == .Ellipse
            {
                path.setEllipseRaw(first.x, first.y, second.x, second.y)
            }
            else
            {
                path.start(first.x, first.y)
                path.lineTo(second.x, second.y)
            }

            primitive.contours.paths = paths
        }

        return primitive.contours.paths
    }

    mtd const strokeFor(shape: const *Shape)->*ShapeStroke?
    {
        return shape.stroke ? &.strokes[shape.stroke - 1] : null
    }

    // Returns the rectangle this shape can ink, its contours plus whatever a stroke adds
    // around them.
    mtd const shapeInkBounds(shape: const *Shape, materialized = false)->Rectangle
    {
        var result: #returntype
        if materialized
        {
            result = .materializeShape(shape).controlBounds()
        }
        elif shape.deferred != .None
        {
            var min, max: Vector2
            if shape.deferred == .Instance
            {
                let instance = &.instances[shape.geometry - 1]
                min = instance.min
                max = instance.max
            }
            else
            {
                let primitive = &.primitives[shape.geometry - 1]
                let first     = primitive.first
                let second    = primitive.second
                min = first
                max = second
                if shape.deferred == .Line
                {
                    min = Vector2.min(first, second)
                    max = Vector2.max(first, second)
                }
                elif shape.deferred == .Ellipse
                {
                    min = first - second
                    max = first + second
                }
            }

            let size = max - min
            result = Rectangle{min.x, min.y, size.x, size.y}
        }
        elif shape.scanFill
        {
            return .scanFills[shape.scanFill - 1].bounds
        }
        else
        {
            result = .pathsFor(shape).controlBounds()
        }

        let stroke = .strokeFor(shape)
        if stroke and stroke.enabled
        {
            // Half the width lies either side of the contour, and a miter join reaches at
            // most the miter limit past a corner. A cap never reaches further than a join.
            let margin = Math.abs(stroke.width) * 0.5 * Math.max(stroke.miter, 1.0'f32)
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
    mtd opDrop()
    {
        for &primitive in .primitives do
            primitive.contours.release()
        for &instance in .instances do
            instance.contours.release()
    }

    mtd opPostCopy()
    {
        for &primitive in .primitives do
            primitive.contours.duplicate()
        for &instance in .instances do
            instance.contours.duplicate()
    }

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
        result.preferScanFills = options.preferScanFills

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
        if result.items.count >= PaintBlockSize * 64
        {
            var index: PaintIndex
            result.measurePaintBins(&index.bins)
            if not index.bins.isEmpty() or result.texts.count do
                result.paintIndex.add(#move index)
        }

        return result
    }

    // Records what each item can ink, so painting can reject the ones a viewport misses.
    //
    // Shapes and pictures are bounded from the geometry the parser produced. A text block is
    // left unmeasured: its runs are placed by the advances of the runs before them, which only
    // shaping can give, so the first paint measures it and every later one rejects it.
    private mtd measureItems()
    {
        var clip:       s64
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
                item.bounds    = .shapeInkBounds(shape)
                item.hasBounds = true

            case .Image:
                let image = &.images[item.index]
                item.bounds    = image.transform.transformBounds(image.rect)
                item.hasBounds = true

            case .Text:
                break
            }

            if item.hasBounds and item.clip
            {
                // A group can apply the same complex clip to every one of its children.
                if not .sameClip(item.clip, clip)
                {
                    clip       = item.clip
                    clipBounds = .clipRangeBounds(clip)
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

    // Bucket widely dispersed items by centre, using both axes for near-square drawings.
    private mtd const measurePaintBins(bins: *Array'PaintBin, measuredText = false)
    {
        if .items.count > Swag.U32.Max do
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
        let spread = cast(f64, .paintBlocks.count) * 0.25
        if extent <= 0 or span < extent * spread do
            return

        // Near-square drawings spread through their authored runs on both axes.
        let square  = width > 0 and height > 0 and width <= height * 4 and height <= width * 4
        let useGrid = square and spanX >= width * spread and spanY >= height * spread

        // Text arranged in rows or columns is already culled by its measured runs.
        if measuredText and square and not useGrid do
            return

        const GridRows = PaintBinCount / PaintGridColumns
        let densityX = useGrid ? cast(f64, PaintGridColumns) / width : 0.0
        let densityY = useGrid ? cast(f64, GridRows) / height : 0.0

        bins.resize(PaintBinCount)
        let density  = cast(f64, PaintBinCount) / extent
        var occupied = 0
        for &item, index in .items
        {
            let first = Vector2{item.bounds.x, item.bounds.y}
            let last  = Vector2{item.bounds.right(), item.bounds.bottom()}
            var bucket: u64
            if useGrid
            {
                let centreX = (cast(f64, first.x) + last.x) * 0.5
                let centreY = (cast(f64, first.y) + last.y) * 0.5
                let column  = cast(u64, Math.clamp((centreX - minimum.x) * densityX, 0.0'f64, cast(f64, PaintGridColumns - 1)))
                let row     = cast(u64, Math.clamp((centreY - minimum.y) * densityY, 0.0'f64, cast(f64, GridRows - 1)))
                bucket = row * PaintGridColumns + column
            }
            else
            {
                let centre = useY ? (cast(f64, first.y) + last.y) * 0.5 : (cast(f64, first.x) + last.x) * 0.5
                bucket = cast(u64, Math.clamp((centre - origin) * density, 0.0'f64, cast(f64, PaintBinCount - 1)))
            }

            let bin   = &bins[bucket]
            let lower = Vector2.min(first, last)
            let upper = Vector2.max(first, last)
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

            bin.indices.add(cast(u32, index))
        }

        if occupied <= 1 do
            bins.free()
    }

    // Collect the spatial candidates in authored order when only a small portion is visible.
    private mtd const collectPaintCandidates(transform: Transform2, visible: Rectangle, axisAligned: bool, candidates: *Array'u32)->bool
    {
        if .paintIndex.isEmpty() do
            return false
        let bins = .paintIndex[0].bins.toSlice()
        if not bins.count do
            return false

        var selected: StaticArray'(u64, PaintBinCount)
        var count = 0'u64
        for &bin, index in bins where bin.indices.count and not bin.bounds.misses(transform, visible, axisAligned)
        {
            count += bin.indices.count
            if count > .items.count / 4 do
                return false
            selected.add(index)
        }

        candidates.reserve(count)
        for index in selected do
            candidates.add(bins[index].indices.toSlice())
        if selected.count > 1 do
            candidates.sort()
        return true
    }

    private mtd storeClip(first, count: u64)->s64
    {
        if count == 1 do
            return cast(s64, first) + 1

        .clipRanges.add(ClipRange{first, count})
        return -cast(s64, .clipRanges.count)
    }

    private mtd const clipRange(clip: s64)->ClipRange
    {
        if clip > 0 do
            return ClipRange{cast(u64, clip - 1), 1}
        if clip < 0 do
            return .clipRanges[cast(u64, -clip - 1)]
        return {}
    }

    // When a whole placement is shared, its first shape's contour identifies the placement.
    private mtd const sameClip(left, right: s64)->bool
    {
        if left == right do
            return true
        if not left or not right do
            return false

        let a = .clipRange(left)
        let b = .clipRange(right)
        return a.count == b.count and .shapes[a.first].geometry == .shapes[b.first].geometry
    }

    // Returns the rectangle a clip range can keep, which is the union of its shapes.
    private mtd const clipRangeBounds(clip: s64)->Rectangle
    {
        let range = .clipRange(clip)
        var result: #returntype
        for i in range.count
        {
            let bounds = .pathsFor(&.shapes[range.first + i]).controlBounds()
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

    // Materializes the shared stops when this placement first reaches the painter.
    private mtd const gradientBrushAt(index: u64)->*Brush
    {
        let entry = &.gradientBrushes[index - 1]
        if entry.stops and entry.brush.gradientStops.isEmpty() do
            entry.brush.gradientStops = .gradientStops[entry.stops - 1]
        return &entry.brush
    }

    private mtd const paintShapeCore(painter: *Painter, shape: *Shape, paintFill = true)
    {
        let paths = .materializeShape(shape)
        if paintFill and shape.hasFill
        {
            if shape.scanFill do
                .scanFills[shape.scanFill - 1].paint(painter, paths, shape.fillColor, shape.evenOdd)
            elif shape.fillGradient do
                painter.fillPath(paths, .gradientBrushAt(shape.fillGradient)[])
            else do
                painter.fillPath(paths, shape.fillColor)
        }

        let stroke = .strokeFor(shape)
        if stroke and stroke.enabled
        {
            var pen: Pen
            if stroke.gradient do
                pen.brush = .gradientBrushAt(stroke.gradient)[]
            else do
                pen.brush.color = stroke.color

            pen.size           = stroke.width
            pen.begCapStyle    = stroke.capStyle
            pen.endCapStyle    = stroke.capStyle
            pen.joinStyle      = stroke.joinStyle
            pen.joinMiterLimit = stroke.miter
            pen.dashOffset     = stroke.offset
            if stroke.pattern.count
            {
                let range = stroke.pattern
                pen.pattern.add(.dashValues.toSlice()[range.first until range.first + range.count])
                if Math.abs(stroke.width) > 0.000001
                {
                    for &value in pen.pattern do
                        value[] /= Math.abs(stroke.width)
                }

                pen.dashStyle = .Pattern
            }

            painter.drawPath(paths, pen, .Separate)
        }
    }

    private mtd const rasterizePatternTile(pattern: const *Pattern, key: const *PatternTileKey, pixelWidth, pixelHeight: s32)->Image
    {
        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        cpu.begin(pixelWidth, pixelHeight)
        var target      = renderer.createRenderTarget(pixelWidth, pixelHeight)
        var tilePainter = Painter.create(renderer)
        tilePainter.begin()
        tilePainter.bindRenderTarget(&target, paintAlpha: false)
        tilePainter.setColorMaskFull()
        tilePainter.clear(Color.fromArgb(Argb.Zero))
        for copyY in 3
        {
            for copyX in 3
            {
                let offsetX       = cast(f32, (cast(s32, copyX) - 1)) * key.size.x
                let offsetY       = cast(f32, (cast(s32, copyY) - 1)) * key.size.y
                var tileTransform = Math.Transform2.createTranslation(-key.origin.x - key.phase.x + offsetX, -key.origin.y - key.phase.y + offsetY)
                tileTransform.multiply(Math.Transform2.createScale(key.scale, key.scale, 0, 0))
                tilePainter.setTransform(tileTransform)
                for i in pattern.count do
                    .paintShapeCore(&tilePainter, &.shapes[pattern.first + i])
            }
        }

        tilePainter.unbindRenderTarget()
        tilePainter.end()
        expect renderer.draw(&tilePainter)

        let result = renderer.readRenderTarget(&target, 0, 0, pixelWidth, pixelHeight)
        renderer.deleteRenderTarget(&target)
        renderer.end()
        return result
    }

    private mtd const paintPattern(painter: *Painter, shape: *Shape, pattern: const *Pattern, cache: *PatternRaster? = null)
    {
        let paths = .materializeShape(shape)
        paths.flatten(.Normal)
        var min = Vector2.Max
        var max = Vector2.Min
        for path in paths.paths
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

        let rasterScale = Math.max(painter.contentScale(), 1.0'f32)
        let pixelWidth  = cast(s32, Math.max(Math.ceil(tileWidth * rasterScale), 1.0'f32))
        let pixelHeight = cast(s32, Math.max(Math.ceil(tileHeight * rasterScale), 1.0'f32))
        let phaseX      = min.x - tileX - Math.floor((min.x - tileX) / tileWidth) * tileWidth
        let phaseY      = min.y - tileY - Math.floor((min.y - tileY) / tileHeight) * tileHeight
        let key         = PatternTileKey{shape.fillPaintId, Vector2{tileX, tileY}, Vector2{phaseX, phaseY}, Vector2{tileWidth, tileHeight}, rasterScale}
        var localImage: Image
        var tile:       const *Image = &localImage

        // Small user-space tiles can repeat across aligned shapes in the same paint.
        if cache and
           pattern.userSpace and
           pixelWidth > 0 and
           pixelHeight > 0 and
           pixelWidth <= 256 and
           pixelHeight <= 256
        {
            if not cache.image.isValid() or Memory.compare(&cache.key, &key, #sizeof(PatternTileKey)) != 0
            {
                cache.image = .rasterizePatternTile(pattern, &key, pixelWidth, pixelHeight)
                cache.key   = key
            }

            tile = &cache.image
        }
        else
        {
            localImage = .rasterizePatternTile(pattern, &key, pixelWidth, pixelHeight)
        }

        let texture = painter.renderer().addImage(tile[])
        var brush   = Brush.createTiled(texture)

        painter.fillPath(paths, brush)
        painter.releaseTexture(texture)
    }

    // Paints one text block and returns the drawing-space rectangle its runs covered.
    private mtd const paintText(painter: *Painter, text: const *SvgText, scratch: *SvgTextScratch, visible: Rectangle, clipRuns: bool)->Rectangle
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

            // Repeated labels can be measured without shaping their glyphs again. The cache
            // lives for this paint and only keeps runs which use one font for every glyph.
            let authored      = run.text.toString()
            let canCache      = clipRuns and scratch.remainingLookups and authored.count <= 96
            let letterSpacing = cast #bit(u32, run.letterSpacing)
            let wordSpacing   = cast #bit(u32, run.wordSpacing)
            let cached        = canCache ? scratch.measurements.tryFind(authored) : null
            let reuse         = cached and
                                cached.value.font == font and
                                cached.value.letterSpacing == letterSpacing and
                                cached.value.wordSpacing == wordSpacing

            // Stop probing after a long run of labels with no reusable measurements.
            if canCache do
                scratch.remainingLookups = reuse ? TextMeasureCacheSize : scratch.remainingLookups - 1

            var metrics: StringMetrics
            if reuse
            {
                metrics = cached!.value.metrics
            }
            else
            {
                Painter.shapeRunInto(&scratch.shaped, authored, font, letterSpacing: run.letterSpacing, wordSpacing: run.wordSpacing)
                metrics = Painter.measureString(&scratch.shaped)
                if canCache and (cached or scratch.measurements.count < TextMeasureCacheSize)
                {
                    var primary = true
                    for glyph in scratch.shaped.glyphs where glyph.font and glyph.font != font
                    {
                        primary = false
                        break
                    }

                    if primary do
                        scratch.measurements.add(authored, SvgTextMeasure{font, metrics, letterSpacing, wordSpacing})
                }
            }

            var offset = advance
            if run.anchor == .Middle do
                offset -= metrics.width * 0.5
            elif run.anchor == .End do
                offset -= metrics.width

            // The run is drawn from `font.ascent` above the baseline; its glyphs can reach a
            // little past the recommended extents either way, so the box takes the larger of
            // the two and a margin of its own.
            let above   = Math.max(font.ascent, metrics.ascent)
            let below   = Math.max(font.descent, metrics.descent)
            let rotated = Math.abs(run.rotation) > 0.0001
            var runBox  = Rectangle{origin.x + offset, origin.y - above, metrics.width, above + below}
            runBox.inflate(run.fontSize * 0.5)
            var rotation: Transform2
            if rotated
            {
                rotation = Transform2.createRotation(run.rotation, origin.x, origin.y)
                runBox   = rotation.transformBounds(runBox)
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

            advance += metrics.width
            if clipRuns
            {
                var painted = painter.transform().transformBounds(runBox)
                painted.inflate(InkFringeMargin)
                if not visible.intersects(painted) do
                    continue
            }

            if rotated
            {
                // Rotate around the baseline after measuring the upright text run.
                painter.pushState()
                rotation.multiply(painter.transform())
                painter.setTransform(rotation)
            }

            let color = run.color.withAlphaF32(run.opacity)
            if reuse do
                Painter.shapeRunInto(&scratch.shaped, authored, font, letterSpacing: run.letterSpacing, wordSpacing: run.wordSpacing)
            painter.drawShapedRun(origin.x + offset, origin.y - font.ascent, &scratch.shaped, font, Brush.createSolid(color))
            if rotated do
                painter.popState()
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

        #[Swag.Inline]
        func missesPaintViewport(bounds: Rectangle, transform: Transform2, visible: Rectangle, axisAligned: bool)->bool
        {
            var painted = axisAligned ? transformAxisAlignedBounds(transform, bounds) : transform.transformBounds(bounds)
            painted.inflate(InkFringeMargin)
            return not visible.intersects(painted)
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

        // Keep the clipping region across consecutive items that share it.
        var activeClip: s64

        // What the painter can still reach, in surface space. An item landing outside it is
        // not drawn, and does not stamp its clip either: a document is normally much larger
        // than the window showing it, and a rejected item costs a rectangle test instead of
        // all of its geometry.
        let visible = painter.clippingRect()

        let axisAligned  = tr.m12 == 0 and tr.m21 == 0
        let useBlocks    = .paintBlocks.count and painter.hasClippingRect()
        var candidates:    Array'u32
        let useBins      = useBlocks and .collectPaintCandidates(tr, visible, axisAligned, &candidates)
        let useRuns      = useBlocks and not useBins
        var textScratch:   SvgTextScratch
        var patternRaster: PatternRaster
        var measuredText = false
        for blockIndex in (useRuns ? .paintBlocks.count : 1'u64)
        {
            var first = 0'u64
            var end   = useBins ? candidates.count : .items.count
            if useRuns
            {
                if .paintBlocks[blockIndex].misses(tr, visible, axisAligned) do
                    continue
                first = blockIndex * PaintBlockSize
                end   = first + Math.min(PaintBlockSize, .items.count - first)
            }

            for i in first until end
            {
                let itemIndex = useBins ? cast(u64, candidates[i]) : i
                let item      = &.items[itemIndex]
                if item.hasBounds
                {
                    if missesPaintViewport(item.bounds, tr, visible, useBlocks and axisAligned) do
                        continue

                    // A conservative bound can make an offscreen reference exchange the active
                    // clip. Use the bounds of an eager contour copy before changing the clip.
                    if item.refineBounds
                    {
                        item.bounds = .shapeInkBounds(&.shapes[item.index], materialized: true)
                        if item.clip do
                            item.bounds.intersect(.clipRangeBounds(item.clip))
                        item.refineBounds = false
                        if missesPaintViewport(item.bounds, tr, visible, useBlocks and axisAligned) do
                            continue
                    }
                }

                if not .sameClip(item.clip, activeClip)
                {
                    .setPaintClip(painter, item.clip)
                    activeClip = item.clip
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
                        .paintPattern(painter, shape, &pattern.value, &patternRaster)
                        .paintShapeCore(painter, shape, false)
                    }
                    else
                    {
                        .paintShapeCore(painter, shape)
                    }

                case .Text:
                    let inked = .paintText(painter, &.texts[item.index], &textScratch, visible, painter.hasClippingRect())

                    // Where the runs landed is what the block covers, and it is the same at every
                    // scale because a run is shaped in its own upright space.
                    if not item.hasBounds
                    {
                        item.bounds = inked
                        if item.clip do
                            item.bounds.intersect(.clipRangeBounds(item.clip))
                        item.hasBounds = true
                        measuredText   = true
                    }

                case .Image:
                    .paintImage(painter, &.images[item.index])
                }
            }
        }

        painter.resetClippingRegion()

        // Use the new text bounds to cull both authored runs and spatial bins.
        if measuredText
        {
            for &block, index in .paintBlocks where not block.bounded do
                block[] = .measurePaintBlock(index * PaintBlockSize)
            if .paintIndex.count and .paintIndex[0].bins.isEmpty() do
                .measurePaintBins(&.paintIndex[0].bins, measuredText: true)
        }
    }

    // Starting a region clears the previous mask. Resetting disables it.
    private mtd const setPaintClip(painter: *Painter, incoming: s64)
    {
        if not incoming
        {
            painter.resetClippingRegion()
            return
        }

        let white = Brush.createSolid(Color.fromArgb(Argb.White))
        let range = .clipRange(incoming)
        painter.startClippingRegion(.Set)
        for i in range.count do
            painter.fillPath(.pathsFor(&.shapes[range.first + i]), white)
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
        renderer.init()
        var result = .rasterizeWithSampleTileSide(renderer, width, height, supersample, RasterSampleTileSide, &cpu)
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
    internal mtd const rasterizeWithSampleTileSide(renderer: IRenderer, width, height: s32, supersample: u8, sampleTileSide: s32, cpu: *RenderCpu? = null)->Image
    {
        Swag.assert(width > 0 and height > 0)
        Swag.assert(sampleTileSide > 0)

        let ss = cast(s32, Math.max(supersample, 1'u8))
        if cpu and
           .preferScanFills and
           (ss == 1 or
            (width <= sampleTileSide / ss and height <= sampleTileSide / ss))
        {
            let ink = .monochromeScanInk()
            if ink != Swag.U32.Max
            {
                let samples = .rasterizeScanFills(width * ss, height * ss, sampleTileSide)
                if ss == 1 or not samples.isValid() do
                    return samples
                return resolveScanFillSamples(&samples, width, height, ss, ink)
            }
        }

        let tileWidth     = Math.min(width, Math.max(sampleTileSide / ss, 1))
        let tileHeight    = Math.min(height, Math.max(sampleTileSide / ss, 1))
        let sampledWidth  = tileWidth * ss
        let sampledHeight = tileHeight * ss
        let mask          = .rasterMask()
        let paired        = cpu != null and ss == 1 and mask == .Color and .canShareMatteCoverage()

        // Strokes use destination alpha as scratch. Recover source-over coverage from two
        // opaque mattes instead: white minus black is the uncovered fraction. Each matte
        // preserves the authored colors and clips, including translucent overlaps.
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
        var whiteMatte: RenderTarget
        if paired do
            whiteMatte = renderer.createRenderTarget(sampledWidth, sampledHeight)
        defer if paired do
            renderer.deleteRenderTarget(&whiteMatte)
        if paired and not whiteMatte.colorBuffer.isValid() do
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
                for matte in (mask != .Color or paired ? 1 : 2)
                {
                    var painter = Painter.create(renderer)
                    painter.begin()
                    painter.bindRenderTarget(&sampled)
                    painter.setColorMaskFull()
                    painter.clear(Color.fromArgb(matte == 0 and mask != .Black ? Argb.Black : Argb.White))
                    painter.setColorMaskColor()
                    painter.pushClippingSurfaceRect({0, 0, cast(f32, sampledWidth), cast(f32, sampledHeight)})
                    .paintImpl(&painter, cast(f32, (-tileX * ss)), cast(f32, (-tileY * ss)), cast(f32, (width * ss)) / .width)
                    painter.popClippingRect()

                    if ss > 1
                    {
                        // The resolve needs opaque samples after strokes use alpha as scratch.
                        // Direct readback consumes only the matte's color channels.
                        painter.setColorMaskAlpha()
                        painter.setBlendingMode(.Copy)
                        painter.fillRect(Rectangle{0, 0, cast(f32, sampledWidth), cast(f32, sampledHeight)}, Argb.White)
                    }

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
                    if paired do
                        cpu!.beginSvgMattes(whiteMatte.colorBuffer)
                    defer if paired do
                        cpu!.endSvgMattes()
                    catch renderer.draw(&painter) { return {} }

                    // Render-target readbacks and images share the bottom-up row convention. Copy
                    // each tile into the matching bottom-up rows of the complete result.
                    mattes[matte] = ss == 1 ? renderer.readRenderTarget(&sampled, 0, 0, copyWidth, copyHeight) : renderer.readRenderTarget(&resolved, 0, 0, copyWidth, copyHeight)
                    if not mattes[matte].isValid() do
                        return {}
                }

                if paired
                {
                    mattes[1] = renderer.readRenderTarget(&whiteMatte, 0, 0, copyWidth, copyHeight)
                    if not mattes[1].isValid() do
                        return {}
                }

                for row in copyHeight
                {
                    let firstMatte  = mattes[0].pixels.storage() + cast(u64, row) * cast(u64, mattes[0].rowStride)
                    let resultRow   = result.height - tileY - copyHeight + row
                    let destination = result.pixels.storage() + cast(u64, resultRow) * cast(u64, result.rowStride) + cast(u64, tileX) * result.bytesPerPixel
                    let output      = cast([*] u32, destination)

                    // Mask ink leaves the same-colored matte unchanged through overlaps.
                    // The other matte carries the coverage, even when strokes use alpha scratch.
                    if mask == .White
                    {
                        for column in copyWidth do
                            output[column] = 0x00FF_FFFF | (cast(u32, firstMatte[column * 4]) << 24)
                        continue
                    }

                    if mask == .Black
                    {
                        for column in copyWidth
                        {
                            let alpha = 255'u32 - firstMatte[column * 4]
                            output[column] = alpha == 0 ? 0x00FF_FFFF : alpha << 24
                        }

                        continue
                    }

                    let black      = firstMatte
                    let white      = mattes[1].pixels.storage() + cast(u64, row) * cast(u64, mattes[1].rowStride)
                    let blackWords = cast(const [*] u32, black)
                    let whiteWords = cast(const [*] u32, white)
                    for column in copyWidth
                    {
                        // Identical matte colors have full coverage. Strokes may have
                        // used the black matte's alpha byte as scratch.
                        let blackRgb = blackWords[column] & 0x00FF_FFFF
                        let whiteRgb = whiteWords[column] & 0x00FF_FFFF
                        if blackRgb == whiteRgb
                        {
                            output[column] = blackRgb | 0xFF00_0000
                            continue
                        }

                        if blackRgb == 0 and whiteRgb == 0x00FF_FFFF
                        {
                            output[column] = 0x00FF_FFFF
                            continue
                        }

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

    // All visible items must be unclipped scan fills of the same solid color.
    private mtd const monochromeScanInk()->u32
    {
        var ink = Swag.U32.Max
        for item in .items
        {
            if item.kind != .Shape or item.clip do
                return Swag.U32.Max
            let shape = &.shapes[item.index]
            if not shape.scanFill or shape.stroke or shape.filterId or shape.fillPaintId do
                return Swag.U32.Max
            let rgb = shape.fillColor.argb & 0x00FF_FFFF
            if ink != Swag.U32.Max and ink != rgb do
                return Swag.U32.Max
            ink = rgb
        }

        return ink
    }

    private mtd const rasterizeScanFills(width, height, sampleTileSide: s32)->Image
    {
        var result = Image.create(width, height, .BGRA8)
        if not result.isValid() do
            return result

        // Keep the raster API's transparent white in pixels untouched by any fill.
        result.fill(Color.fromArgb(0x00FF_FFFF))
        let scale     = cast(f32, width) / .width
        let transform = Transform2.createScale(scale, scale, 0, 0)
        var scratch: ScanScratch
        for item in .items
        {
            let shape = &.shapes[item.index]
            .scanFills[shape.scanFill - 1].blend(.pathsFor(shape), transform, &result, &scratch, sampleTileSide, shape.fillColor, shape.evenOdd)
        }

        return result
    }

    // Match the sampled grid's box resolve after the ordered fills have composed.
    private func resolveScanFillSamples(samples: const *Image, width, height, factor: s32, ink: u32)->Image
    {
        var result = Image.create(width, height, .BGRA8)
        if not result.isValid() do
            return result
        let count = cast(u32, factor * factor)
        for y in height
        {
            let target = result.pixels.storage() + cast(u64, y) * result.rowStride
            let output = cast([*] u32, target)
            for x in width
            {
                var alpha = 0'u32
                for row in factor
                {
                    let source = samples.pixels.storage() + cast(u64, y * factor + row) * samples.rowStride
                    let block  = source + cast(u64, x * factor) * 4
                    for column in factor do
                        alpha += block[column * 4 + 3]
                }

                alpha     = (alpha + count / 2) / count
                output[x] = alpha ? ink | (alpha << 24) : 0x00FF_FFFF
            }
        }

        return result
    }

    // The shared coverage path handles solid and gradient geometry in a single target.
    private mtd const canShareMatteCoverage()->bool
    {
        if .filters.count or .patterns.count do
            return false
        for item in .items where item.kind != .Shape do
            return false
        return true
    }

    // Detects shapes whose color can be recovered from one matte.
    private mtd const rasterMask()->RasterMask
    {
        var white = true
        var black = true
        for item in .items
        {
            if item.kind != .Shape do
                return .Color
            let shape = &.shapes[item.index]
            if shape.filterId or shape.fillPaintId do
                return .Color
            if shape.hasFill
            {
                let rgb = shape.fillColor.argb & 0x00FF_FFFF
                white = white and rgb == 0x00FF_FFFF
                black = black and rgb == 0
            }

            let stroke = .strokeFor(shape)
            if stroke
            {
                if stroke.paintId do
                    return .Color
                if stroke.enabled
                {
                    let rgb = stroke.color.argb & 0x00FF_FFFF
                    white = white and rgb == 0x00FF_FFFF
                    black = black and rgb == 0
                }
            }

            if not white and not black do
                return .Color
        }

        return white ? .White : .Black
    }
}

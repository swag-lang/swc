using Swag, Core

#[Swag.EnumFlags]
public enum LoadFlag
{
    Default                   = 0
    NoScale
    NoHinting
    Render
    NoBitmap
    VerticalLayout
    ForceAutoHint
    CropBitmap
    Pedantic
    AdvanceOnly
    IgnoreGlobalAdvanceWidth
    NoRecurse
    IgnoreTransform
    Monochrome
    LinearDesign
    SBitsOnly
    NoAutoHint
    Color                    = 1 << 20
    ComputeMetrics           = 1 << 21
    BitmapMetricsOnly        = 1 << 22
}

#[Swag.EnumFlags]
public enum StyleFlag
{
    None = 0
    Italic
    Bold
}

public enum RenderMode
{
    Normal = 0
    Light
    Mono
    Lcd
    LcdV
}

#[ConstExpr]
func imageTag(x1, x2, x3, x4: u32)->u32 => (x1 << 24) | (x2 << 16) | (x3 << 8) | x4

public enum GlyphFormat
{
    None      = 0
    Composite = 0x636F6D70
    Bitmap    = 0x62697473
    Outline   = 0x6F75746C
    Plotter   = 0x706C6F74
}

public enum LcdFilter
{
    None    = 0
    Default = 1
    Light   = 2
    Legacy1 = 3
    Legacy  = 16
    Max
}

public enum PixelMode
{
    None
    Mono
    Gray
    Gray2
    Gray4
    Lcd
    LcdV
    Bgra
    Max
}

public struct BBox { xMin, yMin: s32, xMax, yMax: s32 }

public struct Vector
{
    x: s32
    y: s32
}

public struct Matrix { xx, xy: s32, yx, yy: s32 }

public enum OutlineCommandKind
{
    MoveTo
    LineTo
    ConicTo
    CubicTo
}

public struct OutlineCommand
{
    kind:     OutlineCommandKind
    p0:       Vector
    p1:       Vector
    p2:       Vector
}

public struct Bitmap
{
    rows:             u32
    width:            u32
    pitch:            s32
    buffer:           [*] u8
    grayCount:        u16
    pixelMode:        PixelMode
}

public struct Outline
{
    contourCount:     s16
    pointCount:       s16
    points:           [*] Vector
    tags:             [*] u8
    contours:         [*] s16
    flags:            s32
}

public struct GlyphMetrics
{
    width:            s32
    height:           s32
    horizontalBearingX: s32
    horizontalBearingY: s32
    horizontalAdvance:  s32
    verticalBearingX:   s32
    verticalBearingY:   s32
    verticalAdvance:    s32
}

public struct SizeMetrics
{
    xPpem:          u16
    yPpem:          u16
    xScale:         s32
    yScale:         s32
    ascender:       s32
    descender:      s32
    height:         s32
    maxAdvance:     s32
}

public struct Size
{
    face:      *Face
    metrics:   SizeMetrics
}

public struct CharMap
{
    face:         *Face
    encoding:     u32
    platformID:   u16
    encodingID:   u16
}

public struct GlyphSlot
{
    face:                   *Face
    index:                  u32
    metrics:                GlyphMetrics
    linearHorizontalAdvance: s32
    linearVerticalAdvance:   s32
    advance:                Vector
    format:                 GlyphFormat = GlyphFormat.None
    bitmap:                 Bitmap
    bitmapLeft:             s32
    bitmapTop:              s32
    outline:                Outline
    leftSideBearingDelta:   s32
    rightSideBearingDelta:  s32
}

public struct Face
{
    faceCount:            s32
    faceIndex:            s32
    flags:                s32
    style:                StyleFlag
    glyphCount:           u32
    familyName:           String
    styleName:            String
    bbox:                 BBox
    unitsPerEm:           u16
    ascender:             s16
    descender:            s16
    height:               s16
    maxAdvanceWidth:      s16
    maxAdvanceHeight:     s16
    underlinePosition:    s16
    underlineThickness:   s16
    glyph:                GlyphSlot
    size:                 Size
    charMap:              CharMap
}

public struct Library
{
    versionMajor: s32
    versionMinor: s32
    versionPatch: s32
}

var Errors: [0xFF] string = undefined

#init
{
    Errors[0x01] = "cannot open resource"
    Errors[0x02] = "unknown file format"
    Errors[0x03] = "broken file"
    Errors[0x04] = "invalid TrueType version"
    Errors[0x05] = "module version is too low"
    Errors[0x06] = "invalid argument"
    Errors[0x07] = "unimplemented feature"
    Errors[0x08] = "broken table"
    Errors[0x09] = "broken offset within table"
    Errors[0x0A] = "array allocation size too large"
    Errors[0x0B] = "missing module"
    Errors[0x0C] = "missing property"
    Errors[0x10] = "invalid glyph index"
    Errors[0x11] = "invalid character code"
    Errors[0x12] = "unsupported glyph image format"
    Errors[0x13] = "cannot render this glyph format"
    Errors[0x14] = "invalid outline"
    Errors[0x15] = "invalid composite glyph"
    Errors[0x16] = "too many hints"
    Errors[0x17] = "invalid pixel size"
    Errors[0x20] = "invalid object handle"
    Errors[0x21] = "invalid library handle"
    Errors[0x22] = "invalid module handle"
    Errors[0x23] = "invalid face handle"
    Errors[0x24] = "invalid size handle"
    Errors[0x25] = "invalid glyph slot handle"
    Errors[0x26] = "invalid charmap handle"
    Errors[0x27] = "invalid cache manager handle"
    Errors[0x28] = "invalid stream handle"
    Errors[0x30] = "too many modules"
    Errors[0x31] = "too many extensions"
    Errors[0x40] = "out of memory"
    Errors[0x41] = "unlisted object"
    Errors[0x51] = "cannot open stream"
    Errors[0x52] = "invalid stream seek"
    Errors[0x53] = "invalid stream skip"
    Errors[0x54] = "invalid stream read"
    Errors[0x55] = "invalid stream operation"
    Errors[0x56] = "invalid frame operation"
    Errors[0x57] = "nested frame access"
    Errors[0x58] = "invalid frame read"
    Errors[0x60] = "raster uninitialized"
    Errors[0x61] = "raster corrupted"
    Errors[0x62] = "raster overflow"
    Errors[0x63] = "negative height while rastering"
    Errors[0x70] = "too many registered caches"
    Errors[0x80] = "invalid opcode"
    Errors[0x81] = "too few arguments"
    Errors[0x82] = "stack overflow"
    Errors[0x83] = "code overflow"
    Errors[0x84] = "bad argument"
    Errors[0x85] = "division by zero"
    Errors[0x86] = "invalid reference"
    Errors[0x87] = "found debug opcode"
    Errors[0x88] = "found ENDF opcode in execution stream"
    Errors[0x89] = "nested DEFS"
    Errors[0x8A] = "invalid code range"
    Errors[0x8B] = "execution context too long"
    Errors[0x8C] = "too many function definitions"
    Errors[0x8D] = "too many instruction definitions"
    Errors[0x8E] = "SFNT font table missing"
    Errors[0x8F] = "horizontal header (hhea) table missing"
    Errors[0x90] = "locations (loca) table missing"
    Errors[0x91] = "name table missing"
    Errors[0x92] = "character map (cmap) table missing"
    Errors[0x93] = "horizontal metrics (hmtx) table missing"
    Errors[0x94] = "PostScript (post) table missing"
    Errors[0x95] = "invalid horizontal metrics"
    Errors[0x96] = "invalid character map (cmap) format"
    Errors[0x97] = "invalid ppem value"
    Errors[0x98] = "invalid vertical metrics"
    Errors[0x99] = "could not find context"
    Errors[0x9A] = "invalid PostScript (post) table format"
    Errors[0x9B] = "invalid PostScript (post) table"
    Errors[0x9C] = "found FDEF or IDEF opcode in glyf bytecode"
    Errors[0x9D] = "missing bitmap in strike"
    Errors[0xA0] = "opcode syntax error"
    Errors[0xA1] = "argument stack underflow"
    Errors[0xA2] = "ignore"
    Errors[0xA3] = "no Unicode glyph name found"
    Errors[0xA4] = "glyph too big for hinting"
    Errors[0xB0] = "'STARTFONT' field missing"
    Errors[0xB1] = "'FONT' field missing"
    Errors[0xB2] = "'SIZE' field missing"
    Errors[0xB3] = "'FONTBOUNDINGBOX' field missing"
    Errors[0xB4] = "'CHARS' field missing"
    Errors[0xB5] = "'STARTCHAR' field missing"
    Errors[0xB6] = "'ENCODING' field missing"
    Errors[0xB7] = "'BBX' field missing"
    Errors[0xB8] = "'BBX' too big"
    Errors[0xB9] = "Font header corrupted or missing fields"
    Errors[0xBA] = "Font glyphs corrupted or missing fields"
}

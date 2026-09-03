#global namespace Pdf

using Core, Core.Errors, Core.Math, Pixel

// The soft mask an `ExtGState` establishes, and the coverage it produces over a page.
//
// A soft mask is how a document expresses a feathered shadow, a vignette, and a gradient fade:
// `/SMask` names a transparency group, and the group's luminosity — or its own alpha — becomes
// the coverage every later mark is painted through. Without it the marks arrive at full
// strength, which is why an unmasked drop shadow reads as an opaque black block sitting on top
// of the illustration it was meant to sit behind.

// What `/S` selects as the coverage the group contributes.
enum SoftMaskKind
{
    Luminosity     // The group is composited over the backdrop and its brightness is the coverage.
    Alpha          // The group's own alpha is the coverage, whatever it painted.
}

// Samples per PDF point a mask is rasterized at.
//
// A mask is a coverage field rather than a picture: it is almost always a blur or a gradient, so
// it carries far less detail than the marks it covers. Two samples per point keeps a shadow
// smooth at the scales a page is read at, and keeps the rasterization small enough to pay once
// per mark the mask covers.
const SoftMaskSamplesPerPoint = 2.0'f32

// Largest coverage raster produced for one mark.
const SoftMaskMaxDimension = 2048's32

// One soft mask as the graphics state carries it.
//
// `q` copies the whole graphics state, so this names the group rather than holding its coverage:
// the decoded group lives in the parser's cache, keyed by this reference.
struct SoftMaskRef
{
    groupId:  u32 = InvalidNode     // Transparency group the coverage comes from.
    ctm:      Transform2            // Transform in force when `gs` selected the mask.
    backdrop: Color                 // Colour outside the group's own box, from `/BC`.
    kind:     SoftMaskKind          // What the group contributes.
}

impl SoftMaskRef
{
    // Reports whether a mask is in force, which `/SMask /None` clears.
    mtd const isActive()->bool => .groupId != InvalidNode

    // Returns the cache key of the decoded group.
    //
    // The transform is part of the identity: one group placed twice covers two different regions
    // of the page, and they are not the same coverage.
    mtd const cacheKey()->u64
    {
        var hash = cast(u64) .groupId
        hash = mixHash(hash, .ctm.m11)
        hash = mixHash(hash, .ctm.m12)
        hash = mixHash(hash, .ctm.m21)
        hash = mixHash(hash, .ctm.m22)
        hash = mixHash(hash, .ctm.tx)
        hash = mixHash(hash, .ctm.ty)
        return hash
    }
}

// Folds one transform component into a hash, by its exact representation rather than its value.
private func mixHash(hash: u64, value: f32)->u64 => (hash << 7 | hash >> 57) ^ cast(u64) cast #bit(u32) value

// One soft mask group after its content stream has been read.
//
// The marks are kept rather than a coverage raster: a mask covers several marks at different
// scales, and each of them wants the coverage over its own box. Reading the group is the
// expensive half and is paid once; rasterizing a mark's own region is cheap.
struct SoftMaskGroup
{
    page:     Page
    backdrop: Color
    kind:     SoftMaskKind
}

// Reads the soft mask an `ExtGState` dictionary names.
//
// A dictionary with no `/G`, and the name `/None`, both clear the mask rather than failing the
// page: a graphics state may legitimately turn masking off.
internal func readSoftMask(parser: *PdfParser, entry: u32, ctm: Transform2)->SoftMaskRef
{
    var result: retval
    let maskId = parser.dict(entry, "SMask")
    if maskId == InvalidNode or parser.nodes[maskId].kind != .Dictionary do
        return result

    let groupId = parser.resolve(parser.dictRaw(maskId, "G"))
    if groupId == InvalidNode do
        return result

    result.groupId = groupId
    result.ctm     = ctm
    result.kind    = parser.name(parser.dict(maskId, "S")) == "Alpha" ? SoftMaskKind.Alpha : SoftMaskKind.Luminosity

    // Outside the group's own box the coverage is whatever the backdrop contributes, which for a
    // luminosity mask is the colour `/BC` names in the group's space and is black by default. An
    // alpha mask has no backdrop colour: nothing painted is nothing covered.
    if result.kind == .Alpha
    {
        result.backdrop = Color.fromArgb(0'u32)
        return result
    }

    result.backdrop = Color.fromArgb(Argb.Black)
    let backdropId = parser.dict(maskId, "BC")
    if backdropId == InvalidNode or parser.nodes[backdropId].kind != .Array do
        return result

    // The backdrop is stated in the group's own colour space, so it is reduced the same way a
    // colour operator's operands are.
    let group = parser.dict(groupId, "Group")
    let space = catch resolveImageSpace(parser, parser.dictRaw(group, "CS"), parser.dict(groupId, "Resources"), 0) as spaceError
    var values: [8] f32
    let count = Math.min(parser.nodes[backdropId].values.count, 8'u64)
    for i in count do
        values[i] = cast(f32) parser.number(parser.nodes[backdropId].values[i])
    if spaceError == null do
        result.backdrop = spaceColor(&space, values[0 until count])
    elif count >= 1 do
        result.backdrop = grayColor(values[0])
    return result
}

// Returns the coverage a mask produces over one page-space rectangle.
//
// The rectangle is the box of the mark being painted, so the coverage comes back aligned to it
// and can be anchored there without resampling. Rendering the group is what PDF defines the mask
// to be: the group is composited over its backdrop, and its luminosity — or its alpha — is read
// back as coverage.
internal func softMaskCoverage(group: *SoftMaskGroup, region: Math.Rectangle)->Image fail
{
    var result: retval
    if region.width <= 0 or region.height <= 0 or !Math.isFinite(region.width) or !Math.isFinite(region.height) do
        return result

    var options: RenderOptions
    options.scale        = SoftMaskSamplesPerPoint
    options.background   = group.backdrop
    options.sourceRect   = region
    options.maxDimension = SoftMaskMaxDimension

    // A mark far larger than the mask still asks for the coverage over its own box; rasterizing
    // that at full density would cost more than the mark itself, so the density drops until the
    // raster fits.
    let longest = Math.max(region.width, region.height)
    if longest * options.scale > cast(f32) SoftMaskMaxDimension do
        options.scale = cast(f32) SoftMaskMaxDimension / longest

    let rendered = #move try renderPage(&group.page, options)
    result = #move coverageImage(&rendered, group.kind)
    return #move result
}

// Turns a rendered mask group into an image whose alpha is the coverage.
//
// The colour is left white so the image is a pure multiplier: a brush tinted with the mark's own
// colour then produces exactly that colour at the coverage the mask states.
private func coverageImage(rendered: const *Image, kind: SoftMaskKind)->Image
{
    var result = #move Image.create(rendered.width, rendered.height, .RGBA8)
    let width  = cast(u64) rendered.width
    for y in cast(u64) rendered.height
    {
        var out    = result.pixels.buffer! + y * cast(u64) result.rowStride
        var source = rendered.pixels.buffer! + y * cast(u64) rendered.rowStride
        let step   = cast(u64) rendered.bytesPerPixel
        for width
        {
            out[0], out[1], out[2] = 0xFF

            // Luminosity is the brightness of the composited group, weighted the way the format
            // states it; an alpha mask reads the coverage the group itself accumulated.
            if kind == .Luminosity do
                out[3] = cast(u8) ((cast(u32) source[0] * 77 + cast(u32) source[1] * 151 + cast(u32) source[2] * 28) >> 8)
            else do
                out[3] = step >= 4 ? source[3] : 0xFF
            out    += 4
            source += step
        }
    }

    return #move result
}

using Core, TrueType

// Loaded font-face data used to create fonts and rasterize glyphs.
//
// Use [[Pixel.TypeFace.load]] for a font file or [[Pixel.TypeFace.create]] for
// bytes already in memory. Returned pointers are shared by Pixel's typeface cache;
// release them with [[Pixel.TypeFace.release]] rather than deleting them directly.
public struct TypeFace
{
    fullname:     string = ""            // Cache key or source filename.
    buffer:       Array'u8               // Owned font bytes kept alive for the native face.
    face:         *Face  = undefined     // Borrowed TrueType face backed by `buffer`.
    forceBoldDiv: u32    = 11            // Em-size divisor used for synthetic bold strength.
    forceItalic:  bool                   // Whether every rasterized glyph is synthetically slanted.
    forceBold:    bool                   // Whether every rasterized glyph is synthetically emboldened.
}

var g_HashTypeFace: HashTable'(String, *TypeFace)

#drop
{
    for k, [v] in g_HashTypeFace do
        Memory.delete(v)
    g_HashTypeFace.free()
}

impl TypeFace
{
    var lock: Sync.Mutex

    func addOutlineToPathList(pathList: *LinePathList, commands: const [..] OutlineCommand)
    {
        for cmd in commands
        {
            switch cmd.kind
            {
            case .MoveTo:
                let path = pathList.newPath()
                path.start(cmd.p0.x / 64.0, -cmd.p0.y / 64.0)

            case .LineTo:
                let path = pathList.paths[pathList.paths.count - 1]
                path.lineTo(cmd.p0.x / 64.0, -cmd.p0.y / 64.0)

            case .ConicTo:
                let path = pathList.paths[pathList.paths.count - 1]
                path.bezierTo(cmd.p1.x / 64.0, -cmd.p1.y / 64.0, cmd.p0.x / 64.0, -cmd.p0.y / 64.0)

            case .CubicTo:
                let path = pathList.paths[pathList.paths.count - 1]
                path.bezierTo(cmd.p2.x / 64.0, -cmd.p2.y / 64.0, cmd.p0.x / 64.0, -cmd.p0.y / 64.0, cmd.p1.x / 64.0, -cmd.p1.y / 64.0)
            }
        }
    }
}

public impl TypeFace
{
    // Destroys the native face associated with this value.
    mtd opDrop()
    {
        if .face do
            .face.destroy()
    }

    // Returns true if the typeface is bold
    mtd const isBold()->bool => .face.isBold()

    // Returns true if the typeface is italic
    mtd const isItalic()->bool => .face.isItalic()

    // Returns the underlying font family name
    mtd const getFamilyName()->string => .face.familyName

    // Release the given typeface
    func release(typeface: *TypeFace)
    {
        if !typeface do
            return
        Sync.scopedLock(&lock)
        g_HashTypeFace.remove(typeface.fullname)
        Memory.delete(typeface)
    }

    // Get or create a new typeface from a memory buffer
    func create(fullname: string, bytes: const [..] u8)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let here = g_HashTypeFace.tryFind(fullname)
        if here do
            return notnull here.value

        let tf = Memory.new'TypeFace()
        tf.fullname = fullname
        tf.buffer   = bytes

        let face = try Face.load(tf.buffer.toSlice())
        tf.face = notnull face

        g_HashTypeFace.add(fullname, tf)
        return tf
    }

    // Get or load a new typeface
    func load(fullname: string)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let here = g_HashTypeFace.tryFind(fullname)
        if here do
            return notnull here.value

        let tf = Memory.new'TypeFace()
        tf.fullname = fullname

        // If file does not exist, try the system folder
        if !File.exists(fullname)
        {
            let p = Path.combine(Env.getSpecialDirectory(.Font), fullname)
            tf.buffer = File.readAllBytes(p)
        }
        else
        {
            tf.buffer = File.readAllBytes(fullname)
        }

        let face = try Face.load(tf.buffer.toSlice())
        tf.face = notnull face

        g_HashTypeFace.add(fullname, tf)
        return tf
    }

    private mtd transform(size, embolden: u32 = 0, forceBold, forceItalic = false) fail
    {
        var emb = .forceBold or forceBold ? Math.max(1, size / .forceBoldDiv) : 0
        emb += embolden
        if emb do
            .face.glyph.outline.embolden(cast(s32) emb * 64)
        if .forceItalic or forceItalic do
            .face.glyph.oblique()
    }

    // Sub-pixel outline dilation that offsets the anti-aliasing thinning of small
    // text (stem darkening). Per-side strength in 26.6, fading out as the size grows.
    private func stemDarkenStrength(size: u32)->s32
    {
        const FadePx = 24.0'f32     // no darkening at or above this size
        const MaxPx  = 0.12'f32     // per-side dilation in pixels at the smallest sizes
        if cast(f32) size >= FadePx do
            return 0
        let t = (FadePx - cast(f32) size) / FadePx
        return cast(s32) Math.round(MaxPx * t * 64.0)
    }

    // Render one glyph (crisp bitmap path): stem darkening + vertical grid-fitting.
    mtd renderGlyph(c: rune, size: u32, forceBold, forceItalic = false)->const *Bitmap fail
    {
        return try .renderGlyphByIndex(.face.glyphIndex(c), size, forceBold, forceItalic)
    }

    // Render one glyph by glyph index (crisp bitmap path): stem darkening + vertical grid-fitting.
    mtd renderGlyphByIndex(glyphIndex: u32, size: u32, forceBold, forceItalic = false)->const *Bitmap fail
    {
        .face.setPixelSize(0, size)
        .face.loadGlyph(glyphIndex)
        .transform(size, 0, forceBold, forceItalic)
        .face.glyph.outline.embolden(stemDarkenStrength(size))
        .face.hintVertical()
        .face.renderGlyph()
        return &.face.glyph.bitmap
    }

    // Render one glyph as a multi-channel signed distance field
    mtd renderGlyphMsdf(c: rune, size, spread: u32, forceBold, forceItalic = false)->const *Bitmap fail
    {
        return try .renderGlyphMsdfByIndex(.face.glyphIndex(c), size, spread, forceBold, forceItalic)
    }

    // Render one glyph by glyph index as a multi-channel signed distance field
    mtd renderGlyphMsdfByIndex(glyphIndex: u32, size, spread: u32, forceBold, forceItalic = false)->const *Bitmap fail
    {
        .face.setPixelSize(0, size)
        .face.loadGlyph(glyphIndex)
        .transform(size, 0, forceBold, forceItalic)
        .face.renderGlyphMsdf(spread)
        return &.face.glyph.bitmap
    }

    // Convert a rune to its outline, at a given size
    #[Swag.Discardable]
    mtd getRuneOutline(pathList: *LinePathList, c: rune, size: u32, embolden: u32 = 0)->f32 fail
    {
        pathList.clear()

        .face.setPixelSize(0, size)
        .face.loadChar(c)
        .transform(size, embolden)

        let prevIdx  = pathList.paths.count
        let commands = .face.glyph.outline.decompose()
        addOutlineToPathList(pathList, commands.toSlice())

        if prevIdx != pathList.paths.count
        {
            for [i] in prevIdx until pathList.paths.count do
                pathList.paths[i].isClosed = true
        }

        return embolden + (.face.glyph.advance.x / 64.0)
    }

    // Convert a string to its outline, at a given size
    mtd getStringOutline(pathList: *LinePathList, text: string, size: u32, embolden: u32 = 0) fail
    {
        pathList.clear()

        try .face.setPixelSize(0, size)

        var serial = 0
        var x      = 0

        Utf8.visitRunes(text)
        {
            .face.loadChar(c)
            .transform(size, embolden)

            .face.glyph.outline.translate(x, 0)

            let prevIdx  = pathList.paths.count
            let commands = .face.glyph.outline.decompose()
            addOutlineToPathList(pathList, commands.toSlice())

            if prevIdx != pathList.paths.count
            {
                for [i] in prevIdx until pathList.paths.count
                {
                    pathList.paths[i].isClosed = true
                    pathList.paths[i].serial   = serial
                }

                serial += 1
            }

            x += .face.glyph.advance.x
        }
    }
}

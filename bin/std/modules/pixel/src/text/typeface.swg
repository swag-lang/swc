using Core, TrueType

// Loaded font-face data used to create fonts and rasterize glyphs.
//
// Use [[Pixel.TypeFace.load]] for a font file or [[Pixel.TypeFace.create]] for
// bytes already in memory. Returned pointers are shared by Pixel's process-wide
// typeface cache and remain valid until module shutdown; never delete them.
#[Swag.Opaque]
public struct TypeFace
{
    internal
    {
        fullname: String     // Cache key or source filename, owned so a dynamic key cannot dangle.
        #[Swag.Late]
        allocationAllocator: IAllocator     // Allocator that owns this cached value.
        #[Swag.Late]
        face:         *Face        // Owned TrueType face and its copied font bytes.
        faceLoaded:   bool         // Whether `face` can be destroyed during cleanup.
        forceBoldDiv: u32 = 11     // Em-size divisor used for synthetic bold strength.
        forceItalic:  bool         // Whether every rasterized glyph is synthetically slanted.
        forceBold:    bool         // Whether every rasterized glyph is synthetically emboldened.
    }
}

var g_HashTypeFace: HashTable'(String, *TypeFace)

#drop
{
    for k, v in g_HashTypeFace
    {
        let allocator = v.allocationAllocator
        Memory.delete(v, allocator)
    }

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
        if .faceLoaded do
            .face.destroy()
    }

    // Returns true if the typeface is bold
    mtd const isBold()->bool => .face.isBold()

    // Returns true if the typeface is italic
    mtd const isItalic()->bool => .face.isItalic()

    // Returns the family name stored in the font.
    mtd const familyName()->string => .face.familyName

    // Gets or creates a typeface from an in-memory TrueType program.
    //
    // `fullname` is both the cache identity and the fallback family name for a rendering-only
    // subset that legally omits standalone font metadata such as `name` and `post`.
    func create(fullname: string, bytes: const [..] u8)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let here = g_HashTypeFace.tryFind(fullname)
        if here do
            return here.value!

        let allocator = (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)!
        let tf        = Memory.new'TypeFace(allocator)
        tf.allocationAllocator = allocator
        defer #fail Memory.delete(tf, allocator)
        tf.fullname = fullname

        let face = try Face.loadSubset(bytes, fullname, allocator)
        tf.face       = face!
        tf.faceLoaded = true

        g_HashTypeFace.add(fullname, tf)
        return tf
    }

    // Reports whether [[Pixel.TypeFace.load]] has a font to load for `fullname`.
    //
    // A caller choosing among several families needs a miss to be an answer rather than a
    // failure: a machine that does not carry the requested face still has to draw its text,
    // and asking here is how it moves on to the next candidate. The lookup follows the same
    // order `load` does, so an answer of `true` is one `load` honors.
    func exists(fullname: string)->bool
    {
        {
            Sync.scopedLock(&lock)
            if g_HashTypeFace.tryFind(fullname) do
                return true
        }

        if File.exists(fullname) do
            return true
        return File.exists(Path.combine(Env.realSpecialDirectory(.Font), fullname))
    }

    // Get or load a new typeface
    func load(fullname: string)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let here = g_HashTypeFace.tryFind(fullname)
        if here do
            return here.value!

        let allocator = (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)!
        let tf        = Memory.new'TypeFace(allocator)
        tf.allocationAllocator = allocator
        defer #fail Memory.delete(tf, allocator)
        tf.fullname = fullname

        // If file does not exist, try the system folder.
        //
        // The installed fonts belong to the machine, not to the program, so this looks past
        // any sandbox: a sandboxed run has no fonts of its own and would find nothing.
        var buffer: Array'u8
        if !File.exists(fullname)
        {
            let p = Path.combine(Env.realSpecialDirectory(.Font), fullname)
            buffer = File.readAllBytes(p)
        }
        else
        {
            buffer = File.readAllBytes(fullname)
        }

        let face = try Face.load(buffer.toSlice(), allocator)
        tf.face       = face!
        tf.faceLoaded = true

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

    // Builds the outline and advance of one rune at the requested size.
    mtd buildRuneOutline(c: rune, size: u32, embolden: u32 = 0)->{outline: LinePathList, advance: f32} fail
    {
        var result: retval

        .face.setPixelSize(0, size)
        .face.loadChar(c)
        .transform(size, embolden)

        let prevIdx  = result.outline.paths.count
        let commands = .face.glyph.outline.decompose()
        addOutlineToPathList(&result.outline, commands.toSlice())

        if prevIdx != result.outline.paths.count
        {
            for i in prevIdx until result.outline.paths.count do
                result.outline.paths[i].assumeClosed()
        }

        result.advance = embolden + (.face.glyph.advance.x / 64.0)
        return result
    }

    // Builds the outlines of a UTF-8 string at the requested size.
    mtd buildStringOutline(text: string, size: u32, embolden: u32 = 0)->LinePathList fail
    {
        var result: retval

        try .face.setPixelSize(0, size)

        var serial = 0
        var x      = 0

        Utf8.visitRunes(text)
        {
            .face.loadChar(c)
            .transform(size, embolden)

            .face.glyph.outline.translate(x, 0)

            let prevIdx  = result.paths.count
            let commands = .face.glyph.outline.decompose()
            addOutlineToPathList(&result, commands.toSlice())

            if prevIdx != result.paths.count
            {
                for i in prevIdx until result.paths.count
                {
                    result.paths[i].assumeClosed()
                    result.paths[i].serial = serial
                }

                serial += 1
            }

            x += .face.glyph.advance.x
        }

        return result
    }
}

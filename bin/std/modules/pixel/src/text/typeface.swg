using Core, TrueType

var g_TrueType: Library
#init
{
    g_TrueType.init()
}

public struct TypeFace
{
    fullname:         string
    buffer:           Array'u8
    face:             *Face
    forceBoldDiv:     u32 = 11
    forceItalic:      bool
    forceBold:        bool
}

var g_HashTypeFace: HashTable'(String, *TypeFace)

#drop
{
    foreach k, v in g_HashTypeFace do
        Memory.delete(v)
    g_HashTypeFace.free()
}

impl TypeFace
{
    var lock: Sync.Mutex

    func addOutlineToPathList(pathList: *LinePathList, commands: const [..] OutlineCommand)
    {
        foreach cmd in commands
        {
            switch cmd.kind
            {
            case MoveTo:
                let path = pathList.newPath()
                path.start(cmd.p0.x / 64.0, -cmd.p0.y / 64.0)

            case LineTo:
                let path = pathList.paths[pathList.paths.count - 1]
                path.lineTo(cmd.p0.x / 64.0, -cmd.p0.y / 64.0)

            case ConicTo:
                let path = pathList.paths[pathList.paths.count - 1]
                path.bezierTo(cmd.p1.x / 64.0, -cmd.p1.y / 64.0, cmd.p0.x / 64.0, -cmd.p0.y / 64.0)

            case CubicTo:
                let path = pathList.paths[pathList.paths.count - 1]
                path.bezierTo(cmd.p2.x / 64.0, -cmd.p2.y / 64.0, cmd.p0.x / 64.0, -cmd.p0.y / 64.0, cmd.p1.x / 64.0, -cmd.p1.y / 64.0)
            }
        }
    }
}

public impl TypeFace
{
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
    func create(fullname: string, bytes: const [..] u8)->*TypeFace throw
    {
        Sync.scopedLock(&lock)

        let here = g_HashTypeFace.tryFind(fullname)
        if here do
            return here.value

        let tf = Memory.new'TypeFace()
        tf.fullname = fullname
        tf.buffer   = bytes
        tf.face     = try g_TrueType.loadFace(tf.buffer.toSlice())

        g_HashTypeFace.add(fullname, tf)
        return tf
    }

    // Get or load a new typeface
    func load(fullname: string)->*TypeFace throw
    {
        Sync.scopedLock(&lock)

        let here = g_HashTypeFace.tryFind(fullname)
        if here do
            return here.value

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

        tf.face = try g_TrueType.loadFace(tf.buffer.toSlice())

        g_HashTypeFace.add(fullname, tf)
        return tf
    }

    fileprivate mtd transform(size, embolden: u32 = 0, forceBold, forceItalic = false) throw
    {
        var emb = .forceBold or forceBold ? Math.max(1, size / .forceBoldDiv) : 0
        emb += embolden
        if emb do
            .face.glyph.outline.embolden(cast(s32) emb * 64)
        if .forceItalic or forceItalic do
            .face.glyph.oblique()
    }

    // Render one glyph
    mtd renderGlyph(c: rune, size: u32, forceBold, forceItalic = false)->const *Bitmap throw
    {
        .face.setPixelSize(0, size)
        .face.loadChar(c)
        .transform(size, 0, forceBold, forceItalic)
        .face.renderGlyph()
        return &.face.glyph.bitmap
    }

    // Convert a rune to its outline, at a given size
    #[Swag.Discardable]
    mtd getRuneOutline(pathList: *LinePathList, c: rune, size: u32, embolden: u32 = 0)->f32 throw
    {
        pathList.clear()

        .face.setPixelSize(0, size)
        .face.loadChar(c, .NoBitmap)
        .transform(size, embolden)

        let prevIdx = pathList.paths.count
        let commands = .face.glyph.outline.decompose()
        addOutlineToPathList(pathList, commands.toSlice())

        if prevIdx != pathList.paths.count
        {
            for i in prevIdx until pathList.paths.count do
                pathList.paths[i].isClosed = true
        }

        return embolden + (.face.glyph.advance.x / 64.0)
    }

    // Convert a string to its outline, at a given size
    mtd getStringOutline(pathList: *LinePathList, text: string, size: u32, embolden: u32 = 0) throw
    {
        pathList.clear()

        try .face.setPixelSize(0, size)

        var serial = 0
        var x      = 0

        Utf8.visitRunes(|c| text)
        {
            .face.loadChar(c, .NoBitmap)
            .transform(size, embolden)

            .face.glyph.outline.translate(x, 0)

            let prevIdx = pathList.paths.count
            let commands = .face.glyph.outline.decompose()
            addOutlineToPathList(pathList, commands.toSlice())

            if prevIdx != pathList.paths.count
            {
                for i in prevIdx until pathList.paths.count
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

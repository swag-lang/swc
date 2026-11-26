using Core, Swag

private struct CMapCacheEntry
{
    bytes:      const [..] u8
    glyphCount: u32
    selection:  CMapSelection
}

private struct PostNamesCacheEntry
{
    late table: const [..] u8
    glyphCount: u32
    late names: *GlyphNames
}

private struct GlyphLocationCacheEntry
{
    late bytes: const [..] u8
    longFormat: bool
    end:        u64
}

private struct FontSourceStorage
{
    late allocator:  IAllocator
    references:      s64 = 1
    bytes:           Array'u8
    woffSfnt:        Array'u8
    type1Program:    *Type1Font?
    cffPrograms:     Array'(*CffFont)
    programTables:   *ProgramTables?
    cmapSelections:  Array'CMapCacheEntry
    verticalMetrics: Array'(*VerticalMetricTable)
    postNames:       Array'PostNamesCacheEntry
    glyphLocations:  Array'GlyphLocationCacheEntry
    parseMutex:      Swag.Mutex
}

impl FontSourceStorage
{
    mtd opDrop()
    {
        if let program = .type1Program do
            Memory.delete(program, .allocator)
        for program in .cffPrograms do
            Memory.delete(program, .allocator)
        if let tables = .programTables do
            Memory.delete(tables, .allocator)
        for table in .verticalMetrics do
            Memory.delete(table, .allocator)
        for entry in .postNames do
            Memory.delete(entry.names, .allocator)
    }
}

// Owns immutable font bytes shared by one or more independently loaded faces.
//
// Copies of this value and faces opened from it retain the same bytes. Each face has its
// own size, glyph slot, and drawing workspace. Separate threads may use their own
// source values when the source allocator supports access from those threads.
// A default value holds no font bytes.
#[Swag.Opaque]
public struct FontSource
{
    private storage: *FontSourceStorage?
}

impl FontSource
{
    mtd opPostCopy()
    {
        if let storage = .storage do
            discard Atomic.add(&storage.references, 1)
    }

    mtd opDrop()
    {
        if let storage = .storage
        {
            .storage = null
            if Atomic.add(&storage.references, -1) == 1
            {
                let allocator = storage.allocator
                Memory.delete(storage, allocator)
            }
        }
    }

    // Face views use the reconstructed sfnt once prepareBytes has published it.
    mtd const faceBytes()->const [..] u8
    {
        if let storage = .storage do
            return storage.woffSfnt.count ? storage.woffSfnt.toSlice() : storage.bytes.toSlice()
        return ""
    }

    private mtd const prepareBytes(faceIndex: u32)->const [..] u8 fail
    {
        let input = .bytes()
        if input.count < 4 or (try readU32(input, 0)) != TAG_WOFF do
            return input
        if faceIndex do
            try fault(0x0F)

        let storage = unwrap .storage
        Sync.scopedLock(&storage.parseMutex)
        if not storage.woffSfnt.count
        {
            let context        = Swag.getContext()
            let priorAllocator = context.allocator
            context.allocator = storage.allocator
            defer context.allocator = priorAllocator
            storage.woffSfnt = try inflateWoff(input)
        }

        return storage.woffSfnt.toSlice()
    }

    mtd const cachedType1(bytes: const [..] u8)->const *Type1Font? fail
    {
        if not .storage do
            return null

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)
        if let program = storage.type1Program do
            return program

        let context = Swag.getContext()
        let previousAllocator = context.allocator
        context.allocator = storage.allocator
        defer context.allocator = previousAllocator

        var program = try parseType1Font(bytes)
        let cached  = Memory.new'Type1Font(storage.allocator)
        cached[] = #move program
        storage.type1Program = cached
        return cached
    }

    // Different faces of a collection can reference the same CFF byte range.
    mtd const cachedCff(bytes: const [..] u8)->*CffFont? fail
    {
        if not .storage do
            return null

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)
        for program in storage.cffPrograms
        {
            if program.block.buffer == bytes.buffer and program.block.count == bytes.count do
                return program
        }

        let context = Swag.getContext()
        let previousAllocator = context.allocator
        context.allocator = storage.allocator
        defer context.allocator = previousAllocator

        var parsed  = try parseCffFont(bytes)
        let program = Memory.new'CffFont(storage.allocator)
        program[] = #move parsed
        storage.cffPrograms.add(program)
        return program
    }

    // Only a bare program uses these tables. It occupies the entire source.
    mtd const cachedProgramTables(face: *FaceImpl)->const *ProgramTables? fail
    {
        if not .storage do
            return null

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)
        if let tables = storage.programTables do
            return tables

        let allocator = storage.allocator
        let tables    = Memory.new'ProgramTables(allocator)
        defer #fail Memory.delete(tables, allocator)
        tables.advances.allocator = allocator
        let context = Swag.getContext()
        let previousAllocator = context.allocator
        context.allocator = allocator
        defer context.allocator = previousAllocator
        try buildCharstringMetrics(face, &tables.advances)
        buildSyntheticCMap(face, &tables.cmap)
        storage.programTables = tables
        return tables
    }

    // A shared table can occur on faces with different glyph bounds.
    mtd const cachedCMap(bytes: const [..] u8, glyphCount: u32)->CMapSelection fail
    {
        if not .storage do
            return try selectCMap(bytes, glyphCount)

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)
        for entry in storage.cmapSelections
        {
            if entry.bytes.buffer == bytes.buffer and
               entry.bytes.count == bytes.count and
               entry.glyphCount == glyphCount do
                return entry.selection
        }

        let selection = try selectCMap(bytes, glyphCount)
        storage.cmapSelections.add({bytes: bytes, glyphCount: glyphCount, selection: selection})
        return selection
    }

    mtd const cachedVerticalMetrics(bytes: const [..] u8, glyphCount, longMetricCount: u32)->*VerticalMetricTable?
    {
        if not .storage do
            return null

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)
        for entry in storage.verticalMetrics
        {
            if entry.bytes.buffer == bytes.buffer and
               entry.bytes.count == bytes.count and
               entry.glyphCount == glyphCount and
               entry.longCount == longMetricCount do
                return entry
        }

        let table = VerticalMetricTable.create(bytes, glyphCount, longMetricCount, storage.allocator)
        storage.verticalMetrics.add(table)
        return table
    }

    mtd const cachedPostNames(table: const [..] u8, glyphCount, format: u32)->*GlyphNames? fail
    {
        if not .storage do
            return null

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)
        for entry in storage.postNames
        {
            if entry.table.buffer == table.buffer and
               entry.table.count == table.count and
               entry.glyphCount == glyphCount do
                return entry.names
        }

        let context = Swag.getContext()
        let previousAllocator = context.allocator
        context.allocator = storage.allocator
        defer context.allocator = previousAllocator

        let allocator = storage.allocator
        let names     = Memory.new'GlyphNames(allocator)
        defer #fail Memory.delete(names, allocator)
        names.entries.allocator = storage.allocator
        try parsePostGlyphNames(names, glyphCount, table, format)
        storage.postNames.add({table, glyphCount, names})
        return names
    }

    mtd const validatedGlyphEnd(bytes: const [..] u8, glyphCount: u32, longFormat: bool)->u64 fail
    {
        if not .storage do
            return try validateGlyphEnd(bytes, glyphCount, longFormat)

        let storage = .storage
        Sync.scopedLock(&storage.parseMutex)

        // The bounded slice size and format identify the glyph count.
        for entry in storage.glyphLocations
        {
            if entry.bytes.buffer == bytes.buffer and
               entry.bytes.count == bytes.count and
               entry.longFormat == longFormat do
                return entry.end
        }

        let end = try validateGlyphEnd(bytes, glyphCount, longFormat)
        storage.glyphLocations.add({bytes, longFormat, end})
        return end
    }

    private func takeBytes(bytes: #move Array'u8, allocator: IAllocator)->FontSource
    {
        let storage = Memory.new'FontSourceStorage(allocator)
        storage.allocator                 = allocator
        storage.bytes                     = #move bytes
        storage.cffPrograms.allocator     = allocator
        storage.cmapSelections.allocator  = allocator
        storage.verticalMetrics.allocator = allocator
        storage.postNames.allocator       = allocator
        storage.glyphLocations.allocator  = allocator
        return {storage: storage}
    }
}

public impl FontSource
{
    // Takes a snapshot of a font file for subsequent face loads. File errors propagate.
    //
    // Decoding is deferred until [[TrueType.FontSource.loadFace]]. Later writes to or removal
    // of the file do not affect the snapshot. The supplied allocator, or the allocator active
    // at the start of the call, must remain alive until all source copies and faces are gone.
    func loadFile(fileName: string, allocator: IAllocator? = null)->FontSource fail
    {
        let context = Swag.getContext()
        let previousAllocator = context.allocator
        let resolvedAllocator = unwrap (allocator orelse previousAllocator)
        context.allocator = resolvedAllocator
        defer context.allocator = previousAllocator

        var bytes = try readFontSnapshot(fileName)
        return takeBytes(#move bytes, resolvedAllocator)
    }

    // Takes a private snapshot of bytes already in memory.
    //
    // The caller can overwrite or release the input after this call. Allocator lifetime and font
    // decoding follow [[TrueType.FontSource.loadFile]].
    func copy(bytes: const [..] u8, allocator: IAllocator? = null)->FontSource
    {
        let resolvedAllocator = unwrap (allocator orelse Swag.getContext().allocator)
        var owned = Array'u8{allocator: resolvedAllocator}
        owned.add(bytes)
        return takeBytes(#move owned, resolvedAllocator)
    }

    // Borrows the original bytes for inspection, including the original container header.
    //
    // The slice stays valid while this source is alive and retains the same snapshot.
    // A default source answers an empty slice.
    mtd const bytes()->const [..] u8
    {
        if let storage = .storage do
            return storage.bytes.toSlice()
        return ""
    }

    // Reads metadata for a zero-based member using this source's shared tables.
    //
    // The result owns its strings. Index and format checks follow [[TrueType.Face.metadataAt]].
    // For WOFF1, metadata and face loading share one reconstructed sfnt.
    mtd const metadataAt(faceIndex: u32 = 0)->FaceMetadata fail =>
        try Face.metadataAt(try .prepareBytes(faceIndex), faceIndex)

    // Loads one zero-based face while retaining this snapshot.
    //
    // Formats and index checks follow [[TrueType.Face.loadAt]]. The face allocator covers
    // per-face state. The source allocator covers the shared character maps, PostScript
    // programs and advances, glyph locations, glyph names, vertical metrics, and WOFF1
    // reconstruction.
    // A default source or invalid input fails.
    // Destroy the face with [[TrueType.Face.destroy]]. It can outlive this source value.
    mtd const loadFace(faceIndex: u32 = 0, allocator: IAllocator? = null)->*Face fail =>
        try loadFaceBytes(try .prepareBytes(faceIndex), faceIndex, "", allocator, source: me)
}

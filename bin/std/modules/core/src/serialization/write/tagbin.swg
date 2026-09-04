#global namespace Serialization
#global namespace Write
#global public

using Swag, Core.Errors

// Version mark written after the root signature. This is the only supported TagBin
// generation. It deliberately differs from every historical marker, so obsolete data
// stops at the header instead of being interpreted with another layout.
const TagBinVersion1 = 0xFAFAFAFC

// Header flags of a version 1 stream.
//
// These values are the on-disk format; never renumber them.
#[Swag.EnumFlags]
enum TagBinHeaderFlags: u32
{
    Zero             = 0     // No option is enabled.
    StreamCompressed = 1     // The whole body is stored as one deflate payload.
}

// Signatures used to tag different sections and elements in the binary serialization format
enum TagBinSignature: u32
{
    Root     = 0xC0DE0000     // Root element of the serialization structure
    Fat      = 0xC0DE0001     // FAT table identifier for unordered sections
    Sequence = 0xC0DE0002     // Start of a sequence (array or list)
    Version  = 0xC0DE0003     // Indicates that a version number is present
    Raw      = 0xC0DE0004     // Indicates raw POD data with no structure
    UnRaw    = 0xC0DE0005     // Indicates non-POD structured data
    ShapeDir = 0xC0DE0006     // Shape directory of a version 1 stream
}

// Shape id of a section whose fields are self-described in the stream rather than
// referenced from the shape directory. Used for dynamic fields written through
// 'Serializer.serialize' and for types that drive their own fields with 'ISerialize'.
const TagBinAdHocShape = 0xFFFFFFFF'u32

// Additional signature for each value in an ad-hoc section, stored after its key and
// static type identity.
//
// These numbers are the on-disk format, so both cases are pinned. Every element ever
// written carries bit 0, which is why [[Core.Serialization.Write.TagBinValueFlags.None]] is
// one rather than zero; renumbering them makes an existing stream decode its plain
// values as compressed ones.
#[Swag.EnumFlags]
enum TagBinValueFlags: u8
{
    None       = 1     // No value option is enabled.
    Compressed = 2     // The value payload is deflate compressed.
}

// Per-field flags stored in a shape directory entry of a version 1 stream.
//
// These values are the on-disk format; never renumber them.
#[Swag.EnumFlags]
enum TagBinShapeFlags: u8
{
    Zero       = 0     // No option is enabled.
    Compressed = 1     // Every payload of this field is stored as a deflate size pair.
}

// Internal state for a binary serialization section
struct TagBinSection
{
    public
    {
        startSeek:    ConcatBufferPosition                         // Position of the patched section header words.
        mapSeek:      HashTable'(string, ConcatBufferPosition)     // Ad-hoc sections: maps field keys to their position.
        keys:         ArrayPtr'String                              // Owns stable text borrowed by 'mapSeek'.
        offsets:      Array'u32                                    // Shaped sections: per-field offsets, relative to the section payload.
        plan:         const *Plan?                                 // Shaped sections: the plan driving the field order.
        payloadStart: u64                                          // Offset of the first payload byte of the section.
        fieldIndex:   u64                                          // Shaped sections: index of the next field to write.
        kind:         SectionKind                                  // Type of section (e.g., Raw or Unordered)
    }
}

// Binary writer for serialized data with support for structured and raw output.
//
// The writer produces the single version 1 layout described by
// [[Core.Serialization.Read.TagBin]].
#[Swag.Opaque]
struct TagBin
{
    public
    {
        compressionFlags:    Core.Compress.Deflate.CompressionFlags    = .Zero          // Compression flags associated with this value.
        compressionLevel:    Core.Compress.Deflate.CompressionLevel    = .BestSpeed     // Compression level associated with this value.
        compressionStrategy: Core.Compress.Deflate.CompressionStrategy = .Default       // Compression strategy associated with this value.

        // Identifies a document written through the low-level streaming API.
        //
        // `writeAll` uses the root type's [[Core.Serialization.Schema]] instead.
        schema: String

        // When true, the whole stream body is compressed as a single deflate payload at the
        // end of the write. This replaces the per-field 'Serialization.Compress' attribute
        // when most of the stream benefits from compression.
        compressStream: bool
    }

    // Writing state: the compressor, the section stack and the buffer pools it recycles.

    private
    {
        rootType:     typeinfo?                                              // Root type supplied by the high-level encoder.
        compressor:   Core.Compress.Deflate                                  // Compressor used for compressed sections.
        finalOutput:  *ConcatBuffer?                                         // Caller buffer receiving the header, then the body.
        output:       *ConcatBuffer?                                         // Current sink: the body, or a compressed element scratch.
        body:         ConcatBuffer                                           // Accumulates every section before the final assembly.
        shapeIds:     HashTable'(u64, u32)                                   // Maps each serialization plan address to its shape id.
        shapePlans:   Array'(const *Plan)                                    // The plan of each registered shape, by shape id.
        headerPatch:  ConcatBufferPosition                                   // Position of the shape directory offset in the header.
        freeSections: ArrayPtr'TagBinSection                                 // Pool of reusable section structures.
        sections:     ArrayPtr'TagBinSection                                 // Stack of currently active sections.
        outStack:     Array'(*ConcatBuffer?)                                 // Output buffers of the enclosing sections.
        elemStack:    Array'{ compressed: bool, tmpBuf: *ConcatBuffer? }     // Element stack.
        freeTmpBuf:   ArrayPtr'ConcatBuffer                                  // Pool of reusable scratch buffers.
    }
}

private impl TagBin
{
    // Creates or reuses a new section for writing
    mtd newSection()->*TagBinSection
    {
        if .freeSections.count
        {
            let ptr = .freeSections.popBack()!
            ptr.mapSeek.clear()
            ptr.keys.clear()
            ptr.offsets.clear()
            ptr.plan       = null
            ptr.fieldIndex = 0
            .sections.add(ptr)
            return ptr
        }

        return .sections.addNew()
    }

    // Releases the most recently added section and recycles it
    mtd releaseSection()
    {
        let ptr = .sections.popBack()
        .freeSections.add(ptr)
    }

    mtd acquireTmpBuf()->*ConcatBuffer
    {
        if .freeTmpBuf.count
        {
            let b = .freeTmpBuf.popBack()!
            b.clear()
            return b
        }

        return .freeTmpBuf.allocate()
    }

    mtd releaseTmpBuf(b: *ConcatBuffer)
    {
        b.clear()
        .freeTmpBuf.add(b)
    }

    // Returns the shape id of a plan, registering the shape on first use.
    mtd shapeIdFor(plan: const *Plan)->u32
    {
        let key = cast(u64) plan
        let e   = .shapeIds.tryFind(key)
        if e do
            return e.value

        let id = cast(u32) .shapePlans.count
        .shapePlans.add(plan)
        .shapeIds.add(key, id)
        return id
    }

    // Opens a section. A raw section starts with a patched byte length, so a reader can
    // verify that the raw layout it decoded is the one that was written.
    mtd beginSectionWithPlan(kind: SectionKind, plan: const *Plan?)
    {
        let sec = .newSection()
        sec.kind = kind
        sec.plan = plan

        let output = .output!
        if kind == .Raw
        {
            sec.startSeek = output.position()
            output.addNative(0'u64)     // Will store the raw byte length here
            sec.payloadStart = ConcatBuffer.offsetOf(output.position())
            return
        }

        if kind != .Unordered do
            return

        output.addNative(TagBinSignature.Fat)
        if plan do
            output.addNative(.shapeIdFor(plan!))
        else do
            output.addNative(TagBinAdHocShape)

        sec.startSeek = output.position()
        output.addNative(0'u64)     // Will store the fat offset here
        if !plan do
            output.addNative(0'u64)     // Ad-hoc sections also store the fat count here

        sec.payloadStart = ConcatBuffer.offsetOf(output.position())
    }
}

impl TagBin
{
    // Supplies the root type used to derive the document schema.
    #[Swag.NoDoc]
    mtd setRootType(type: typeinfo)
    {
        .rootType = type
    }

    // Tagbin is a binary format.
    mtd isTextual()->bool
    {
        return false
    }

    // Returns the wire identity written for a type value. See [[Core.Serialization.wireTypeCrc]].
    mtd typeCrcOf(type: typeinfo?)->u32
    {
        return wireTypeCrc(type)
    }

    // Writes a varint to an explicit buffer.
    mtd writeVarintTo(output: *ConcatBuffer, value: u64)
    {
        var v = value
        while v >= 0x80
        {
            output.addNative(cast(u8) ((v & 0x7F) | 0x80))
            v >>= 7
        }

        output.addNative(cast(u8) v)
    }

    // Writes an unsigned value as LEB128, the framing encoding of a version 1 stream.
    mtd writeVarint(value: u64)
    {
        .writeVarintTo(.output!, value)
    }

    // Validates and returns the stable key of a concrete interface object.
    #[Swag.NoDoc]
    mtd interfaceTypeKey(type: typeinfo?)->string fail
    {
        if !type do
            return ""

        let key = wireTypeKey(type)
        if key == "" do
            fail SerializationError{"interface object type needs a Serialization.TypeKey attribute"}
        if Reflection.typeFromKey(key) != type do
            fail SerializationError{Errors.mkString(Format.toString("interface object key [[%]] does not resolve to one registered type", key))}
        return key
    }

    // Writes the stable key of a concrete interface object.
    #[Swag.NoDoc]
    mtd writeInterfaceType(type: typeinfo?) fail
    {
        let key = .interfaceTypeKey(type)
        .writeVarint(key.count)
        .output!.addBytes(key)
    }

    // Begins writing to a specified output buffer
    mtd startWrite(buf: *ConcatBuffer)
    {
        .finalOutput = buf
        .output      = &.body
        .body.clear()
        .shapeIds.clear()
        .shapePlans.clear()
        .outStack.clear()
        .elemStack.clear()
        .sections.clear()
    }

    // Begins the root section of the serialization structure
    mtd beginRoot()
    {
        let header = .finalOutput!
        header.addNative(TagBinSignature.Root)
        header.addNative(TagBinVersion1)

        let schema = .rootType ? wireSchema(.rootType) : .schema.toString()
        .writeVarintTo(header, schema.count)
        header.addBytes(schema)

        var flags: TagBinHeaderFlags = .Zero
        if .compressStream do
            flags.add(.StreamCompressed)
        header.addNative(flags)

        .headerPatch = header.position()
        header.addNative(0'u64)     // Will store the shape directory offset here
    }

    // Ends the root: writes the shape directory, patches the header, then appends the
    // body to the caller buffer, compressing it when requested.
    mtd endRoot()
    {
        Debug.assert(.sections.isEmpty())
        Debug.assert(.output == &.body)

        // Shape directory: the field list of every struct type used by the stream,
        // written once.
        let shapeDirOffset = ConcatBuffer.offsetOf(.body.position())
        .body.addNative(TagBinSignature.ShapeDir)
        .writeVarint(.shapePlans.count)
        for plan in .shapePlans
        {
            .writeVarint(plan.fields.count)
            for &pf in plan.fields
            {
                .writeVarint(pf.key.count)
                .body.addBytes(pf.key)
                .body.addNative(pf.wireCrc)
                var flags: TagBinShapeFlags = .Zero
                if pf.compressed do
                    flags.add(.Compressed)
                .body.addNative(flags)
            }
        }

        let header = .finalOutput!
        let endPos = header.position()
        header.setPosition(.headerPatch)
        header.addNative(shapeDirOffset)
        header.setPosition(endPos)

        // The body always holds at least the shape directory, so the slice exists.
        .body.makeLinear()
        let bodyBytes = .body.toSlice()!

        if .compressStream
        {
            .compressor.init(.compressionLevel, .compressionStrategy, .compressionFlags)

            var compressBuffer: Array'u8
            catch .compressor.compress(&compressBuffer, bodyBytes) as err

            if err != null or compressBuffer.count >= bodyBytes.count
            {
                // Equal sizes tell the reader the body is stored uncompressed.
                header.addNative(cast(u64) bodyBytes.count)
                header.addNative(cast(u64) bodyBytes.count)
                header.addBytes(bodyBytes)
            }
            else
            {
                header.addNative(cast(u64) bodyBytes.count)
                header.addNative(compressBuffer.count)
                header.addBytes(compressBuffer.toSlice())
            }
        }
        else
        {
            header.addBytes(bodyBytes)
        }

        .body.clear()
        .rootType = null
    }

    // Begins a new section of the specified kind
    mtd beginSection(kind: SectionKind)
    {
        .beginSectionWithPlan(kind, null)
    }

    // Ends the current section and writes out any required metadata
    mtd endSection()
    {
        let sec    = .sections.back()!
        let output = .output!

        if sec.kind == .Raw
        {
            // Patch the raw byte length.
            let curSeek = output.position()
            let rawLen  = ConcatBuffer.offsetOf(curSeek) - sec.payloadStart
            output.setPosition(sec.startSeek)
            output.addNative(rawLen)
            output.setPosition(curSeek)
        }
        elif sec.kind == .Unordered and sec.plan
        {
            // Shaped section: the fat is the per-field offsets, in shape order.
            let fatSeek = ConcatBuffer.offsetOf(output.position())
            for off in sec.offsets do
                output.addNative(off)

            let curSeek = output.position()
            output.setPosition(sec.startSeek)
            output.addNative(fatSeek)
            output.setPosition(curSeek)
        }
        elif sec.kind == .Unordered
        {
            // Ad-hoc section: the fat carries its own crc/offset pairs and its count.
            let fatSeek = ConcatBuffer.offsetOf(output.position())
            output.addNative(TagBinSignature.Fat)
            for k, v in sec.mapSeek
            {
                .writeVarint(k.count)
                output.addBytes(k)
                output.addNative(ConcatBuffer.offsetOf(v))     // Offset inside the body
            }

            let curSeek = output.position()
            output.setPosition(sec.startSeek)
            output.addNative(fatSeek)
            output.addNative(sec.mapSeek.count)
            output.setPosition(curSeek)
        }

        .releaseSection()
    }

    // Begins a new struct, writing versioning and section metadata
    mtd beginStruct(structType: typeinfo?, _structData: const [*] u8?)->bool fail
    {
        let output = .output!
        if !structType
        {
            output.addNative(TagBinSignature.Version)
            output.addNative(0'u32)
            .beginSectionWithPlan(.Unordered, null)
            return false
        }

        let plan = planFor(cast(const *Swag.TypeInfoStruct) structType!)
        if plan.podFinal
        {
            output.addNative(TagBinSignature.Raw)
            .beginSectionWithPlan(.Raw, null)
            return false
        }

        output.addNative(TagBinSignature.Version)
        output.addNative(plan.version)

        // A type that drives its own fields through 'ISerialize' can write anything, so
        // its section stays self-described instead of referencing a shape.
        .beginSectionWithPlan(.Unordered, plan.hasCustom ? null : plan)
        return false
    }

    // Ends the current struct section
    mtd endStruct()
    {
        .endSection()
    }

    // Begins a new element inside the current section and records its metadata
    mtd beginElement(val: TypeValue) fail
    {
        Debug.assert(!.sections.isEmpty(), "Missing a previous 'beginSection' call")

        // If section is raw, then we just have values without versioning
        let sec = .sections.back()!
        if sec.kind == .Raw do
            return

        let output = .output!
        var compressed: bool

        if sec.plan
        {
            // Shaped section: fields arrive in plan order, so the element carries no
            // inline metadata at all. Its offset goes to the fat, everything else is in
            // the shape.
            let plan = sec.plan!
            Debug.assert(sec.fieldIndex < plan.fields.count)
            let pf = plan.fields.buffer! + sec.fieldIndex
            Debug.assert(pf.key == wireFieldKey(val))
            sec.fieldIndex += 1

            let off = ConcatBuffer.offsetOf(output.position()) - sec.payloadStart
            if off > cast(u64) Swag.U32.Max do
                fail SerializationError{"section payload exceeds the 4 GiB shaped section limit", field: val}
            sec.offsets.add(cast(u32) off)

            compressed = pf.compressed
        }
        else
        {
            let key = wireFieldKey(val)
            if key == "" do
                fail SerializationError{"serialized field needs a non-empty key", field: val}

            if sec.mapSeek.contains(key) do
                fail SerializationError{Errors.mkString(Format.toString("serialized ad-hoc field key [[%]] is already used", key)), field: val}
            let ownedKey = sec.keys.addNew()
            ownedKey[] = String.from(key)
            sec.mapSeek.add(ownedKey[].toString(), output.position())

            // Write element signature
            .writeVarint(key.count)
            output.addBytes(key)
            output.addNative(wireTypeCrc(val.pointedType))

            var valSig: TagBinValueFlags = .None
            compressed = Reflection.hasAttribute(val, Compress) or Reflection.hasAttribute(val.pointedType, Compress)
            if compressed do
                valSig.add(TagBinValueFlags.Compressed)
            output.addNative(valSig)
        }

        // If compressed, push a new ConcatBuffer that will collect all payload for this element
        if compressed
        {
            // push parent buffer on stack and switch current output
            let tmp = .acquireTmpBuf()
            .elemStack.add({compressed: true, tmpBuf: tmp})

            // From now, write to this temporary output
            .outStack.add(.output)
            .output = tmp
        }
        else
        {
            // track a non-compressed element to keep nesting consistent
            .elemStack.add({false, null})
        }
    }

    // Ends the current element, flushing its compressed payload if any
    mtd endElement(val: TypeValue)
    {
        // If section is raw, then we just have values without versioning
        let sec = .sections.back()!
        if sec.kind == .Raw do
            return

        Debug.assert(!.elemStack.isEmpty())
        let ctx = .elemStack.popBack()
        if !ctx.compressed do
            return

        // We must have a previous buffer to append into
        Debug.assert(!.outStack.isEmpty())
        let parentOut = .outStack.popBack()!

        // Gather uncompressed bytes
        let tmpBuf     = ctx.tmpBuf!
        let childBytes = tmpBuf.toString()

        // Compress
        .compressor.init(.compressionLevel, .compressionStrategy, .compressionFlags)

        var compressBuffer: Array'u8
        catch .compressor.compress(&compressBuffer, childBytes.toSlice()) as err

        if compressBuffer.count >= childBytes.length or err != null
        {
            // No compression, just store input
            parentOut.addNative(childBytes.length)     // uncompressedSize
            parentOut.addNative(childBytes.length)     // compressedSize
            parentOut.addBytes(childBytes)
        }
        else
        {
            parentOut.addNative(childBytes.length)        // uncompressedSize
            parentOut.addNative(compressBuffer.count)     // compressedSize
            parentOut.addBytes(compressBuffer.toSlice())
        }

        // Switch current 'output' back to parent and recycle tmp
        .output = parentOut
        .releaseTmpBuf(tmpBuf)
    }

    // Begins a value (stubbed out)
    mtd beginValue() {}

    // Ends a value (stubbed out)
    mtd endValue() {}

    // Begins a sequence and determines if elements can be written in bulk as raw data
    mtd beginSequence(typeElem: typeinfo?, data: const *void?, countElem: u64)->bool
    {
        let output = .output!
        output.addNative(TagBinSignature.Sequence)
        .writeVarint(countElem)

        // Dynamic array of raw serializable types
        // Just write them in one batch
        if Reflection.isDynamicArray(typeElem)
        {
            let valueType     = Reflection.dynamicArrayElementType(typeElem)
            let {raw, sizeof} = isPodFinal(valueType)

            if raw
            {
                // The byte length lets a reader verify the raw element layout and skip
                // the payload even when the element type changed.
                output.addNative(TagBinSignature.Raw)
                .writeVarint(countElem * sizeof)
                if !data do
                    return true
                let bufArr = cast(const *Array'u8) data
                output.addBytes(Swag.makeSlice(bufArr.buffer, countElem * sizeof))
                return true
            }
            else
            {
                output.addNative(TagBinSignature.UnRaw)
            }
        }

        // Static array of raw serializable types
        else
        {
            let {raw, sizeof} = isPodFinal(typeElem)
            if raw
            {
                output.addNative(TagBinSignature.Raw)
                .writeVarint(countElem * sizeof)
                if !data do
                    return true
                output.addBytes(Swag.makeSlice(cast(const [*] u8) data, countElem * sizeof))
                return true
            }
            else
            {
                output.addNative(TagBinSignature.UnRaw)
            }
        }

        return false
    }

    // Ends a sequence (stubbed out)
    mtd endSequence() {}

    /////////////////////////////////
    // VALUES
    /////////////////////////////////

    // Writes a native value to the output buffer, with special handling for strings
    mtd(NT) writeNative(value: NT)
    {
        let output = .output!
        #static if Reflection.isString(NT)
        {
            .writeVarint(value.count)
            output.addBytes(value)
        }
        else
        {
            output.addNative(value)
        }
    }
}

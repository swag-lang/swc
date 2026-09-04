#global namespace Serialization
#global namespace Read
#global public

using Swag, Core.Errors

// Names the buffer type.
alias Buffer = Array'u8

// Highest ratio deflate can reach, one stored bit per output byte plus block
// overhead. A payload announcing more expansion than this is corrupt.
private const DeflateMaxExpansion = 1032'u64

// Shape index of a field reference coming from a stream without shapes.
private const NoShapeIndex = 0xFFFFFFFF'u32

/*
Binary serializer with schema and key based compatibility.
Changes that are supported from V to V+1 are:

- Add a new field. The new field will stay at the default value.
- Remove a field. It will just be ignored.
- Reorder of fields, as long as their name/type are the same.
- Rename a field that declares a stable 'Serialization.Key'.

Supported type changes are :

- Conversion from integer/float/rune/bool to integer/float/rune/bool.
- Change the underlying type of an enum.
- Change the size of a static array.
- Conversion from a static array to a dynamic `Core.Array`, and vice versa.
- Conversion from a single value to a static array or `Core.Array`, and vice versa.
- Rename a concrete interface implementation that declares a stable 'Serialization.TypeKey'.
- Convert an existing complex type to 'Serialization.Final'.

Supported attributes are :

- 'Serialization.Version'. The struct version, exposed while reading through [[Core.Serialization.Read.TagBin.version]].
- 'Serialization.Schema'. To identify and validate a root document independently from its type name.
- 'Serialization.Key'. To give one stable identity to a field.
- 'Serialization.TypeKey'. To give one stable identity to a serialized struct type.
- 'Serialization.Final'. The struct will be loaded/saved without versioning (faster and lower serialization size)

The persisted format is version 1. Earlier experimental layouts are not accepted.
*/
struct TagBin
{
    public
    {
        ignoreElements: Array'String          // Element names skipped while decoding.
        options:        TagBinOptions         // Compatibility behavior.
        diag:           TagBinDiagnostics     // What the decode had to tolerate. Inspect after reading.

        // Optionally identifies the document expected by the low-level streaming API.
        //
        // An empty value accepts any schema so generic inspectors can open a TagBin stream.
        // `readAll` always uses the root type's [[Core.Serialization.Schema]] instead.
        schema: String
    }

    stream:            ByteStream                      // Input cursor over the version 1 body.
    bodyBuffer:        Buffer                          // Owns the decompressed body of a compressed stream.
    shapes:            Array'TagBinShape               // Shape directory of a version 1 stream.
    freeSections:      ArrayPtr'TagBinSection          // Reusable section objects.
    sections:          ArrayPtr'TagBinSection          // Active section stack.
    convertNextNative: const *Swag.TypeInfoNative?     // Pending native conversion.
    convertValToArray: bool                            // Whether the next scalar becomes an array.
    convertArrayToVal: bool                            // Whether the next array becomes a scalar.
    outStack:          Array'{ buf: const [..] u8?, seek: u64 }
    elemStack:         Array'{ compressed: bool, tmpBuf: *Buffer? }
    tmpPool:           ArrayPtr'Buffer
    expectedRootType:  typeinfo?     // Root type supplied by [[Core.Serialization.Decoder.readAll]].
}

// Counters describing what a decode had to tolerate.
//
// They stay at zero for a stream that matches the current types exactly. A user of
// [[Core.Serialization.DecoderFlags.IgnoreStructFieldError]] should inspect them after
// reading: a load that silently dropped half its fields is what they exist to reveal.
struct TagBinDiagnostics
{
    public
    {
        fieldErrors:         u32     // Fields whose payload failed to decode and were reset or skipped.
        droppedStreamFields: u32     // Stream fields the current types no longer request.
        unknownTypes:        u32     // Element type crcs that resolved to no registered type.
        recoveredFields:     u32     // Fields recovered through the fat after a positional mismatch.
        corruptPayloads:     u32     // Raw payloads whose decoded length did not match the written one.
    }
}

// One field entry of a section index: where the payload sits, and which shape entry
// describes it.
struct TagBinFieldRef
{
    public
    {
        seek:       u64      // Stream position of the field.
        shapeIndex: u32      // Index in the section shape, or 'NoShapeIndex'.
        consumed:   bool     // Whether the field was requested by the decode.
    }
}

// One field of a shape directory entry.
struct TagBinShapeField
{
    public
    {
        key:     String                     // Stable, human-readable field key.
        crcType: u32                        // Wire identity of the field type.
        flags:   Write.TagBinShapeFlags     // Per-field flags.
    }
}

// The field list of one struct type, stored once per version 1 stream.
struct TagBinShape
{
    public fields: Array'TagBinShapeField     // The fields, in written order.
}

// Section information for tracking deserialization state within structured data.
struct TagBinSection
{
    public
    {
        mapSeek:       HashTable'(String, TagBinFieldRef)     // Field index of the section, keyed by readable identity.
        afterFatSeek:  u64                                    // Stream position right after the section and its fat.
        fatSeek:       u64                                    // Stream position of the fat table.
        fatCount:      u64                                    // Number of fat entries.
        payloadStart:  u64                                    // Stream position of the first payload byte.
        consumedCount: u64                                    // How many indexed fields the decode requested.
        posIndex:      u64                                    // Next field index in positional mode.
        version:       u32                                    // Version number of this section
        kind:          SectionKind                            // Type of section (ordered, unordered, or raw)
        positional:    bool                                   // Shape matches the plan, so fields are read in order.
        mapLoaded:     bool                                   // Whether 'mapSeek' is populated.
        shape:         const *TagBinShape?                    // Shape describing the stream fields.
        plan:          const *Plan?                           // The reader plan of the struct, when known.
    }
}

// Configuration options for controlling deserialization behavior.
struct TagBinOptions
{
    public tryForward: bool     // Accept to try to read a newest version, otherwise error
}

private impl TagBin
{
    // Create a new section for the deserialization stack.
    // Returns a pointer to a section object, either reused from the free pool or newly allocated.
    mtd newSection()->*TagBinSection
    {
        var ptr: *TagBinSection?
        if .freeSections.count
        {
            let recycled = .freeSections.popBack()!
            recycled.mapSeek.clear()
            .sections.add(recycled)
            ptr = recycled
        }
        else
        {
            ptr = .sections.addNew()
        }

        let sec = ptr!
        sec.version       = 0
        sec.consumedCount = 0
        sec.posIndex      = 0
        sec.positional    = false
        sec.mapLoaded     = false
        sec.shape         = null
        sec.plan          = null
        return sec
    }

    // Release the current section back to the free pool.
    // Pops the most recent section from the active stack and returns it to the reuse pool.
    mtd releaseSection()
    {
        let ptr = .sections.popBack()
        .freeSections.add(ptr)
    }

    mtd acquireTmpBuf()->*Buffer
    {
        if .tmpPool.count
        {
            let b = .tmpPool.popBack()!
            b.clear()
            return b
        }

        return .tmpPool.allocate()
    }

    mtd releaseTmpBuf(b: *Buffer)
    {
        b.clear()
        .tmpPool.add(b)
    }

    // Returns the number of unread bytes.
    mtd remaining()->u64
    {
        return .stream.length() - .stream.seek
    }

    // Reads a varint-sized UTF-8 string from the current stream.
    mtd readWireString()->String fail
    {
        var result: retval
        let count = .stream.readVarint()
        if count > .remaining() do
            fail SerializationError{"string runs past the end of the stream"}
        result.reserve(count)
        .stream.readBytes(result.buffer, count)
        result.length = count
        return result
    }

    // Check if type conversion is possible between 'fromType' and 'toType'.
    // Sets up conversion flags and returns true if the conversion is supported.
    mtd canConvertType(toType, fromType: typeinfo?)->bool
    {
        if toType == fromType do
            return true
        if !toType or !fromType do
            return false

        // An enum travels as its underlying type, so conversions consider that type: a
        // changed underlying width then reads as an ordinary native conversion.
        var dstType = toType!
        var srcType = fromType!
        if Reflection.isEnum(dstType) do
            dstType = Reflection.enumUnderlyingType(dstType)
        if Reflection.isEnum(srcType) do
            srcType = Reflection.enumUnderlyingType(srcType)
        if dstType == srcType
        {
            if Reflection.isSimpleNative(dstType) do
                .convertNextNative = cast(const *Swag.TypeInfoNative?) srcType
            return true
        }

        var fromStruct: const *Swag.TypeInfoStruct?
        var toStruct:   const *Swag.TypeInfoStruct?

        if Reflection.isStruct(srcType) do
            fromStruct = cast(const *Swag.TypeInfoStruct?) srcType
        if Reflection.isStruct(dstType) do
            toStruct = cast(const *Swag.TypeInfoStruct?) dstType

        // s64/float/bool/rune to s64/float/bool/rune
        if Reflection.isSimpleNative(dstType) and Reflection.isSimpleNative(srcType)
        {
            .convertNextNative = cast(const *Swag.TypeInfoNative?) srcType
            return true
        }

        if Reflection.isStaticArray(srcType)
        {
            let fromArr = cast(const *Swag.TypeInfoArray) srcType

            // Array to array, this is fine, we will deal with size change
            if Reflection.isStaticArray(dstType)
            {
                let toArr = cast(const *Swag.TypeInfoArray) dstType
                if .canConvertType(toArr.pointedType, fromArr.pointedType) do
                    return true
            }

            elif toStruct
            {
                // Static array to dynamic array
                if Reflection.isDynamicArray(toStruct)
                {
                    if .canConvertType(Reflection.dynamicArrayElementType(toStruct), fromArr.pointedType) do
                        return true
                }

                // Static array to single struct value
                elif .canConvertType(dstType, fromArr.pointedType)
                {
                    .convertArrayToVal = true
                    return true
                }
            }

            // Static array to single value
            elif .canConvertType(dstType, fromArr.pointedType)
            {
                .convertArrayToVal = true
                return true
            }
        }
        elif fromStruct
        {
            // Dynamic array to something...
            if Reflection.isDynamicArray(fromStruct)
            {
                // Dynamic array to Static array
                if Reflection.isStaticArray(dstType)
                {
                    let toArr = cast(const *Swag.TypeInfoArray) dstType
                    if .canConvertType(toArr.pointedType, Reflection.dynamicArrayElementType(fromStruct)) do
                        return true
                }

                // Dynamic array to dynamic array
                elif toStruct and Reflection.isDynamicArray(toStruct)
                {
                    if .canConvertType(Reflection.dynamicArrayElementType(toStruct), Reflection.dynamicArrayElementType(fromStruct)) do
                        return true
                }

                // Dynamic array to single value
                elif .canConvertType(dstType, Reflection.dynamicArrayElementType(fromStruct))
                {
                    .convertArrayToVal = true
                    return true
                }
            }
        }

        if Reflection.isStaticArray(dstType)
        {
            let toArr = cast(const *Swag.TypeInfoArray) dstType

            // Conversion from simple value to array
            if .canConvertType(toArr.pointedType, srcType)
            {
                .convertValToArray = true
                return true
            }
        }
        elif toStruct
        {
            // To dynamic array...
            if Reflection.isDynamicArray(toStruct)
            {
                // Conversion from simple value to Core.Array
                if (!fromStruct or !Reflection.isDynamicArray(fromStruct)) and .canConvertType(Reflection.dynamicArrayElementType(toStruct), srcType)
                {
                    .convertValToArray = true
                    return true
                }
            }

            // A statically requested structured payload is self-framed. Its source type
            // name is not part of the compatibility contract.
            elif fromStruct and !Reflection.isDynamicArray(fromStruct) do
                return true
        }

        return false
    }

    // Loads the readable key and offset pairs of an ad-hoc section into its field index.
    mtd loadSectionFat(sec: *TagBinSection) fail
    {
        let savedSeek = .stream.position()
        .stream.setPosition(sec.fatSeek)

        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Fat do
            fail SerializationError{"invalid fat signature"}

        var fatCount = sec.fatCount
        while fatCount
        {
            var key  = .readWireString()
            let seek = .stream.readNative'u64()
            if sec.mapSeek.contains(key) do
                fail SerializationError{"serialized field key is duplicated"}
            sec.mapSeek.add(#move key, {seek: seek, shapeIndex: NoShapeIndex})
            fatCount -= 1
        }

        sec.mapLoaded    = true
        sec.afterFatSeek = .stream.position()
        .stream.setPosition(savedSeek)
    }

    // Opens a section of a version 1 stream.
    //
    // 'plan' names the reader's own layout of the struct when known; it selects the
    // positional fast path when the stream shape is identical to it. Every validation
    // happens before the section is pushed: a failure after the push would leave an
    // orphan section for the enclosing 'endSection' to pop.
    mtd openSection(kind: SectionKind, plan: const *Plan?) fail
    {
        if kind == .Raw
        {
            // A raw section starts with its byte length, so the end of the decode can be
            // verified against what was written.
            let rawLen = .stream.readNative'u64()
            if rawLen > .remaining() do
                fail SerializationError{"raw section runs past the end of the stream"}

            let sec = .newSection()
            sec.kind         = kind
            sec.plan         = plan
            sec.payloadStart = .stream.position()
            sec.afterFatSeek = sec.payloadStart + rawLen
            return
        }

        if kind != .Unordered
        {
            let sec = .newSection()
            sec.kind = kind
            sec.plan = plan
            return
        }

        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Fat do
            fail SerializationError{"invalid fat signature"}

        let shapeId = .stream.readNative'u32()
        if shapeId == Write.TagBinAdHocShape
        {
            let fatSeek  = .stream.readNative'u64()
            let fatCount = .stream.readNative'u64()

            if fatSeek > .stream.length() do
                fail SerializationError{"fat table runs past the end of the stream"}

            let sec = .newSection()
            sec.kind         = kind
            sec.plan         = plan
            sec.fatSeek      = fatSeek
            sec.fatCount     = fatCount
            sec.afterFatSeek = 0

            catch .loadSectionFat(sec) as err
            if err != null
            {
                // The section is already live, so hand it back before reporting.
                .releaseSection()
                fail err
            }

            return
        }

        if shapeId >= .shapes.count do
            fail SerializationError{"invalid shape identifier"}
        let shape = .shapes.buffer! + shapeId

        let fatSeek      = .stream.readNative'u64()
        let payloadStart = .stream.position()
        let afterFatSeek = fatSeek + shape.fields.count * #sizeof(u32)
        if fatSeek < payloadStart or afterFatSeek > .stream.length() do
            fail SerializationError{"fat table runs past the end of the stream"}

        let sec = .newSection()
        sec.kind         = kind
        sec.plan         = plan
        sec.shape        = shape
        sec.fatSeek      = fatSeek
        sec.fatCount     = shape.fields.count
        sec.payloadStart = payloadStart
        sec.afterFatSeek = afterFatSeek

        // The shape matching the reader's own field list, in order, means every field
        // sits exactly where the decode expects it: read positionally and never touch
        // the fat. Ignored elements and custom 'ISerialize' fields break that pairing,
        // so they force the indexed path.
        if plan and !plan.hasCustom and .ignoreElements.isEmpty() and .shapeMatchesPlan(shape, plan!)
        {
            sec.positional = true
            return
        }

        .loadShapedFat(sec)
    }

    // Pairs the shape entries of a section with the per-field offsets of the current
    // instance, building the field index.
    mtd loadShapedFat(sec: *TagBinSection) fail
    {
        let shape     = sec.shape!
        let savedSeek = .stream.position()
        .stream.setPosition(sec.fatSeek)
        for i in shape.fields.count
        {
            let off = cast(u64) .stream.readNative'u32()
            let sf  = shape.fields[i]
            if sec.mapSeek.contains(sf.key) do
                fail SerializationError{"serialized field key is duplicated"}
            sec.mapSeek.add(sf.key, {sec.payloadStart + off, cast(u32) i})
        }

        sec.mapLoaded = true
        .stream.setPosition(savedSeek)
    }

    // Returns true when a stream shape lists exactly the fields of a reader plan.
    mtd shapeMatchesPlan(shape: const *TagBinShape, plan: const *Plan)->bool
    {
        if shape.fields.count != plan.fields.count do
            return false
        for i in shape.fields.count
        {
            if shape.fields[i].key != plan.fields[i].key do
                return false
            if shape.fields[i].crcType != plan.fields[i].wireCrc do
                return false
        }

        return true
    }

    // Enters the payload of an element, decompressing it when the stream says so.
    //
    // On return the element owns an entry on the element stack, and the stream reads
    // from the decompressed payload when one was present.
    mtd enterElementPayload(compressed: bool, val: TypeValue) fail
    {
        if !compressed
        {
            .elemStack.add({false, null})
            return
        }

        let uncompressedSize = .stream.readNative'u64()
        let compressedSize   = .stream.readNative'u64()

        // Both sizes come from the stream, so a truncated or foreign payload can
        // name any value at all. The compressed run must fit in what is left,
        // otherwise the element is not readable.
        if compressedSize > .remaining() do
            fail SerializationError{"compressed payload runs past the end of the stream", field: val}

        if uncompressedSize == compressedSize
        {
            .elemStack.add({false, null})
            return
        }

        let decompressedBuffer = .acquireTmpBuf()

        // The announced size is only a sizing hint: 'decompress' grows the
        // buffer on its own and rejects a malformed payload. Honour it only
        // while it stays within what deflate can produce from this input, so
        // a corrupt header cannot ask for an arbitrary allocation.
        if uncompressedSize <= compressedSize * DeflateMaxExpansion do
            decompressedBuffer.reserve(uncompressedSize)

        // Feed the decompressor exactly the announced run, so a malformed payload can
        // never consume the bytes of the elements that follow.
        let rem   = .stream.remainingBytes()
        let input = Swag.makeSlice(rem.buffer, compressedSize)

        var decompressor: Core.Compress.Inflate
        catch decompressor.decompress(decompressedBuffer, input) as err
        if err != null or decompressedBuffer.count != uncompressedSize
        {
            .releaseTmpBuf(decompressedBuffer)
            fail SerializationError{"corrupted compressed payload", field: val}
        }

        // track this element context
        .elemStack.add({true, decompressedBuffer})

        .outStack.add({.stream.readBuffer, .stream.seek + compressedSize})
        .stream.readBuffer = decompressedBuffer.toSlice()
        .stream.seek       = 0
    }

    // Checks the element type read from the stream against the requested one, arming a
    // conversion when they differ. Returns false when the element must be skipped.
    mtd checkElementType(streamCrc: u32, val: TypeValue) fail
    {
        let wantedCrc = wireTypeCrc(val.pointedType)
        if streamCrc == wantedCrc do
            return

        // We try to find a registered type with the crc from the stream.
        let streamType = Reflection.typeFromCrc(streamCrc)
        if !streamType
        {
            // A scalar has no self-validating framing, so reading an unknown type as
            // another width would silently produce garbage.
            var requested = val.pointedType orelse #typeof(u8)
            requested = Reflection.resolveAliases(requested)
            if Reflection.isEnum(requested) do
                requested = Reflection.enumUnderlyingType(requested)
            if Reflection.isSimpleNative(requested)
            {
                .diag.unknownTypes += 1
                fail SerializationError{"unknown value type in the stream", field: val}
            }

            // Structured payloads are framed and decoded through the statically
            // requested shape. Their runtime type name is not part of the contract.
            return
        }

        // The type exists, but we do not have a way to convert it to the requested
        // type.
        if !.canConvertType(val.pointedType, streamType) do
            fail SerializationError{"cannot convert field type", field: val}

        // It's an array in the stream, but now we want a single value.
        // Skip the sequence header
        if .convertArrayToVal
        {
            .convertArrayToVal = false
            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Sequence do
                fail SerializationError{"stream is corrupted", field: val}
            discard .stream.readVarint()

            let arraySig = .stream.readNative'u32()
            if arraySig != Write.TagBinSignature.Raw and arraySig != Write.TagBinSignature.UnRaw do
                fail SerializationError{"stream is corrupted", field: val}
            if arraySig == Write.TagBinSignature.Raw do
                discard .stream.readVarint()
        }
    }

    // Looks a field up by its canonical key. Marks the entry consumed and returns its
    // position, or 'found' false.
    mtd findFieldRef(sec: *TagBinSection, val: TypeValue)->{ found: bool, seek: u64, shapeIndex: u32 }
    {
        let reqKey = wireFieldKey(val)
        var ent    = sec.mapSeek.tryFind(reqKey)

        if !ent do
            return {false, 0, 0}

        if !ent.value.consumed
        {
            ent.value.consumed = true
            sec.consumedCount  += 1
        }

        return {true, ent.value.seek, ent.value.shapeIndex}
    }

    // Reads the stream header, re-bases the stream on the body, and loads the shape directory.
    mtd readShapedRoot() fail
    {
        let streamSchema = .readWireString()
        if .expectedRootType
        {
            let wantedSchema = wireSchema(.expectedRootType)
            if streamSchema != wantedSchema do
                fail SerializationError{Errors.mkString(Format.toString("document schema is [[%]], but the requested type needs [[%]]", streamSchema, wantedSchema))}
        }
        elif !.schema.isEmpty() and streamSchema != .schema do
            fail SerializationError{Errors.mkString(Format.toString("document schema is [[%]], but the reader needs [[%]]", streamSchema, .schema))}

        let flags          = .stream.readNative'Write.TagBinHeaderFlags()
        let shapeDirOffset = .stream.readNative'u64()

        if flags.has(.StreamCompressed)
        {
            let uncompressedSize = .stream.readNative'u64()
            let compressedSize   = .stream.readNative'u64()
            if compressedSize > .remaining() do
                fail SerializationError{"compressed body runs past the end of the stream"}

            let rem = .stream.remainingBytes()
            if uncompressedSize == compressedSize
            {
                .stream = ByteStream.openRead(Swag.makeSlice(rem.buffer, compressedSize))
            }
            else
            {
                if uncompressedSize <= compressedSize * DeflateMaxExpansion do
                    .bodyBuffer.reserve(uncompressedSize)

                var decompressor: Core.Compress.Inflate
                catch decompressor.decompress(&.bodyBuffer, Swag.makeSlice(rem.buffer, compressedSize)) as err
                if err != null or .bodyBuffer.count != uncompressedSize do
                    fail SerializationError{"corrupted compressed body"}

                .stream = ByteStream.openRead(.bodyBuffer.toSlice())
            }
        }
        else
        {
            .stream = ByteStream.openRead(.stream.remainingBytes())
        }

        // Load the shape directory, then rewind to the first section.
        if shapeDirOffset > .stream.length() do
            fail SerializationError{"shape directory runs past the end of the stream"}
        .stream.setPosition(shapeDirOffset)

        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.ShapeDir do
            fail SerializationError{"invalid shape directory signature"}

        var shapeCount = .stream.readVarint()
        if shapeCount > .remaining() do
            fail SerializationError{"corrupted shape directory"}
        .shapes.reserve(shapeCount)
        while shapeCount
        {
            let shape      = .shapes.emplaceInitAddress()
            var fieldCount = .stream.readVarint()
            if fieldCount > .remaining() do
                fail SerializationError{"corrupted shape directory"}
            shape.fields.reserve(fieldCount)
            while fieldCount
            {
                var sf: TagBinShapeField
                sf.key     = .readWireString()
                sf.crcType = .stream.readNative'u32()
                sf.flags   = .stream.readNative'Write.TagBinShapeFlags()
                shape.fields.add(sf)
                fieldCount -= 1
            }

            shapeCount -= 1
        }

        .stream.setPosition(0)
    }
}

impl TagBin
{
    // Supplies the root type used to validate the document schema.
    #[Swag.NoDoc]
    mtd setExpectedRootType(type: typeinfo)
    {
        .expectedRootType = type
    }

    // Reads and resolves the stable key of a concrete interface object.
    #[Swag.NoDoc]
    mtd readInterfaceType()->typeinfo? fail
    {
        let key = .readWireString()
        if key == "" do
            return null

        let type = Reflection.typeFromKey(key)
        if !type do
            fail SerializationError{Errors.mkString(Format.toString("cannot resolve interface object key [[%]]", key))}
        return type
    }

    // Initialize the deserializer with the given input byte array.
    // Sets up the private byte stream for reading from the provided data buffer.
    mtd startRead(input: const [..] u8) fail
    {
        .stream = ByteStream.openRead(input)
        .shapes.clear()
        .bodyBuffer.clear()
        .sections.clear()
        .outStack.clear()
        .elemStack.clear()
        .diag = TagBinDiagnostics{}
    }

    // Begin reading the root container of the serialized data.
    //
    // Validates the root signature and the only supported format marker.
    mtd beginRoot() fail
    {
        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Root do
            fail SerializationError{"invalid root signature"}

        let mark = .stream.readNative'u32()
        if mark != Write.TagBinVersion1 do
            fail SerializationError{"unsupported TagBin format version"}
        .readShapedRoot()
    }

    // Finish reading the root container.
    // Currently no cleanup is required, but this maintains the symmetric begin/end API.
    mtd endRoot() fail
    {
        .expectedRootType = null
    }

    // Begin reading a new section with the specified 'kind'.
    mtd beginSection(kind: SectionKind, _skipFat = false) fail => .openSection(kind, null)

    // Finish reading the current section.
    // Updates the stream position and releases the section back to the pool.
    mtd endSection() fail
    {
        let sec = .sections.back()!

        if sec.kind == .Raw
        {
            // A raw section knows its byte length: a decode that consumed a
            // different amount read a layout that is not the one written. This runs
            // inside no-fail cleanup paths, so the mismatch is recorded and the stream
            // repositioned; [[Core.Serialization.Decoder.end]] turns it into an error
            // for a strict decode.
            if .stream.position() != sec.afterFatSeek
            {
                .diag.corruptPayloads += 1
                .stream.setPosition(sec.afterFatSeek)
            }
        }
        else
        {
            // Count the stream fields the decode never requested; they are data a
            // rewrite of the value would lose.
            if sec.mapLoaded and sec.consumedCount < sec.mapSeek.count do
                .diag.droppedStreamFields += cast(u32) (sec.mapSeek.count - sec.consumedCount)

            // Fat is after the datas. We need to be sure to point
            // to what's next.
            .stream.setPosition(sec.afterFatSeek)
        }

        .releaseSection()
    }

    // Begin reading a struct of the given 'structType'.
    // Returns false for normal struct processing, true for special handling cases.
    mtd beginStruct(structType: typeinfo?, _structData: [*] u8?)->bool fail
    {
        var sig = .stream.readNative'u32()
        if sig == Write.TagBinSignature.Raw
        {
            // If the stream contains a 'raw' representation of the struct, and the requested
            // type is not a POD, then we can load in place.
            if !Reflection.hasAttribute(structType, Serialization.Final) do
                fail SerializationError{"cannot convert a type from final to non final"}

            .openSection(.Raw, null)
            return false
        }

        // Skip array in case of an array to value conversion
        if sig == Write.TagBinSignature.UnRaw do
            sig = .stream.readNative'u32()

        // Read struct version
        if sig != Write.TagBinSignature.Version do
            fail SerializationError{"invalid version signature"}
        let streamVersion = .stream.readNative'u32()

        var plan: const *Plan?
        if structType and Reflection.isStruct(structType) do
            plan = planFor(cast(const *Swag.TypeInfoStruct) structType!)

        // Deal with version
        if plan and plan.hasVersion
        {
            // The stream version is more recent than the code that tries to read it.
            // Specific error, except if we want to try forward compatibility
            if !.options.tryForward and plan.version < streamVersion do
                fail InvalidVersion{wantedVersion: plan.version, foundVersion: streamVersion}
        }

        .openSection(.Unordered, plan)

        .sections.back()!.version = streamVersion
        return false
    }

    // Finish reading the current struct.
    // Closes the current section that was opened by 'beginStruct'.
    mtd endStruct() fail
    {
        .endSection()
    }

    // Begin reading a field element identified by 'val'.
    // Returns true if the element exists in the stream and should be processed, false to skip it.
    mtd beginElement(val: TypeValue)->bool fail
    {
        Debug.assert(!.sections.isEmpty(), "Missing a previous 'beginSection' call")

        // If this name is in the ignore list, then skip it
        if .ignoreElements.contains(val.name)
        {
            .elemStack.add({false, null})
            return false
        }

        let sec = .sections.back()!

        // If section is raw, then we just have values without versionning
        if sec.kind == .Raw
        {
            .elemStack.add({false, null})
            return true
        }

        // Shaped positional path: the shape is the plan, so the field is the
        // next one in the stream and carries no inline metadata.
        if sec.positional
        {
            let shape = sec.shape!
            Debug.assert(sec.posIndex < shape.fields.count)
            let sf = shape.fields.buffer! + sec.posIndex
            Debug.assert(sf.key == wireFieldKey(val))
            sec.posIndex += 1

            catch .enterElementPayload(sf.flags.has(.Compressed), val) as err
            if err == null do
                return true

            // A corrupt payload does not condemn the rest of the struct: the fat was
            // written anyway, so demote the section to the indexed path and let every
            // remaining field seek its own position.
            .loadShapedFat(sec)
            sec.positional        = false
            .diag.recoveredFields += 1
            fail err
        }

        // Shaped indexed path.
        if sec.shape
        {
            let ent = .findFieldRef(sec, val)
            if !ent.found
            {
                .elemStack.add({false, null})
                return false
            }

            // The offset comes from the stream, so it can name any position at all.
            if ent.seek >= .stream.length() do
                fail SerializationError{"field offset runs past the end of the stream", field: val}

            .stream.setPosition(ent.seek)
            let sf = sec.shape.fields.buffer! + ent.shapeIndex

            .enterElementPayload(sf.flags.has(.Compressed), val)
            defer #fail catch .endElement(val)

            .checkElementType(sf.crcType, val)
            return true
        }

        // Ad-hoc sections carry their readable key and type inline.
        let reqKey = wireFieldKey(val)
        if sec.mapLoaded
        {
            let ent = .findFieldRef(sec, val)

            // The requested field is not there, just ignore it
            if !ent.found
            {
                .elemStack.add({false, null})
                return false
            }

            // The offset comes from the stream, so it can name any position at all.
            if ent.seek >= .stream.length() do
                fail SerializationError{"field offset runs past the end of the stream", field: val}

            // Otherwise we seek to the field in the stream
            .stream.setPosition(ent.seek)
        }

        // Read the name signature.
        let fieldKey = .readWireString()
        if fieldKey != reqKey do
            fail SerializationError{"serialized field key does not match the requested field", field: val}

        // Read the type signature.
        let crcType = .stream.readNative'u32()

        let flags = .stream.readNative'Write.TagBinValueFlags()

        .enterElementPayload(flags.has(.Compressed), val)

        // The element owns an entry on the stacks from here on. Whatever fails below
        // has to hand them back, because a caller pairs 'endElement' with a
        // 'beginElement' that returned and with nothing else.
        defer #fail catch .endElement(val)

        .checkElementType(crcType, val)
        return true
    }

    // Finish reading the current field element.
    // Clears any pending native type conversion state.
    mtd endElement(_val: TypeValue) fail
    {
        .convertNextNative = null

        Debug.assert(!.elemStack.isEmpty())
        let ctx = .elemStack.popBack()
        if !ctx.compressed do
            return

        // We must have a previous buffer to append into
        Debug.assert(!.outStack.isEmpty())
        let {parentOut, parentSeek} = .outStack.popBack()

        // Switch current 'output' back to parent and recycle tmp
        .stream.readBuffer = parentOut
        .stream.seek       = parentSeek
        .releaseTmpBuf(ctx.tmpBuf!)
    }

    // Begin reading a value within the current context.
    // Currently no special processing is required, but this maintains the symmetric API.
    mtd beginValue() fail {}

    // Finish reading a value within the current context.
    // Currently no cleanup is required, but this maintains the symmetric API.
    mtd endValue() fail {}

    // Begin reading a sequence (array) of elements of type 'typeElem'.
    // Updates 'countElem' with the actual number of elements and returns true for bulk reading optimization.
    mtd beginSequence(typeElem: typeinfo?, data: *u8?, countElem: *u64)->bool fail
    {
        let orgCount = countElem[]
        if .convertValToArray
        {
            countElem[] = 1
        }
        else
        {
            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Sequence do
                fail SerializationError{"stream is corrupted"}

            // 0 for a dynamic array, > 0 for a static array
            countElem[] = .stream.readVarint()

            // Every element takes at least one byte, so a count beyond the remaining
            // bytes is corrupt. Checking here keeps a hostile count from driving the
            // allocations below.
            if countElem[] > .remaining() do
                fail SerializationError{"sequence count runs past the end of the stream"}
        }

        // If we need a value conversion, we must read element by element
        if .convertValToArray
        {
            .convertValToArray = false
            return false
        }

        // If we need a type conversion, we must read element by element
        if .convertNextNative
        {
            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Raw and sig != Write.TagBinSignature.UnRaw do
                fail SerializationError{"stream is corrupted"}
            if sig == Write.TagBinSignature.Raw do
                discard .stream.readVarint()

            return false
        }

        // Dynamic array
        if Reflection.isDynamicArray(typeElem)
        {
            let valueType = Reflection.dynamicArrayElementType(typeElem)

            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Raw and sig != Write.TagBinSignature.UnRaw do
                fail SerializationError{"stream is corrupted"}

            // The Raw/UnRaw signature records how the writer laid out the elements and is
            // authoritative. Honor it rather than re-deriving from this build's
            // isPodFinal(valueType): the two can legitimately disagree if the element type's
            // 'Serialization.Final' status changed since the data was written (or it resolves
            // differently across a module boundary). Trusting the local result instead would
            // read raw bytes as framed values, or the reverse, and desync the whole stream.
            if sig == Write.TagBinSignature.Raw
            {
                // Raw bytes can only be loaded in place if the element type is still a plain
                // POD (same property the writer required to emit Raw). This stays robust to a
                // 'Serialization.Final' toggle on a POD type, and fails cleanly rather than
                // corrupting memory if the type became non-POD.
                if !Reflection.isPod(valueType) do
                    fail SerializationError{"cannot load a raw array into a non-pod element type"}

                let vt       = valueType!
                let elemSize = vt.sizeof

                // Validate the payload against the remaining bytes before any
                // allocation, so a corrupt count cannot request arbitrary memory.
                let byteCount = countElem[] * elemSize
                if elemSize != 0 and countElem[] > .remaining() / elemSize do
                    fail SerializationError{"raw sequence runs past the end of the stream"}

                // The stream also records the written byte length: a different
                // one means the raw element layout changed since the write.
                let byteLen = .stream.readVarint()
                if byteLen != byteCount do
                    fail SerializationError{"raw element layout changed"}

                let bufArr = cast(*Array'u8) data!
                bufArr.count = countElem[]
                bufArr.reserve(byteCount)
                bufArr.capacity = bufArr.count
                .stream.readBytes(bufArr.buffer, byteCount)
                return true
            }
        }

        // Static array
        else
        {
            let streamCount = countElem[]
            countElem[] = Math.min(orgCount, streamCount)

            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Raw and sig != Write.TagBinSignature.UnRaw do
                fail SerializationError{"stream is corrupted"}

            // Honor the stream's layout signature (see the dynamic-array case above).
            if sig == Write.TagBinSignature.Raw
            {
                if !Reflection.isPod(typeElem) do
                    fail SerializationError{"cannot load a raw array into a non-pod element type"}

                let te = typeElem!
                if te.sizeof != 0 and streamCount > .remaining() / te.sizeof do
                    fail SerializationError{"raw sequence runs past the end of the stream"}

                let byteLen = .stream.readVarint()
                if byteLen != streamCount * te.sizeof do
                    fail SerializationError{"raw element layout changed"}

                .stream.readBytes(data, countElem[] * te.sizeof)

                // The stream can hold more elements than the array does now; skip them
                // so the next value starts at the right position.
                if streamCount > countElem[] do
                    .stream.advance((streamCount - countElem[]) * te.sizeof)
                return true
            }
        }

        return false
    }

    // Finish reading the current sequence.
    // Currently no cleanup is required, but this maintains the symmetric API.
    mtd endSequence() fail {}

    // Advance to the next element in the current sequence.
    // Decrements 'countElem' and returns false when no more elements remain.
    mtd toNextSequenceElement(countElem: *u64)->bool
    {
        if countElem[] == 0 do
            return false
        countElem[] -= 1
        return true
    }

    // Check if this serializer uses textual representation.
    // Always returns false since this is a binary serializer.
    mtd isTextual()->bool
    {
        return false
    }

    // Get the version number of the current section.
    // Returns 0 if no sections are active, otherwise returns the version found in the stream for the innermost struct.
    mtd version()->u32
    {
        if .sections.isEmpty() do
            return 0
        let sec = .sections.back()!
        return sec.version
    }

    /////////////////////////////////
    // VALUES
    /////////////////////////////////

    // Read a native type value from the stream with automatic type conversion support.
    // Handles string types specially and performs type conversions when 'convertNextNative' is set.
    mtd(NT) readNative()->NT fail
    {
        #static if NT == Core.String
        {
            var result: retval
            let count = .stream.readVarint()

            // Validate before reserving, so a corrupt length cannot request an
            // arbitrary allocation. The error type stays fully qualified: this generic
            // body is exported and re-checked without this file's 'using' context.
            if count > .stream.length() - .stream.seek do
                fail Core.Errors.SerializationError{"string runs past the end of the stream"}

            result.reserve(count)
            .stream.readBytes(result.buffer, count)
            result.length = count
            return result
        }
        else
        {
            if .convertNextNative
            {
                #[Swag.Safety(.All, false)]
                switch .convertNextNative.nativeKind
                {
                case .Bool:
                    let v = .stream.readNative'bool()
                    return cast(NT) v

                case .U8:
                    let v = .stream.readNative'u8()
                    return cast(NT) v

                case .U16:
                    let v = .stream.readNative'u16()
                    return cast(NT) v

                case .U32, .Rune:
                    let v = .stream.readNative'u32()
                    return cast(NT) v

                case .U64:
                    let v = .stream.readNative'u64()
                    return cast(NT) v

                case .S8:
                    let v = .stream.readNative's8()
                    return cast(NT) v

                case .S16:
                    let v = .stream.readNative's16()
                    return cast(NT) v

                case .S32:
                    let v = .stream.readNative's32()
                    return cast(NT) v

                case .S64:
                    let v = .stream.readNative's64()
                    return cast(NT) v

                case .F32:
                    let v = .stream.readNative'f32()
                    return cast(NT) v

                case .F64:
                    let v = .stream.readNative'f64()
                    return cast(NT) v
                }
            }

            return .stream.readNative'NT()
        }
    }
}

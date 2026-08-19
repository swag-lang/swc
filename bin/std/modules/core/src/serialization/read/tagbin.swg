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
Binary serializer with forward/backward compatibility.
Changes that are supported from V to V+1 are :

- Add a new field. The new field will stay at the default value.
- Remove a field. It will just be ignored.
- Reorder of fields, as long as their name/type are the same.
- Rename a field with 'Serialization.Alias'.

Supported type changes are :

- Conversion from integer/float/rune/bool to integer/float/rune/bool.
- Change the underlying type of an enum.
- Change the size of a static array.
- Conversion from a static array to a dynamic `Core.Array`, and vice versa.
- Conversion from a single value to a static array or `Core.Array`, and vice versa.
- Rename a struct with 'Serialization.Alias'.
- Convert an existing complexe type to 'Serialization.Final'

Supported attributes are :

- 'Serialisation.Version'. The struct version, exposed while reading through [[Core.Serialization.Read.TagBin.version]].
- 'Serialization.Alias'. To rename a field or a struct type. Multiple aliases are supported.
- 'Serialization.Final'. The struct will be loaded/saved without versioning (faster and lower serialization size)

The reader accepts the three stream generations described in
[[Core.Serialization.Write.TagBin]]; the writer always produces the current one.
*/
struct TagBin
{
    public
    {
        ignoreElements: Array'String          // Element names skipped while decoding.
        options:        TagBinOptions         // Compatibility behavior.
        diag:           TagBinDiagnostics     // What the decode had to tolerate. Inspect after reading.
    }

    wire:              u32                                  // Stream generation: 0, 1 or 2.
    hasValueFlags:     bool                                 // Whether each element carries a value-flags byte (version 1).
    stream:            ByteStream                           // Input cursor, over the body for a version 2 stream.
    bodyBuffer:        Buffer                               // Owns the decompressed body of a compressed stream.
    shapes:            Array'TagBinShape                    // Shape directory of a version 2 stream.
    freeSections:      ArrayPtr'TagBinSection               // Reusable section objects.
    sections:          ArrayPtr'TagBinSection               // Active section stack.
    convertNextNative: #null const *Swag.TypeInfoNative     // Pending native conversion.
    convertValToArray: bool                                 // Whether the next scalar becomes an array.
    convertArrayToVal: bool                                 // Whether the next array becomes a scalar.
    outStack:          Array'{ buf: #null const [..] u8, seek: u64 }
    elemStack:         Array'{ compressed: bool, tmpBuf: #null *Buffer }
    tmpPool:           ArrayPtr'Buffer
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
        crcName: u32                        // Crc of the field name.
        crcType: u32                        // Wire identity of the field type.
        flags:   Write.TagBinShapeFlags     // Per-field flags.
    }
}

// The field list of one struct type, stored once per version 2 stream.
struct TagBinShape
{
    public fields: Array'TagBinShapeField     // The fields, in written order.
}

// Section information for tracking deserialization state within structured data.
struct TagBinSection
{
    public
    {
        mapSeek:       HashTable'(u32, TagBinFieldRef)     // Field index of the section, keyed by name crc.
        afterFatSeek:  u64                                 // Stream position right after the section and its fat.
        fatSeek:       u64                                 // Stream position of the fat table.
        fatCount:      u64                                 // Number of fat entries.
        payloadStart:  u64                                 // Stream position of the first payload byte (version 2).
        consumedCount: u64                                 // How many indexed fields the decode requested.
        posIndex:      u64                                 // Next field index in positional mode (version 2).
        version:       u32                                 // Version number of this section
        kind:          SectionKind                         // Type of section (ordered, unordered, or raw)
        skipFat:       bool                                // Version 1: positional read, the fat was not loaded.
        positional:    bool                                // Version 2: shape matches the plan, fields read in order.
        mapLoaded:     bool                                // Whether 'mapSeek' is populated.
        shape:         #null const *TagBinShape            // Version 2: the shape describing the stream fields.
        plan:          #null const *Plan                   // The reader plan of the struct, when known.
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
        var ptr: #null *TagBinSection
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
        sec.skipFat       = false
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

    // Check if type conversion is possible between 'fromType' and 'toType'.
    // Sets up conversion flags and returns true if the conversion is supported.
    mtd canConvertType(toType, fromType: #null typeinfo)->bool
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
                .convertNextNative = cast(#null const *Swag.TypeInfoNative) srcType
            return true
        }

        var fromStruct: #null const *Swag.TypeInfoStruct
        var toStruct:   #null const *Swag.TypeInfoStruct

        if Reflection.isStruct(srcType) do
            fromStruct = cast(#null const *Swag.TypeInfoStruct) srcType
        if Reflection.isStruct(dstType) do
            toStruct = cast(#null const *Swag.TypeInfoStruct) dstType

        // s64/float/bool/rune to s64/float/bool/rune
        if Reflection.isSimpleNative(dstType) and Reflection.isSimpleNative(srcType)
        {
            .convertNextNative = cast(#null const *Swag.TypeInfoNative) srcType
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

            // Struct to struct...
            elif fromStruct and !Reflection.isDynamicArray(fromStruct)
            {
                // Alias
                let aliases = Reflection.attributes(dstType, Serialization.Alias)
                for al in aliases
                {
                    let value = Reflection.attributeValue(al, "name")
                    if cast(#null string) value == srcType.name
                    {
                        return true
                    }
                }
            }
        }

        return false
    }

    // Loads the fat of a section into its field index.
    //
    // Works for a version 0/1 fat and for the ad-hoc fat of a version 2 stream, which
    // share the same layout: a fat signature followed by crc/offset pairs.
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
            let crc  = .stream.readNative'u32()
            let seek = .stream.readNative'u64()
            sec.mapSeek.add(crc, {seek, NoShapeIndex, false})
            fatCount -= 1
        }

        sec.mapLoaded = true
        .stream.setPosition(savedSeek)
    }

    // Opens a section of a version 0 or version 1 stream.
    //
    // Every validation happens before the section is pushed: a failure after the push
    // would leave an orphan section for the enclosing 'endSection' to pop.
    mtd beginSection1(kind: SectionKind, skipFat: bool) fail
    {
        if kind != .Unordered
        {
            let sec = .newSection()
            sec.kind    = kind
            sec.skipFat = skipFat
            return
        }

        // Read fat position and count
        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Fat do
            fail SerializationError{"invalid fat signature"}
        let fatSeek  = .stream.readNative'u64()
        let fatCount = .stream.readNative'u64()

        // The fat sits after the payload: signature, then a crc/offset pair per field.
        let afterFatSeek = fatSeek + #sizeof(u32) + fatCount * (#sizeof(u32) + #sizeof(u64))
        if afterFatSeek > .stream.length() do
            fail SerializationError{"fat table runs past the end of the stream"}

        let sec = .newSection()
        sec.kind         = kind
        sec.skipFat      = skipFat
        sec.fatSeek      = fatSeek
        sec.fatCount     = fatCount
        sec.afterFatSeek = afterFatSeek

        if !skipFat
        {
            catch .loadSectionFat(sec) as err
            if err != null
            {
                // The section is already live, so hand it back before reporting.
                .releaseSection()
                fail err
            }

            .stream.setPosition(sec.afterFatSeek)
        }
    }

    // Opens a section of a version 2 stream.
    //
    // 'plan' names the reader's own layout of the struct when known; it selects the
    // positional fast path when the stream shape is identical to it. Every validation
    // happens before the section is pushed: a failure after the push would leave an
    // orphan section for the enclosing 'endSection' to pop.
    mtd beginSection2(kind: SectionKind, plan: #null const *Plan) fail
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

            let afterFatSeek = fatSeek + #sizeof(u32) + fatCount * (#sizeof(u32) + #sizeof(u64))
            if afterFatSeek > .stream.length() do
                fail SerializationError{"fat table runs past the end of the stream"}

            let sec = .newSection()
            sec.kind         = kind
            sec.plan         = plan
            sec.fatSeek      = fatSeek
            sec.fatCount     = fatCount
            sec.afterFatSeek = afterFatSeek

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
            sec.mapSeek.add(shape.fields[i].crcName, {sec.payloadStart + off, cast(u32) i, false})
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
            if shape.fields[i].crcName != plan.fields[i].crcName do
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
        let input = @mkslice(@dataof(rem), compressedSize)

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
        let wantedCrc = .wire >= 2 ? wireTypeCrc(val.pointedType) : getTypeInfoCrc(val.pointedType)
        if streamCrc == wantedCrc do
            return

        // We try to find a registered type with the crc from the stream.
        let streamType = Reflection.typeFromCrc(streamCrc)
        if !streamType
        {
            .diag.unknownTypes += 1

            // A version 0/1 stream can carry type crcs from a previous hash scheme, so
            // an unknown crc is read with the requested type and the payload readers
            // validate the bytes. A version 2 stream carries current crcs only; a scalar
            // has no self-validating framing, so reading it as another width would
            // silently produce garbage.
            if .wire >= 2
            {
                var requested = val.pointedType orelse #typeof(u8)
                requested = Reflection.resolveAliases(requested)
                if Reflection.isEnum(requested) do
                    requested = Reflection.enumUnderlyingType(requested)
                if Reflection.isSimpleNative(requested) do
                    fail SerializationError{"unknown value type in the stream", field: val}
            }

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
            if .wire >= 2 do
                discard .stream.readVarint()
            else do
                discard .stream.readNative'u64()

            let arraySig = .stream.readNative'u32()
            if arraySig != Write.TagBinSignature.Raw and arraySig != Write.TagBinSignature.UnRaw do
                fail SerializationError{"stream is corrupted", field: val}
            if .wire >= 2 and arraySig == Write.TagBinSignature.Raw do
                discard .stream.readVarint()
        }
    }

    // Looks a field up in the section index by its name, then by its declared aliases.
    // Marks the entry consumed and returns its position, or 'found' false.
    mtd findFieldRef(sec: *TagBinSection, val: TypeValue)->{ found: bool, seek: u64, shapeIndex: u32 }
    {
        let reqCrc = getTypeValueCrc(val)
        var ent    = sec.mapSeek.tryFind(reqCrc)

        if !ent
        {
            // The plan caches the alias crcs of its own fields; a dynamic field falls
            // back to its attributes.
            var scanAttributes = true
            if sec.plan
            {
                let pf = sec.plan.fieldByCrc(reqCrc)
                if pf
                {
                    scanAttributes = false
                    for aliasCrc in pf.aliases
                    {
                        ent = sec.mapSeek.tryFind(aliasCrc)
                        if ent do
                            break
                    }
                }
            }

            if !ent and scanAttributes
            {
                let aliases = Reflection.attributes(val, Serialization.Alias)
                for al in aliases
                {
                    let value = Reflection.attributeValue(al, "name")
                    Debug.assert(value != null)
                    ent = sec.mapSeek.tryFind(Hash.Crc32.compute(cast(string) value!))
                    if ent do
                        break
                }
            }
        }

        if !ent do
            return {false, 0, 0}

        if !ent.value.consumed
        {
            ent.value.consumed = true
            sec.consumedCount  += 1
        }

        return {true, ent.value.seek, ent.value.shapeIndex}
    }

    // Reads the version 2 header, re-bases the stream on the body, and loads the shape
    // directory.
    mtd readRootV2() fail
    {
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
                .stream = ByteStream.openRead(@mkslice(@dataof(rem), compressedSize))
            }
            else
            {
                if uncompressedSize <= compressedSize * DeflateMaxExpansion do
                    .bodyBuffer.reserve(uncompressedSize)

                var decompressor: Core.Compress.Inflate
                catch decompressor.decompress(&.bodyBuffer, @mkslice(@dataof(rem), compressedSize)) as err
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
                sf.crcName = .stream.readNative'u32()
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
    // Peeks the field name crcs of the struct at the current stream position.
    //
    // Used to infer the concrete type of a serialized interface when its stored type
    // crc resolves to nothing.
    mtd peekStructFieldCrcs(fieldCrcs: *Array'u32)->bool fail
    {
        let savedSeek = .stream.position()
        defer .stream.setPosition(savedSeek)

        var sig = .stream.readNative'u32()
        if sig == Write.TagBinSignature.UnRaw do
            sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Version do
            return false

        discard .stream.readNative'u32()
        sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Fat do
            return false

        if .wire >= 2
        {
            let shapeId = .stream.readNative'u32()
            if shapeId != Write.TagBinAdHocShape
            {
                if shapeId >= .shapes.count do
                    return false
                for &sf in .shapes[shapeId].fields do
                    fieldCrcs.add(sf.crcName)
                return true
            }
        }

        let fatSeek  = .stream.readNative'u64()
        var fatCount = .stream.readNative'u64()

        if fatSeek >= .stream.length() do
            return false
        .stream.setPosition(fatSeek)
        sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Fat do
            return false

        while fatCount
        {
            fieldCrcs.add(.stream.readNative'u32())
            discard .stream.readNative'u64()
            fatCount -= 1
        }

        return true
    }

    // Initialize the deserializer with the given input byte array.
    // Sets up the private byte stream for reading from the provided data buffer.
    mtd startRead(input: const [..] u8) fail
    {
        .stream = ByteStream.openRead(input)
        .wire   = 0
        .shapes.clear()
        .bodyBuffer.clear()
        .sections.clear()
        .outStack.clear()
        .elemStack.clear()
        .diag = TagBinDiagnostics{}
    }

    // Begin reading the root container of the serialized data.
    //
    // Validates the root signature, then establishes which stream generation follows:
    // the version mark cannot be mistaken for what an older stream puts at the same
    // position, because that position then holds a 'TagBinSignature' and the constants
    // are disjoint.
    mtd beginRoot() fail
    {
        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Root do
            fail SerializationError{"invalid root signature"}

        let mark = .stream.readNative'u32()
        if mark == Write.TagBinVersion2
        {
            .wire = 2
            .readRootV2()
            return
        }

        if mark == Write.TagBinVersion1
        {
            .wire          = 1
            .hasValueFlags = true
            return
        }

        .stream.setPosition(.stream.position() - #sizeof(u32))
        .wire          = 0
        .hasValueFlags = false
    }

    // Finish reading the root container.
    // Currently no cleanup is required, but this maintains the symmetric begin/end API.
    mtd endRoot() fail {}

    // Begin reading a new section with the specified 'kind'.
    // Optionally skips reading the fat table if 'skipFat' is true for performance optimization.
    mtd beginSection(kind: SectionKind, skipFat = false) fail
    {
        if .wire >= 2 do
            .beginSection2(kind, null)
        else do
            .beginSection1(kind, skipFat)
    }

    // Finish reading the current section.
    // Updates the stream position and releases the section back to the pool.
    mtd endSection() fail
    {
        let sec = .sections.back()!

        if sec.kind == .Raw
        {
            // A version 2 raw section knows its byte length: a decode that consumed a
            // different amount read a layout that is not the one written. This runs
            // inside no-fail cleanup paths, so the mismatch is recorded and the stream
            // repositioned; [[Core.Serialization.Decoder.end]] turns it into an error
            // for a strict decode.
            if .wire >= 2 and .stream.position() != sec.afterFatSeek
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
    mtd beginStruct(structType: #null typeinfo, _structData: #null [*] u8)->bool fail
    {
        var sig = .stream.readNative'u32()
        if sig == Write.TagBinSignature.Raw
        {
            // If the stream contains a 'raw' representation of the struct, and the requested
            // type is not a POD, then we can load in place.
            if !Reflection.hasAttribute(structType, Serialization.Final) do
                fail SerializationError{"cannot convert a type from final to non final"}

            if .wire >= 2 do
                .beginSection2(.Raw, null)
            else do
                .beginSection1(.Raw, false)
            return false
        }

        // Skip array in case of an array to value conversion
        if sig == Write.TagBinSignature.UnRaw do
            sig = .stream.readNative'u32()

        // Read struct version
        if sig != Write.TagBinSignature.Version do
            fail SerializationError{"invalid version signature"}
        let streamVersion = .stream.readNative'u32()

        var plan: #null const *Plan
        if structType and Reflection.isStruct(structType) do
            plan = planFor(cast(const *Swag.TypeInfoStruct) structType!)

        // Deal with version
        var skipFat = false
        if plan and plan.hasVersion
        {
            // The stream version is more recent than the code that tries to read it.
            // Specific error, except if we want to try forward compatibility
            if !.options.tryForward and plan.version < streamVersion do
                fail InvalidVersion{wantedVersion: plan.version, foundVersion: streamVersion}

            // If this is the exact same version, then no need to read the fat, because everything
            // is supposed to be in the correct order
            if plan.version == streamVersion do
                skipFat = true
        }

        if .wire >= 2 do
            .beginSection2(.Unordered, plan)
        else do
            .beginSection1(.Unordered, skipFat)

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

        // Version 2 shaped positional path: the shape is the plan, so the field is the
        // next one in the stream and carries no inline metadata.
        if sec.positional
        {
            let shape = sec.shape!
            Debug.assert(sec.posIndex < shape.fields.count)
            let sf = shape.fields.buffer! + sec.posIndex
            Debug.assert(sf.crcName == getTypeValueCrc(val))
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

        // Version 2 shaped indexed path.
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

        // Version 0/1 sections and version 2 ad-hoc sections: elements carry their name
        // and type inline.
        let reqCrcName = getTypeValueCrc(val)
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
        var crcName = .stream.readNative'u32()

        // In positional mode a mismatch does not mean the stream is unreadable: the fat
        // was written anyway, so load it and look the field up by name instead of
        // failing the whole struct.
        if crcName != reqCrcName and sec.skipFat
        {
            .loadSectionFat(sec)
            sec.skipFat           = false
            .diag.recoveredFields += 1

            let ent = .findFieldRef(sec, val)
            if !ent.found
            {
                .elemStack.add({false, null})
                return false
            }

            if ent.seek >= .stream.length() do
                fail SerializationError{"field offset runs past the end of the stream", field: val}

            .stream.setPosition(ent.seek)
            crcName = .stream.readNative'u32()
        }

        // The looked-up field can still answer to an alias rather than its own name.
        if crcName != reqCrcName
        {
            var matchesAlias = false
            let aliases      = Reflection.attributes(val, Serialization.Alias)
            for al in aliases
            {
                let value = Reflection.attributeValue(al, "name")
                Debug.assert(value != null)
                if crcName == Hash.Crc32.compute(cast(string) value!)
                {
                    matchesAlias = true
                    break
                }
            }

            if !matchesAlias do
                fail SerializationError{"bad field name", field: val}
        }

        // Read the type signature.
        let crcType = .stream.readNative'u32()

        // Read value flags. A version 0 stream has none of them, and nothing in it is
        // compressed.
        var flags = Write.TagBinValueFlags.None
        if .hasValueFlags or .wire >= 2 do
            flags = .stream.readNative'Write.TagBinValueFlags()

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
    mtd beginSequence(typeElem: #null typeinfo, data: #null *u8, countElem: *u64)->bool fail
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
            if .wire >= 2 do
                countElem[] = .stream.readVarint()
            else do
                countElem[] = .stream.readNative'u64()

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
            if .wire >= 2 and sig == Write.TagBinSignature.Raw do
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

                // A version 2 stream also records the written byte length: a different
                // one means the raw element layout changed since the write.
                if .wire >= 2
                {
                    let byteLen = .stream.readVarint()
                    if byteLen != byteCount do
                        fail SerializationError{"raw element layout changed"}
                }

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

                if .wire >= 2
                {
                    let byteLen = .stream.readVarint()
                    if byteLen != streamCount * te.sizeof do
                        fail SerializationError{"raw element layout changed"}
                }

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
            var count:  u64
            if .wire >= 2 do
                count = .stream.readVarint()
            else do
                count = cast(u64) .stream.readNative'u32()

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

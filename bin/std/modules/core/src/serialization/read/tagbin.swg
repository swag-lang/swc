#global namespace Serialization
#global namespace Read
#global public

using Swag, Core.Errors

// Names the buffer type.
alias Buffer = Array'u8

// Highest ratio deflate can reach, one stored bit per output byte plus block
// overhead. A payload announcing more expansion than this is corrupt.
private const DeflateMaxExpansion = 1032'u64

/*
Binary serializer with forward/backward compatibility.
Changes that are supported from V to V+1 are :

* Add a new field. The new field will stay at the default value.
* Remove a field. It will just be ignored.
* Reorder of fields, as long as their name/type are the same.
* Rename a field with 'Serialization.Alias'.

Supported type changes are :

* Conversion from integer/float/rune/bool to integer/float/rune/bool.
* Change the size of a static array.
* Conversion from a static array to a dynamic `Core.Array`, and vice versa.
* Conversion from a single value to a static array or `Core.Array`, and vice versa.
* Rename a struct with 'Serialization.Alias'.
* Convert an existing complexe type to 'Serialization.Final'

Supported attributes are :

* 'Serialisation.Version'. If version is specified, then loading will not have versioning if versions are the same
* 'Serialization.Alias'. To rename a field or a struct type. Multiple aliases are supported.
* 'Serialization.Final'. The struct will be loaded/saved without versioning (faster and lower serialization size)
*/
struct TagBin
{
    ignoreElements: Array'String      // Element names skipped while decoding.
    options:        TagBinOptions     // Compatibility behavior.

    internal
    {
        streamVersion:     u32                                  // Version found in the stream.
        stream:            ByteStream                           // Input cursor.
        freeSections:      ArrayPtr'TagBinSection               // Reusable section objects.
        sections:          ArrayPtr'TagBinSection               // Active section stack.
        convertNextNative: #null const *Swag.TypeInfoNative     // Pending native conversion.
        convertValToArray: bool                                 // Whether the next scalar becomes an array.
        convertArrayToVal: bool                                 // Whether the next array becomes a scalar.
        outStack:          Array'{ buf: #null const [..] u8, seek: u64 }
        elemStack:         Array'{ compressed: bool, tmpBuf: #null *Buffer }
        tmpPool:           ArrayPtr'Buffer
    }
}

// Section information for tracking deserialization state within structured data.
struct TagBinSection
{
    // Map from field name CRC to stream position
    mapSeek:      HashTable'(u32, u64)     // Map seek associated with this value.
    afterFatSeek: u64                      // Stream position after the section's fat table
    version:      u32                      // Version number of this section
    kind:         SectionKind              // Type of section (ordered, unordered, or raw)
    skipFat:      bool                     // Whether to skip reading the fat table for this section
}

// Configuration options for controlling deserialization behavior.
struct TagBinOptions
{
    tryForward: bool     // Accept to try to read a newest version, otherwise error
}

private impl TagBin
{
    // Create a new section for the deserialization stack.
    // Returns a pointer to a section object, either reused from the free pool or newly allocated.
    mtd newSection()->*TagBinSection
    {
        if .freeSections.count
        {
            let ptr = notnull .freeSections.popBack()
            ptr.mapSeek.clear()
            ptr.version = 0
            .sections.add(ptr)
            return ptr
        }

        return .sections.addNew()
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
            let b = notnull .tmpPool.popBack()
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

    // Check if type conversion is possible between 'fromType' and 'toType'.
    // Sets up conversion flags and returns true if the conversion is supported.
    mtd canConvertType(toType, fromType: #null typeinfo)->bool
    {
        if toType == fromType do
            return true
        if !toType or !fromType do
            return false

        var fromStruct: #null const *Swag.TypeInfoStruct
        var toStruct:   #null const *Swag.TypeInfoStruct

        if Reflection.isStruct(fromType) do
            fromStruct = cast(#null const *Swag.TypeInfoStruct) fromType
        if Reflection.isStruct(toType) do
            toStruct = cast(#null const *Swag.TypeInfoStruct) toType

        // s64/float/bool/rune to s64/float/bool/rune
        if Reflection.isSimpleNative(toType) and Reflection.isSimpleNative(fromType)
        {
            .convertNextNative = cast(#null const *Swag.TypeInfoNative) fromType
            return true
        }

        if Reflection.isStaticArray(fromType)
        {
            let fromArr = cast(#null const *Swag.TypeInfoArray) fromType

            // Array to array, this is fine, we will deal with size change
            if Reflection.isStaticArray(toType)
            {
                let toArr = cast(#null const *Swag.TypeInfoArray) toType
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
                elif .canConvertType(toType, fromArr.pointedType)
                {
                    .convertArrayToVal = true
                    return true
                }
            }

            // Static array to single value
            elif .canConvertType(toType, fromArr.pointedType)
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
                if Reflection.isStaticArray(toType)
                {
                    let toArr = cast(#null const *Swag.TypeInfoArray) toType
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
                elif .canConvertType(toType, Reflection.dynamicArrayElementType(fromStruct))
                {
                    .convertArrayToVal = true
                    return true
                }
            }
        }

        if Reflection.isStaticArray(toType)
        {
            let toArr = cast(#null const *Swag.TypeInfoArray) toType

            // Conversion from simple value to array
            if .canConvertType(toArr.pointedType, fromType)
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
                if (!fromStruct or !Reflection.isDynamicArray(fromStruct)) and .canConvertType(Reflection.dynamicArrayElementType(toStruct), fromType)
                {
                    .convertValToArray = true
                    return true
                }
            }

            // Struct to struct...
            elif fromStruct and !Reflection.isDynamicArray(fromStruct)
            {
                // Alias
                let aliases = Reflection.attributes(toType, Serialization.Alias)
                for al in aliases
                {
                    let value = Reflection.attributeValue(al, "name")
                    if cast(#null string) value == fromType.name
                    {
                        return true
                    }
                }
            }
        }

        return false
    }
}

impl TagBin
{
    // Performs the peek struct field crcs operation.
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

        let fatSeek  = .stream.readNative'u64()
        var fatCount = .stream.readNative'u64()

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
    }

    // Begin reading the root container of the serialized data.
    // Validates the root signature to ensure the stream contains valid serialized data.
    mtd beginRoot() fail
    {
        let sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Root do
            fail SerializationError{"invalid root signature"}
        .streamVersion = .stream.readNative'u32()
    }

    // Finish reading the root container.
    // Currently no cleanup is required, but this maintains the symmetric begin/end API.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endRoot() fail {}

    // Begin reading a new section with the specified 'kind'.
    // Optionally skips reading the fat table if 'skipFat' is true for performance optimization.
    mtd beginSection(kind: SectionKind, skipFat = false) fail
    {
        let sec = .newSection()
        sec.kind    = kind
        sec.skipFat = skipFat
        if kind != .Unordered do
            return

        // Read fat position and count
        var sig = .stream.readNative'u32()
        if sig != Write.TagBinSignature.Fat do
            fail SerializationError{"invalid fat signature"}
        let fatSeek  = .stream.readNative'u64()
        var fatCount = .stream.readNative'u64()

        // We have a fat, but we do not want it !
        if skipFat
        {
            sec.afterFatSeek = fatSeek
            sec.afterFatSeek += #sizeof(u32)

            // Signature
            sec.afterFatSeek += fatCount * #sizeof(u32)

            // Crc
            sec.afterFatSeek += fatCount * #sizeof(u64)
        }
        else
        {
            // Seek to fat and read it
            .stream.setPosition(fatSeek)
            sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Fat do
                fail SerializationError{"invalid fat signature"}

            while fatCount
            {
                let crc  = .stream.readNative'u32()
                let seek = .stream.readNative'u64()
                sec.mapSeek.add(crc, seek)
                fatCount -= 1
            }

            sec.afterFatSeek = .stream.position()
        }
    }

    // Finish reading the current section.
    // Updates the stream position and releases the section back to the pool.
    mtd endSection() fail
    {
        let sec = notnull .sections.back()

        // Fat is after the datas. We need to be sure to point
        // to what's next, except in raw mode where we are already at
        // the correct offset
        if sec.kind != .Raw do
            .stream.setPosition(sec.afterFatSeek)

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

            .beginSection(.Raw)
        }
        else
        {
            // Skip array in case of an array to value conversion
            if sig == Write.TagBinSignature.UnRaw do
                sig = .stream.readNative'u32()

            // Read struct version
            if sig != Write.TagBinSignature.Version do
                fail SerializationError{"invalid version signature"}
            let streamVersion = .stream.readNative'u32()

            // Deal with version
            var skipFat       = false
            let structVersion = Reflection.attributeValue(structType, Serialization.Version, "v")
            if structVersion != null
            {
                let curVersion = cast(u32) structVersion

                // The stream version is more recent than the code that tries to read it.
                // Specific error, except if we want to try forward compatibility
                if !.options.tryForward and curVersion < streamVersion do
                    fail InvalidVersion{wantedVersion: curVersion, foundVersion: streamVersion}

                // If this is the exact same version, then no need to read the fat, because everything
                // is supposed to be in the correct order
                if curVersion == streamVersion do
                    skipFat = true
            }

            .beginSection(.Unordered, skipFat)
        }

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

        var reqCrcName = getTypeValueCrc(val)
        let sec        = notnull .sections.back()

        // If section is raw, then we just have values without versionning
        if sec.kind == .Raw
        {
            .elemStack.add({false, null})
            return true
        }

        // If section is unordered, then we have a fat where each value has a descriptor
        if sec.kind == .Unordered and !sec.skipFat
        {
            var ent = sec.mapSeek.tryFind(reqCrcName)

            // If ent is null, then we are requesting a field that does not exist
            // in the stream
            if !ent
            {
                // So check for aliases
                let aliases = Reflection.attributes(val, Serialization.Alias)
                for al in aliases
                {
                    let value = Reflection.attributeValue(al, "name")
                    Debug.assert(value != null)
                    reqCrcName = Hash.Crc32.compute(notnull cast(#null string) value)
                    ent        = sec.mapSeek.tryFind(reqCrcName)
                    if ent do
                        break
                }
            }

            // The requested field is not there, just ignore it
            if !ent
            {
                .elemStack.add({false, null})
                return false
            }

            // Otherwise we seek to the field in the stream
            .stream.setPosition(ent.value)
        }

        // Read the name signature.
        let crcName = .stream.readNative'u32()

        // We should have a matching crc
        if crcName != reqCrcName do
            fail SerializationError{"bad field name", field: val}

        // Read the type signature.
        let crcType = .stream.readNative'u32()

        // Read value flags
        let flags = .stream.readNative'Write.TagBinValueFlags()
        if flags.has(.Compressed)
        {
            let uncompressedSize = .stream.readNative'u64()
            let compressedSize   = .stream.readNative'u64()

            // Both sizes come from the stream, so a truncated or foreign payload can
            // name any value at all. The compressed run must fit in what is left,
            // otherwise the element is not readable.
            if compressedSize > .stream.length() - .stream.seek do
                fail SerializationError{"compressed payload runs past the end of the stream", field: val}

            if uncompressedSize == compressedSize do
                .elemStack.add({false, null})
            else
            {
                // push parent buffer on stack and switch current output
                let decompressedBuffer = .acquireTmpBuf()

                // The announced size is only a sizing hint: 'decompress' grows the
                // buffer on its own and rejects a malformed payload. Honour it only
                // while it stays within what deflate can produce from this input, so
                // a corrupt header cannot ask for an arbitrary allocation.
                if uncompressedSize <= compressedSize * DeflateMaxExpansion do
                    decompressedBuffer.reserve(uncompressedSize)

                // Here uncompress to 'tmp'
                var decompressor: Core.Compress.Inflate
                decompressor.decompress(decompressedBuffer, notnull .stream.remainingBytes())

                // track this element context
                .elemStack.add({true, decompressedBuffer})

                .outStack.add({.stream.readBuffer, .stream.seek + compressedSize})
                .stream.readBuffer = decompressedBuffer.toSlice()
                .stream.seek       = 0
            }
        }
        else
        {
            .elemStack.add({false, null})
        }

        // If they do not match, we will try to convert the type from the one in the
        // stream to the requested one
        if crcType != getTypeInfoCrc(val.pointedType)
        {
            // We try to find a registered type with the crc from the stream.
            let streamType = Reflection.typeFromCrc(crcType)

            // Older streams can contain type CRCs from a previous hash scheme.
            // If the field name matched but the type CRC is unknown, read with
            // the requested type and let the payload reader validate the bytes.
            if !streamType do
                return true

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
                discard .stream.readNative'u64()

                let arraySig = .stream.readNative'u32()
                if arraySig != Write.TagBinSignature.Raw and arraySig != Write.TagBinSignature.UnRaw do
                    fail SerializationError{"stream is corrupted", field: val}
            }
        }

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
        .releaseTmpBuf(notnull ctx.tmpBuf)
    }

    // Begin reading a value within the current context.
    // Currently no special processing is required, but this maintains the symmetric API.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd beginValue() fail {}

    // Finish reading a value within the current context.
    // Currently no cleanup is required, but this maintains the symmetric API.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endValue() fail {}

    // Begin reading a sequence (array) of elements of type 'typeElem'.
    // Updates 'countElem' with the actual number of elements and returns true for bulk reading optimization.
    mtd beginSequence(typeElem: #null typeinfo, data: #null *u8, countElem: *u64)->bool fail
    {
        let orgCount = dref countElem
        if .convertValToArray
        {
            dref countElem = 1
        }
        else
        {
            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Sequence do
                fail SerializationError{"stream is corrupted"}

            // 0 for a dynamic array, > 0 for a static array
            dref countElem = .stream.readNative'u64()
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

                let vt       = notnull valueType
                let elemSize = vt.sizeof
                let bufArr   = notnull cast(#null *Array'u8) data
                bufArr.count = dref countElem
                bufArr.reserve(bufArr.count * elemSize)
                bufArr.capacity = bufArr.count
                .stream.readBytes(bufArr.buffer, bufArr.count * elemSize)
                return true
            }
        }

        // Static array
        else
        {
            dref countElem = Math.min(orgCount, dref countElem)

            let sig = .stream.readNative'u32()
            if sig != Write.TagBinSignature.Raw and sig != Write.TagBinSignature.UnRaw do
                fail SerializationError{"stream is corrupted"}

            // Honor the stream's layout signature (see the dynamic-array case above).
            if sig == Write.TagBinSignature.Raw
            {
                if !Reflection.isPod(typeElem) do
                    fail SerializationError{"cannot load a raw array into a non-pod element type"}

                let te = notnull typeElem
                .stream.readBytes(data, dref countElem * te.sizeof)
                return true
            }
        }

        return false
    }

    // Finish reading the current sequence.
    // Currently no cleanup is required, but this maintains the symmetric API.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endSequence() fail {}

    // Advance to the next element in the current sequence.
    // Decrements 'countElem' and returns false when no more elements remain.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd toNextSequenceElement(countElem: *u64)->bool
    {
        if dref countElem == 0 do
            return false
        dref countElem -= 1
        return true
    }

    // Check if this serializer uses textual representation.
    // Always returns false since this is a binary serializer.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd isTextual()->bool
    {
        return false
    }

    // Get the version number of the current section.
    // Returns 0 if no sections are active, otherwise returns the version of the most recent section.
    mtd version()->u32
    {
        if .sections.isEmpty() do
            return 0
        let sec = notnull .sections.back()
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
            let count = cast(u64) .stream.readNative'u32()
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

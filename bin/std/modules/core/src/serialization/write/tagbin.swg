#global namespace Serialization
#global namespace Write
#global public

using Swag

// Current tagbin version.
const TagBinVersion = 0xFAFAFAFA

// Signatures used to tag different sections and elements in the binary serialization format
enum TagBinSignature: u32
{
    Root     = 0xC0DE0000     // Root element of the serialization structure
    Fat      = 0xC0DE0001     // FAT table identifier for unordered sections
    Sequence = 0xC0DE0002     // Start of a sequence (array or list)
    Version  = 0xC0DE0003     // Indicates that a version number is present
    Raw      = 0xC0DE0004     // Indicates raw POD data with no structure
    UnRaw    = 0xC0DE0005     // Indicates non-POD structured data
}

// Additional signature for each value, stored after the value description (crcs)
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

// Internal state for a binary serialization section
struct TagBinSection
{
    startSeek: ConcatBufferPosition                      // Position in the output buffer where the section starts.
    mapSeek:   HashTable'(u32, ConcatBufferPosition)     // Maps CRC keys to their position in the output buffer.
    kind:      SectionKind                               // Type of section (e.g., Raw or Unordered)
}

// Binary writer for serialized data with support for structured and raw output
#[Swag.Opaque]
struct TagBin
{
    compressionFlags:    Core.Compress.Deflate.CompressionFlags    = .Zero          // Compression flags associated with this value.
    compressionLevel:    Core.Compress.Deflate.CompressionLevel    = .BestSpeed     // Compression level associated with this value.
    compressionStrategy: Core.Compress.Deflate.CompressionStrategy = .Default       // Compression strategy associated with this value.

    // Writing state: the compressor, the section stack and the buffer pools it recycles.
    private
    {
        compressor:   Core.Compress.Deflate                                       // Compressor used for compressed sections.
        output:       #null *ConcatBuffer                                         // Output buffer where data is written.
        freeSections: ArrayPtr'TagBinSection                                      // Pool of reusable section structures.
        sections:     ArrayPtr'TagBinSection                                      // Stack of currently active sections.
        outStack:     Array'(#null *ConcatBuffer)                                 // Output buffers of the enclosing sections.
        elemStack:    Array'{ compressed: bool, tmpBuf: #null *ConcatBuffer }     // Element stack.
        freeTmpBuf:   ArrayPtr'ConcatBuffer                                       // Pool of reusable scratch buffers.
    }
}

private impl TagBin
{
    // Creates or reuses a new section for writing
    mtd newSection()->*TagBinSection
    {
        if .freeSections.count
        {
            let ptr = notnull .freeSections.popBack()
            ptr.mapSeek.clear()
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
            let b = notnull .freeTmpBuf.popBack()
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
}

impl TagBin
{
    // Tagbin is a binary format.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd isTextual()->bool
    {
        return false
    }

    // Begins writing to a specified output buffer
    mtd startWrite(buf: *ConcatBuffer)
    {
        .output = buf
        .outStack.clear()
        .elemStack.clear()
        .sections.clear()
    }

    // Begins the root section of the serialization structure
    mtd beginRoot()
    {
        let output = notnull .output
        output.addNative(TagBinSignature.Root)
        output.addNative(TagBinVersion)
    }

    // Ends the root section and asserts that all subsections have been closed
    mtd endRoot()
    {
        Debug.assert(.sections.isEmpty())
    }

    // Begins a new section of the specified kind
    mtd beginSection(kind: SectionKind)
    {
        let sec = .newSection()
        sec.kind = kind

        if sec.kind == .Unordered
        {
            let output = notnull .output
            output.addNative(TagBinSignature.Fat)
            sec.startSeek = output.position()
            output.addNative(0'u64)     // Will store the fat offset here
            output.addNative(0'u64)     // Will store the fat count here
        }
    }

    // Ends the current section and writes out any required metadata
    mtd endSection()
    {
        let sec = notnull .sections.back()

        if sec.kind == .Unordered
        {
            // Patch fat table seek and count
            let output  = notnull .output
            let curSeek = output.position()
            output.setPosition(sec.startSeek)
            output.addNative(ConcatBuffer.offsetOf(curSeek))
            output.addNative(sec.mapSeek.count)
            output.setPosition(curSeek)

            // Write fat table
            output.addNative(TagBinSignature.Fat)
            for k, [v] in sec.mapSeek
            {
                output.addNative(k)                            // Crc
                output.addNative(ConcatBuffer.offsetOf(v))     // Linear seek inside the buffer
            }
        }

        .releaseSection()
    }

    // Begins a new struct, writing versioning and section metadata
    mtd beginStruct(structType: #null typeinfo, _structData: #null const [*] u8)->bool
    {
        let {pod, ?} = isPodFinal(structType)
        let output   = notnull .output
        if pod
        {
            output.addNative(TagBinSignature.Raw)
            .beginSection(.Raw)
        }
        else
        {
            // Struct version
            output.addNative(TagBinSignature.Version)
            let version = Reflection.attributeValue(structType, Serialization.Version, "v")
            if version == null do
                output.addNative(0'u32)
            else do
                output.addNative(cast(u32) version)

            // Start unordered section
            .beginSection(.Unordered)
        }

        return false
    }

    // Ends the current struct section
    mtd endStruct()
    {
        .endSection()
    }

    // Begins a new element inside the current section and records its metadata
    mtd beginElement(val: TypeValue)
    {
        Debug.assert(!.sections.isEmpty(), "Missing a previous 'beginSection' call")

        // If section is raw, then we just have values without versioning
        let sec = notnull .sections.back()
        if sec.kind == .Raw do
            return

        // Register the current seek for the fat generation
        let output = notnull .output
        if sec.kind == .Unordered
        {
            let crcName = getTypeValueCrc(val)
            Debug.assert(!sec.mapSeek.contains(crcName))
            sec.mapSeek.add(crcName, output.position())
        }

        // Write element signature
        output.addNative(getTypeValueCrc(val))
        output.addNative(getTypeInfoCrc(val.pointedType))

        var valSig: TagBinValueFlags = .None
        if Reflection.hasAttribute(val, Compress) or Reflection.hasAttribute(val.pointedType, Compress) do
            valSig.add(TagBinValueFlags.Compressed)
        output.addNative(valSig)

        // If compressed, push a new ConcatBuffer that will collect all payload for this element
        if valSig.has(.Compressed)
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

    // Ends the current element (stubbed out)
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endElement(val: TypeValue)
    {
        // If section is raw, then we just have values without versioning
        let sec = notnull .sections.back()
        if sec.kind == .Raw do
            return

        Debug.assert(!.elemStack.isEmpty())
        let ctx = .elemStack.popBack()
        if !ctx.compressed do
            return

        // We must have a previous buffer to append into
        Debug.assert(!.outStack.isEmpty())
        let parentOut = notnull .outStack.popBack()

        // Gather uncompressed bytes
        let tmpBuf     = notnull ctx.tmpBuf
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
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd beginValue() {}

    // Ends a value (stubbed out)
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endValue() {}

    // Begins a sequence and determines if elements can be written in bulk as raw data
    mtd beginSequence(typeElem: #null typeinfo, data: #null const *void, countElem: u64)->bool
    {
        let output = notnull .output
        output.addNative(TagBinSignature.Sequence)
        output.addNative(countElem)

        // Dynamic array of raw serializable types
        // Just write them in one batch
        if Reflection.isDynamicArray(typeElem)
        {
            let valueType     = Reflection.dynamicArrayElementType(typeElem)
            let {raw, sizeof} = isPodFinal(valueType)

            if raw
            {
                output.addNative(TagBinSignature.Raw)
                if !data do
                    return true
                let bufArr = cast(const *Array'u8) data
                output.addBytes(@mkslice(bufArr.buffer, countElem * sizeof))
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
                if !data do
                    return true
                output.addBytes(@mkslice(cast(const [*] u8) data, countElem * sizeof))
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
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endSequence() {}

    /////////////////////////////////
    // VALUES
    /////////////////////////////////

    // Writes a native value to the output buffer, with special handling for strings
    mtd(NT) writeNative(value: NT)
    {
        let output = notnull .output
        #static if Reflection.isString(NT)
        {
            output.addNative(cast(u32) @countof(value))
            output.addBytes(value)
        }
        else
        {
            output.addNative(value)
        }
    }
}

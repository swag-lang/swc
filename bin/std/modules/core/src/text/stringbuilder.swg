#global public
#global namespace StrConv

// Builds text piece by piece in a [[Core.ConcatBuffer]], without moving what was appended before.
struct StringBuilder
{
    public buffer: ConcatBuffer     // Storage of the text built so far.
}

impl StringBuilder
{
    // Empties the builder while keeping its storage for reuse.
    mtd clear()
    {
        .buffer.clear()
    }

    // Returns the number of bytes appended so far.
    mtd const count()->u64 => .buffer.count()

    // Sets the minimum size, in bytes, of the buckets allocated from now on.
    mtd setBucketSize(size: u64)
    {
        .buffer.setBucketSize(size)
    }

    // Appends `value`.
    mtd appendString(value: string?)
    {
        .buffer.addBytes(value)
    }

    // Appends the platform line ending, [[Core.Env.LineEnding]].
    mtd appendEOL()
    {
        .buffer.addBytes(Env.LineEnding)
    }

    // Appends the UTF-8 encoding of `value`.
    mtd appendRune(value: rune)
    {
        convertRune(&.buffer, value)
    }

    // Appends the text of `value`, formatted by `strFormat` as [[Core.StrConv.convertAny]] does.
    mtd appendAny(value: const any?, strFormat: string? = null)
    {
        let convFmt: StrConv.ConvertFormat
        convertAny(&.buffer, value, convFmt, strFormat)
    }

    // Appends `fmt` formatted with `values`, following the rules of [[Core.Format.toString]].
    mtd appendFormat(fmt: string, values: ...)
    {
        Format.append(&.buffer, fmt, values)
    }

    // Writes a zero byte after the content without counting it, so the storage is zero-terminated.
    mtd zeroTerminate()
    {
        let seek = .buffer.position()
        .buffer.addNative(0'u8)
        .buffer.truncate(seek)
    }

    // Returns a new [[Core.String]] holding a copy of the content.
    mtd const toString()->String => .buffer.toString()

    // Returns the content as a [[Core.String]], taking over the storage when it is a single bucket.
    //
    // See [[Core.ConcatBuffer.moveToString]] for what remains in the builder.
    mtd moveToString()->String => .buffer.moveToString()
}

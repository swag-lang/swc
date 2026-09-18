#global public
#global namespace Compress

// Reads little-endian bit fields from a borrowed byte slice.
//
// Bits are consumed least significant first, as in Deflate. The source slice must remain
// valid until the stream is reset or discarded.
struct BitStream
{
    internal
    {
        stream:     const [..] u8?     // Borrowed input bytes.
        curByte:    u64                // Index of the next byte to load into 'codeBuffer'.
        codeBuffer: u64                // Buffered low-order bits.
        numBits:    u8                 // Number of buffered bits.
        eof:        bool               // Whether refill reached the end.
    }
}

impl BitStream
{
    // Resets the stream over `buffer`, which it borrows until the next reset.
    mtd reset(buffer: const [..] u8)
    {
        Swag.init(me, 1)
        .stream = buffer
    }

    // Returns a borrowed pointer to the next source byte not yet loaded into the bit buffer.
    #[Swag.Inline]
    mtd currentPointer() => (.stream).buffer + .curByte

    // Returns the source size in bytes.
    #[Swag.Inline]
    mtd size() => (.stream).count

    // Returns the index of the next source byte not yet loaded into the bit buffer.
    #[Swag.Inline]
    mtd bytePosition()->u64 => .curByte

    // Returns whether a refill reached the end of the source.
    #[Swag.Inline]
    mtd isEof()->bool => .eof

    // Skips `count` whole source bytes; the bit buffer must be empty.
    mtd advanceBytes(count: u64)
    {
        Swag.assert(.numBits == 0)
        Swag.assert(count <= .size() - .curByte)
        .curByte += count
        .eof     = .curByte == .size()
    }

    // Refills the bit buffer until it holds more than `width` bits, unless the source ends first.
    mtd refill(width = 24'u8)
    {
        // Fast path: a single unaligned 64-bit load refills the buffer to at least
        // 56 bits at once, as long as 8 bytes remain so the load stays in bounds.
        // This avoids the per-byte loop for the bulk of the stream.
        if .numBits <= 56 and .curByte + 8 <= (.stream).count
        {
            let chunk = (cast(const *u64) .currentPointer()!)[]
            .codeBuffer |= chunk << #wrap .numBits
            let nbytes = (64 - cast(u64) .numBits) >> 3
            .curByte += nbytes
            .numBits += cast(u8) (nbytes << 3)

            // Zero any partial high byte brought in above 'numBits' so the invariant
            // "bits at or above numBits are zero" holds (skip when the buffer is full).
            if .numBits != 64 do
                .codeBuffer &= (1'u64 << .numBits) - 1
            return
        }

        // Slow path: byte-by-byte, used near the end of the stream.
        while .numBits <= width
        {
            // Detect and reset broken state (if buffer was empty and numBits was max)
            if .codeBuffer == 0 and .numBits == cast #bit (u8) -1 do
                .numBits = 0

            // If buffer is already full, prevent overflow
            if .codeBuffer >= 1'u64 << .numBits
            {
                .numBits = 255
                return
            }

            // Stop if we reached end of stream
            if .curByte >= (.stream).count
            {
                .eof = true
                return
            }

            // Read next byte and shift it into the buffer
            let stream = .stream!
            let c      = stream[.curByte]
            .curByte    += 1
            .codeBuffer |= cast(u64) c << .numBits
            .numBits    += 8
        }
    }

    // Returns the next `width` bits without consuming them, refilling the bit buffer when needed.
    #[Swag.Inline]
    mtd peekBits(width: u8)->u32
    {
        if .numBits < width do
            .refill()
        return cast(u32) (.codeBuffer & ((1'u64 << width) - 1))
    }

    // Returns the next `width` bits without consuming them; the bit buffer must already hold them.
    mtd peekBitsUnchecked(width: u8)->u32
    {
        Swag.assert(.numBits >= width)
        return cast(u32) (.codeBuffer & ((1'u64 << width) - 1))
    }

    // Reads and consumes the next `width` bits, refilling the bit buffer when needed.
    #[Swag.Inline]
    mtd readBits(width: u8)->u32
    {
        let k = .peekBits(width)
        .consumeBits(width)
        return k
    }

    // Reads and consumes the next `width` bits, which the bit buffer must already hold.
    mtd readBitsUnchecked(width: u8)->u32
    {
        let k = .peekBitsUnchecked(width)
        .consumeBits(width)
        return k
    }

    // Discards the next `width` buffered bits.
    #[Swag.Inline]
    mtd consumeBits(width: u8)
    {
        .codeBuffer >>= width
        .numBits    -= #wrap width
    }

    // Discards the buffered bits up to the next byte boundary.
    #[Swag.Inline]
    mtd discardToNextByte()
    {
        .consumeBits(cast(u8) .numBits & 7)
    }

    // Gives the whole bytes held in the bit buffer back to the source.
    //
    // The buffer must hold a whole number of bytes. Reading then resumes at the first byte
    // not yet consumed, which [[Core.Compress.BitStream.currentPointer]] addresses.
    mtd revert()
    {
        Swag.assert(not (.numBits & 7))     // Must be aligned
        .curByte    -= .numBits / 8
        .numBits    = 0
        .codeBuffer = 0
    }

    // Reads and consumes the next `count` bytes into `dest`.
    mtd readBytes(count: u8, dest: [*] u8)
    {
        for i in count
        {
            dest[i] = cast(u8) .peekBits(8)
            .consumeBits(8)
        }
    }

    // Reads and consumes the next four bytes into `dest`, in stream order.
    mtd read32(dest: [*] u8)
    {
        dest[0] = cast(u8) .peekBits(8)
        .consumeBits(8)
        dest[1] = cast(u8) .peekBits(8)
        .consumeBits(8)
        dest[2] = cast(u8) .peekBits(8)
        .consumeBits(8)
        dest[3] = cast(u8) .peekBits(8)
        .consumeBits(8)
    }

    // Reads and consumes the next four bytes as a big-endian 32-bit value stored at `dest` in native byte order.
    mtd read32Be(dest: [*] u8)
    {
        #static if BIG_ENDIAN do
            .read32(dest)
        else
        {
            dest[3] = cast(u8) .peekBits(8)
            .consumeBits(8)
            dest[2] = cast(u8) .peekBits(8)
            .consumeBits(8)
            dest[1] = cast(u8) .peekBits(8)
            .consumeBits(8)
            dest[0] = cast(u8) .peekBits(8)
            .consumeBits(8)
        }
    }
}

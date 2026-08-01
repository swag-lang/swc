#global public
#global namespace Compress

// Reads little-endian bit fields from a borrowed byte slice.
//
// The source slice must remain valid until the stream is reset or discarded.
struct BitStream
{
    internal
    {
        stream:     #null const [..] u8     // Borrowed input bytes.
        curByte:    u64                     // Current byte index.
        codeBuffer: u64                     // Buffered low-order bits.
        numBits:    u8                      // Number of buffered bits.
        eof:        bool                    // Whether refill reached the end.
    }
}

impl BitStream
{
    // Resets the stream over `buffer`.
    mtd reset(buffer: const [..] u8)
    {
        @init(me, 1)
        .stream = buffer
    }

    // Returns a borrowed pointer to the first source byte.
    #[Swag.Inline]
    internal mtd startPointer() => @dataof(.stream)

    // Returns a borrowed pointer to the current source byte.
    #[Swag.Inline]
    mtd currentPointer() => @dataof(.stream) + .curByte

    // Returns the source size in bytes.
    #[Swag.Inline]
    mtd size() => @countof(.stream)

    // Returns the current source byte index.
    #[Swag.Inline]
    mtd bytePosition()->u64 => .curByte

    // Returns whether a refill reached the end of the source.
    #[Swag.Inline]
    mtd isEof()->bool => .eof

    // Advances by whole source bytes while no bits are buffered.
    mtd advanceBytes(count: u64)
    {
        Debug.assert(.numBits == 0)
        Debug.assert(count <= .size() - .curByte)
        .curByte += count
        .eof = .curByte == .size()
    }

    // Refills the bit buffer until at least 'width' bits are available
    mtd refill(width = 24'u8)
    {
        // Fast path: a single unaligned 64-bit load refills the buffer to at least
        // 56 bits at once, as long as 8 bytes remain so the load stays in bounds.
        // This avoids the per-byte loop for the bulk of the stream.
        if .numBits <= 56 and .curByte + 8 <= @countof(.stream)
        {
            let chunk = dref notnull cast(#null const *u64) .currentPointer()
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
            if .curByte >= @countof(.stream)
            {
                .eof = true
                return
            }

            // Read next byte and shift it into the buffer
            let stream = notnull .stream
            let c      = stream[.curByte]
            .curByte    += 1
            .codeBuffer |= cast(u64) c << .numBits
            .numBits    += 8
        }
    }

    // Returns next 'width' bits without consuming them (refills if needed)
    #[Swag.Inline]
    mtd peekBits(width: u8)->u32
    {
        if .numBits < width do
            .refill()
        return cast(u32) (.codeBuffer & ((1'u64 << width) - 1))
    }

    // Like peekBits, but assumes enough bits are already available
    mtd peekBitsUnchecked(width: u8)->u32
    {
        Debug.assert(.numBits >= width)
        return cast(u32) (.codeBuffer & ((1'u64 << width) - 1))
    }

    // Reads and consumes 'width' bits from the buffer
    #[Swag.Inline]
    mtd readBits(width: u8)->u32
    {
        let k = .peekBits(width)
        .consumeBits(width)
        return k
    }

    // Reads and consumes 'width' bits without checking buffer availability
    mtd readBitsUnchecked(width: u8)->u32
    {
        let k = .peekBitsUnchecked(width)
        .consumeBits(width)
        return k
    }

    // Consumes 'width' bits from the buffer (advances the bit position)
    #[Swag.Inline]
    mtd consumeBits(width: u8)
    {
        .codeBuffer >>= width
        .numBits    -= #wrap width
    }

    // Discards bits to align to the next byte boundary
    #[Swag.Inline]
    mtd discardToNextByte()
    {
        .consumeBits(cast(u8) .numBits & 7)
    }

    // Reverts stream to last byte-aligned state (undo partial read)
    mtd revert()
    {
        Debug.assert(!(.numBits & 7))     // Must be aligned
        .curByte    -= .numBits / 8
        .numBits    = 0
        .codeBuffer = 0
    }

    // Peeks 'width' bytes into 'dest', consuming bits after each byte
    mtd peekBytes(width: u8, dest: [*] u8)
    {
        // Could be optimized further
        for [i] in width
        {
            dest[i] = cast(u8) .peekBits(8)
            .consumeBits(8)
        }
    }

    // Peeks 4 bytes (little-endian) into 'dest'
    mtd peek32(dest: [*] u8)
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

    // Peeks 4 bytes (big-endian) into 'dest', auto-switches based on platform
    mtd peek32Be(dest: [*] u8)
    {
        #static if BIG_ENDIAN do
            peek32(dest)     // Already big-endian
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

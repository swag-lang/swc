#global namespace Pdf

using Core, Core.Errors

// The Group 3 and Group 4 facsimile filter, decoded here like every other PDF stream filter.
//
// The encoding is a run-length code over a bilevel scan: each line is written either on its own
// or as a set of differences from the line above it, and both forms share the run tables. This
// filter is what a scanned page arrives as, so a document carrying one is unreadable without it
// rather than merely missing a picture.

// What a CCITT stream's `/DecodeParms` dictionary says about the encoding.
//
// `k` selects the form: negative is pure two-dimensional (Group 4), zero is pure one-dimensional
// (Group 3), and positive is the mixed form where every line names the one it uses.
struct CcittParameters
{
    k:         s64
    columns:   s64 = 1728
    rows:      s64
    blackIs1:  bool
    byteAlign: bool
}

// One entry of a run-length code table: `bits` wide, spelling `run` pixels of its own colour.
private struct CcittCode
{
    bits: u8
    code: u16
    run:  u16
}

// Widest code of either table. Every lookup peeks exactly this many bits.
private const CcittLookupBits = 13'u32
private const CcittLookupSize = 1'u64 << CcittLookupBits

// The widest scan line the filter accepts. Anything larger is a damaged dictionary, not a page.
private const CcittMaxColumns = 1_000_000's64

// End of line: eleven zeroes and a one. No run code shares its prefix, so a line boundary is
// recognized before a run is read rather than discovered by failing to decode one.
private const CcittEndOfLine     = 1'u32
private const CcittEndOfLineBits = 12'u32

private const CcittWhiteCodes: [104] CcittCode = [{8, 0b00110101, 0}, {6, 0b000111, 1}, {4, 0b0111, 2}, {4, 0b1000, 3}, {4, 0b1011, 4}, {4, 0b1100, 5}, {4, 0b1110, 6}, {4, 0b1111, 7}, {5, 0b10011, 8}, {5, 0b10100, 9}, {5, 0b00111, 10}, {5, 0b01000, 11}, {6, 0b001000, 12}, {6, 0b000011, 13}, {6, 0b110100, 14}, {6, 0b110101, 15}, {6, 0b101010, 16}, {6, 0b101011, 17}, {7, 0b0100111, 18}, {7, 0b0001100, 19}, {7, 0b0001000, 20}, {7, 0b0010111, 21}, {7, 0b0000011, 22}, {7, 0b0000100, 23}, {7, 0b0101000, 24}, {7, 0b0101011, 25}, {7, 0b0010011, 26}, {7, 0b0100100, 27}, {7, 0b0011000, 28}, {8, 0b00000010, 29}, {8, 0b00000011, 30}, {8, 0b00011010, 31}, {8, 0b00011011, 32}, {8, 0b00010010, 33}, {8, 0b00010011, 34}, {8, 0b00010100, 35}, {8, 0b00010101, 36}, {8, 0b00010110, 37}, {8, 0b00010111, 38}, {8, 0b00101000, 39}, {8, 0b00101001, 40}, {8, 0b00101010, 41}, {8, 0b00101011, 42}, {8, 0b00101100, 43}, {8, 0b00101101, 44}, {8, 0b00000100, 45}, {8, 0b00000101, 46}, {8, 0b00001010, 47}, {8, 0b00001011, 48}, {8, 0b01010010, 49}, {8, 0b01010011, 50}, {8, 0b01010100, 51}, {8, 0b01010101, 52}, {8, 0b00100100, 53}, {8, 0b00100101, 54}, {8, 0b01011000, 55}, {8, 0b01011001, 56}, {8, 0b01011010, 57}, {8, 0b01011011, 58}, {8, 0b01001010, 59}, {8, 0b01001011, 60}, {8, 0b00110010, 61}, {8, 0b00110011, 62}, {8, 0b00110100, 63}, {5, 0b11011, 64}, {5, 0b10010, 128}, {6, 0b010111, 192}, {7, 0b0110111, 256}, {8, 0b00110110, 320}, {8, 0b00110111, 384}, {8, 0b01100100, 448}, {8, 0b01100101, 512}, {8, 0b01101000, 576}, {8, 0b01100111, 640}, {9, 0b011001100, 704}, {9, 0b011001101, 768}, {9, 0b011010010, 832}, {9, 0b011010011, 896}, {9, 0b011010100, 960}, {9, 0b011010101, 1024}, {9, 0b011010110, 1088}, {9, 0b011010111, 1152}, {9, 0b011011000, 1216}, {9, 0b011011001, 1280}, {9, 0b011011010, 1344}, {9, 0b011011011, 1408}, {9, 0b010011000, 1472}, {9, 0b010011001, 1536}, {9, 0b010011010, 1600}, {6, 0b011000, 1664}, {9, 0b010011011, 1728}, {11, 0b00000001000, 1792}, {11, 0b00000001100, 1856}, {11, 0b00000001101, 1920}, {12, 0b000000010010, 1984}, {12, 0b000000010011, 2048}, {12, 0b000000010100, 2112}, {12, 0b000000010101, 2176}, {12, 0b000000010110, 2240}, {12, 0b000000010111, 2304}, {12, 0b000000011100, 2368}, {12, 0b000000011101, 2432}, {12, 0b000000011110, 2496}, {12, 0b000000011111, 2560}]

private const CcittBlackCodes: [104] CcittCode = [{10, 0b0000110111, 0}, {3, 0b010, 1}, {2, 0b11, 2}, {2, 0b10, 3}, {3, 0b011, 4}, {4, 0b0011, 5}, {4, 0b0010, 6}, {5, 0b00011, 7}, {6, 0b000101, 8}, {6, 0b000100, 9}, {7, 0b0000100, 10}, {7, 0b0000101, 11}, {7, 0b0000111, 12}, {8, 0b00000100, 13}, {8, 0b00000111, 14}, {9, 0b000011000, 15}, {10, 0b0000010111, 16}, {10, 0b0000011000, 17}, {10, 0b0000001000, 18}, {11, 0b00001100111, 19}, {11, 0b00001101000, 20}, {11, 0b00001101100, 21}, {11, 0b00000110111, 22}, {11, 0b00000101000, 23}, {11, 0b00000010111, 24}, {11, 0b00000011000, 25}, {12, 0b000011001010, 26}, {12, 0b000011001011, 27}, {12, 0b000011001100, 28}, {12, 0b000011001101, 29}, {12, 0b000001101000, 30}, {12, 0b000001101001, 31}, {12, 0b000001101010, 32}, {12, 0b000001101011, 33}, {12, 0b000011010010, 34}, {12, 0b000011010011, 35}, {12, 0b000011010100, 36}, {12, 0b000011010101, 37}, {12, 0b000011010110, 38}, {12, 0b000011010111, 39}, {12, 0b000001101100, 40}, {12, 0b000001101101, 41}, {12, 0b000011011010, 42}, {12, 0b000011011011, 43}, {12, 0b000001010100, 44}, {12, 0b000001010101, 45}, {12, 0b000001010110, 46}, {12, 0b000001010111, 47}, {12, 0b000001100100, 48}, {12, 0b000001100101, 49}, {12, 0b000001010010, 50}, {12, 0b000001010011, 51}, {12, 0b000000100100, 52}, {12, 0b000000110111, 53}, {12, 0b000000111000, 54}, {12, 0b000000100111, 55}, {12, 0b000000101000, 56}, {12, 0b000001011000, 57}, {12, 0b000001011001, 58}, {12, 0b000000101011, 59}, {12, 0b000000101100, 60}, {12, 0b000001011010, 61}, {12, 0b000001100110, 62}, {12, 0b000001100111, 63}, {10, 0b0000001111, 64}, {12, 0b000011001000, 128}, {12, 0b000011001001, 192}, {12, 0b000001011011, 256}, {12, 0b000000110011, 320}, {12, 0b000000110100, 384}, {12, 0b000000110101, 448}, {13, 0b0000001101100, 512}, {13, 0b0000001101101, 576}, {13, 0b0000001001010, 640}, {13, 0b0000001001011, 704}, {13, 0b0000001001100, 768}, {13, 0b0000001001101, 832}, {13, 0b0000001110010, 896}, {13, 0b0000001110011, 960}, {13, 0b0000001110100, 1024}, {13, 0b0000001110101, 1088}, {13, 0b0000001110110, 1152}, {13, 0b0000001110111, 1216}, {13, 0b0000001010010, 1280}, {13, 0b0000001010011, 1344}, {13, 0b0000001010100, 1408}, {13, 0b0000001010101, 1472}, {13, 0b0000001011010, 1536}, {13, 0b0000001011011, 1600}, {13, 0b0000001100100, 1664}, {13, 0b0000001100101, 1728}, {11, 0b00000001000, 1792}, {11, 0b00000001100, 1856}, {11, 0b00000001101, 1920}, {12, 0b000000010010, 1984}, {12, 0b000000010011, 2048}, {12, 0b000000010100, 2112}, {12, 0b000000010101, 2176}, {12, 0b000000010110, 2240}, {12, 0b000000010111, 2304}, {12, 0b000000011100, 2368}, {12, 0b000000011101, 2432}, {12, 0b000000011110, 2496}, {12, 0b000000011111, 2560}]

// A run table expanded into a direct lookup: every bit pattern opening with one code maps to that
// code's width and run, so a run is read with one peek instead of a walk down the tree.
private struct CcittRunTable
{
    length: Array'u8
    run:    Array'u16
}

private func buildRunTable(codes: const [..] CcittCode)->CcittRunTable
{
    var result: retval
    result.length.resize(CcittLookupSize)
    result.run.resize(CcittLookupSize)

    for one in codes
    {
        let shift = CcittLookupBits - cast(u32) one.bits
        let base  = cast(u64) one.code << shift
        for i in 1'u64 << shift
        {
            result.length[base + i] = one.bits
            result.run[base + i]    = one.run
        }
    }

    return result
}

// Reads the encoded stream one code at a time, most significant bit first.
private struct CcittBits
{
    data: const [..] u8
    pos:  u64
}

private impl CcittBits
{
    mtd const isAtEnd()->bool => .pos >= .data.count * 8

    // Returns the next `count` bits without consuming them, zero-filled past the end.
    //
    // A stream stopping in the middle of a code is padding rather than a failure, and reading
    // that padding as zeroes is what lets the caller notice the end at a code boundary.
    mtd const peek(count: u32)->u32
    {
        let index = .pos >> 3
        let shift = cast(u32) (.pos & 7)

        var window = 0'u64
        for i in 5'u64
        {
            let at = index + i
            window = window << 8 | (at < .data.count ? cast(u64) .data[at] : 0)
        }

        return cast(u32) ((window >> (40 - shift - count)) & ((1'u64 << count) - 1))
    }

    mtd skip(count: u32)
    {
        .pos += count
    }

    mtd alignToByte()
    {
        .pos = ((.pos + 7) / 8) * 8
    }

    // Consumes the zero fill a line may be padded with before its end-of-line code. Twelve
    // zeroes cannot open any run code, so such a window is fill and nothing else.
    mtd skipFill()
    {
        while !.isAtEnd() and .peek(CcittEndOfLineBits) == 0 do
            .skip(1)
    }
}

// Reads one complete run: a chain of make-up codes closed by a terminating code below 64.
private func readCcittRun(bits: *CcittBits, table: const *CcittRunTable)->s32 fail
{
    var result = 0's32
    for 64
    {
        let index  = bits.peek(CcittLookupBits)
        let length = table.length[index]
        if !length do
            fail InvalidFormatError{"CCITTFaxDecode stream contains an undefined run code"}

        bits.skip(length)
        let run = cast(s32) table.run[index]
        result += run
        if run < 64 do
            return result
    }

    fail InvalidFormatError{"CCITTFaxDecode run is made of too many make-up codes"}
}

// What one two-dimensional code says about the next changing element.
private enum CcittMode
{
    Pass
    Horizontal
    Vertical
    EndOfData
}

private struct CcittModeCode
{
    mode:  CcittMode
    delta: s32
}

// Reads one two-dimensional mode code.
//
// The seven codes form a prefix tree short enough to test directly, which keeps the vertical
// mode - by far the most frequent - at one peek and one branch.
private func readCcittMode(bits: *CcittBits)->CcittModeCode
{
    let window = bits.peek(7)
    if window & 0x40
    {
        bits.skip(1)
        return {.Vertical, 0}
    }

    switch window >> 4
    {
    case 0b011:
        bits.skip(3)
        return {.Vertical, 1}

    case 0b010:
        bits.skip(3)
        return {.Vertical, -1}

    case 0b001:
        bits.skip(3)
        return {.Horizontal, 0}
    }

    if window >> 3 == 0b0001
    {
        bits.skip(4)
        return {.Pass, 0}
    }

    switch window >> 1
    {
    case 0b000011:
        bits.skip(6)
        return {.Vertical, 2}

    case 0b000010:
        bits.skip(6)
        return {.Vertical, -2}
    }

    switch window
    {
    case 0b0000011:
        bits.skip(7)
        return {.Vertical, 3}

    case 0b0000010:
        bits.skip(7)
        return {.Vertical, -3}
    }

    return {.EndOfData, 0}
}

// Decodes one line written on its own, as alternating white and black runs.
private func decodeCcittLine1D(bits: *CcittBits, current: *Array's32, columns: s32, white, black: const *CcittRunTable) fail
{
    var at    = 0's32
    var color = 0'u32

    // A zero-length run is legal and says the line opens with the other colour, so the loop needs
    // a bound of its own rather than trusting the position to advance.
    for 2 * cast(u64) columns + 64
    {
        if at >= columns do
            return
        let run = try readCcittRun(bits, color ? black : white)
        at = Math.min(at + run, columns)
        current.add(at)
        color = 1 - color
    }

    fail InvalidFormatError{"CCITTFaxDecode one-dimensional line does not advance"}
}

// Decodes one line written as differences from the line above it.
private func decodeCcittLine2D(bits: *CcittBits, reference: const [..] s32, current: *Array's32, columns: s32, white, black: const *CcittRunTable) fail
{
    var a0    = -1's32
    var color = 0'u32

    for 2 * cast(u64) columns + 64
    {
        if a0 >= columns do
            return

        // b1 is the first changing element of the reference line right of a0 that opens a run of
        // the colour opposite to the one being coded, which is what its index parity says; b2 is
        // the one after it. Both fall off the end of a line as the line's own width.
        var index = 0'u64
        while index < reference.count and reference[index] <= a0 do
            index += 1
        if (index & 1) != color do
            index += 1
        let b1 = index < reference.count ? reference[index] : columns
        let b2 = index + 1 < reference.count ? reference[index + 1] : columns

        let code = readCcittMode(bits)
        switch code.mode
        {
        case .Pass:
            a0 = b2

        case .Horizontal:
            let start = Math.max(a0, 0)
            let first = try readCcittRun(bits, color ? black : white)
            let next  = try readCcittRun(bits, color ? white : black)
            let a1    = Math.min(start + first, columns)
            let a2    = Math.min(a1 + next, columns)
            current.add(a1)
            current.add(a2)
            a0 = a2

        case .Vertical:
            let a1 = Math.min(Math.max(b1 + code.delta, 0), columns)
            current.add(a1)
            a0    = a1
            color = 1 - color

        case .EndOfData:
            return
        }
    }

    fail InvalidFormatError{"CCITTFaxDecode two-dimensional line does not advance"}
}

private func writeCcittBlackRun(result: *Array'u8, base: u64, first, last: s32, blackIs1: bool)
{
    for x in first until last
    {
        let index = base + cast(u64) (x >> 3)
        let mask  = 0x80'u8 >> cast(u32) (x & 7)
        if blackIs1 do
            result[index] |= mask
        else do
            result[index] &= ~mask
    }
}

// Writes one decoded line as packed samples: black runs stamped over a white line.
private func writeCcittRow(result: *Array'u8, changes: const [..] s32, columns: s32, blackIs1: bool)
{
    let rowBytes = (cast(u64) columns + 7) / 8
    let base     = result.count
    result.resize(base + rowBytes)
    for i in rowBytes do
        result[base + i] = blackIs1 ? 0 : 0xFF

    var color = 0'u32
    var at    = 0's32
    for i in changes.count
    {
        let next = Math.min(Math.max(changes[i], 0), columns)
        if color and next > at do
            writeCcittBlackRun(result, base, at, next, blackIs1)
        at    = Math.max(at, next)
        color = 1 - color
    }

    if color and at < columns do
        writeCcittBlackRun(result, base, at, columns, blackIs1)
}

// Decodes a CCITTFaxDecode stream into packed one-bit samples.
//
// The result is what the image machinery reads: `columns` samples a line, most significant bit
// first, every line starting on a byte boundary. `blackIs1` chooses the sample value black takes,
// exactly as the filter parameter of that name says, and a stream ending early is completed with
// white lines so the samples always describe the whole declared image.
internal func decodeCcittFax(data: const [..] u8, params: CcittParameters)->Array'u8 fail
{
    if params.columns <= 0 or params.columns > CcittMaxColumns do
        fail InvalidFormatError{"CCITTFaxDecode stream declares an invalid column count"}

    let columns  = cast(s32) params.columns
    let rowBytes = (cast(u64) columns + 7) / 8
    let white    = buildRunTable(CcittWhiteCodes)
    let black    = buildRunTable(CcittBlackCodes)

    var bits = CcittBits{data, 0}

    var result:    retval
    var reference: Array's32
    var current:   Array's32
    var rows = 0's64

    // The line above the first one is an imaginary all-white line, which has no changing element
    // at all: an empty reference is what makes the first two-dimensional line decodable.
    while params.rows <= 0 or rows < params.rows
    {
        if params.byteAlign do
            bits.alignToByte()

        // Lines may be separated by fill and one or more end-of-line codes; two of them in a row
        // end the block.
        var endOfLines = 0'u32
        for
        {
            bits.skipFill()
            if bits.peek(CcittEndOfLineBits) != CcittEndOfLine do
                break
            bits.skip(CcittEndOfLineBits)
            endOfLines += 1
            if endOfLines >= 2 do
                break
        }

        if endOfLines >= 2 or bits.isAtEnd() do
            break

        var twoDimensional = params.k < 0
        if params.k > 0
        {
            twoDimensional = bits.peek(1) == 0
            bits.skip(1)
        }

        let before = bits.pos
        current.clear()
        if twoDimensional do
            try decodeCcittLine2D(&bits, reference.toSlice(), &current, columns, &white, &black)
        else do
            try decodeCcittLine1D(&bits, &current, columns, &white, &black)

        // A line that consumed nothing is the end of the data rather than an empty line; without
        // this an unterminated stream would go on producing white lines.
        if bits.pos == before do
            break

        writeCcittRow(&result, current.toSlice(), columns, params.blackIs1)
        rows += 1
        reference.clear()
        reference.add(current.toSlice())
    }

    // A stream that stopped early still describes an image of the declared height.
    while params.rows > 0 and rows < params.rows
    {
        let base = result.count
        result.resize(base + rowBytes)
        for i in rowBytes do
            result[base + i] = params.blackIs1 ? 0 : 0xFF
        rows += 1
    }

    return result
}

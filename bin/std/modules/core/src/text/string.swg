#global public

using Swag

// The largest capacity, in bytes, that a [[Core.String]] stores inline without allocating.
const StringSmallSize = 16'u64
#assert(#sizeof(String) == 56)

// Selects which letters a case conversion maps.
enum CharacterSet
{
    Latin1      // ASCII and Latin-1 letters only, keeping the byte count.
    Unicode     // Every letter with a Unicode simple case mapping.
}

// Iterates Unicode scalar values decoded lazily from borrowed UTF-8 bytes.
#[Swag.Opaque]
struct StringRunes
{
    bytes: const [..] u8
}

impl StringRunes
{
    // Visits each decoded rune with its zero-based character index and UTF-8 byte offset.
    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool) const opVisit(stmt: #code(value: rune, charIndex: u64, byteIndex: u64))
        where not ptr
    {
        Utf8.visitRunes(.bytes, stmt)
    }
}

// Owns a growable UTF-8 buffer, with small strings stored inline.
//
// Like [[Core.Array]], a string is a header over a memory block and that header is part of its
// contract: code that hands `buffer` to a C API then states how much was written sets `length`
// itself. So these fields stay writable, unlike the state of a type that maintains an invariant
// across its fields.
struct String
{
    public
    {
        buffer:    [*] u8?                  // Storage of the string, inline for a small one.
        length:    u64                      // Number of valid bytes in 'buffer'.
        capacity:  u64                      // Number of bytes 'buffer' can hold.
        allocator: IAllocator?              // Allocator used to grow the storage.
        padding:   [StringSmallSize] u8     // Inline storage of a small string.
    }
}

impl String
{
    // Returns the length in bytes.
    #[Inline]
    mtd const opCount()->u64 => .length

    // Returns the address of the bytes, null when the string owns no storage.
    #[Inline]
    mtd const opData()->const [*] u8? => .buffer

    // Converts the string implicitly to a `cstring`, a `string` or a `const [..] u8` that borrows its bytes.
    #[Implicit, Inline]
    mtd const opCast()->cstring? => .buffer

    #[Implicit, Inline]
    mtd const opCast()->string => Swag.makeString(.buffer, .length)

    #[Implicit, Inline]
    mtd const opCast()->const [..] u8 => Swag.makeSlice(.buffer, .length)

    // Returns the byte storage as a pointer the caller walks itself.
    //
    // A String that holds nothing owns no block, and a caller asking it for its storage is
    // about to walk zero bytes. The answer is then a dangling address that is never read,
    // rather than a null every caller would have to assert: walking is bounded by 'length',
    // and a read through the dangling address faults exactly as loudly as a read through
    // null. Ask 'isNull' or 'isNullOrEmpty' whether there is anything to walk.
    #[Inline]
    mtd const storage()->[*] u8 => .buffer orelse cast([*] u8) cast(u64) 1

    // Replaces the contents with a copy of `value`, which may view this string's own storage.
    //
    // A null `value` empties the string.
    #[Implicit]
    mtd opSet(value: string?)
    {
        if value.buffer == null
        {
            .length = 0
            if .buffer do
                .buffer[0] = 0
            return
        }

        if .buffer
        {
            let dataof = value.buffer
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(value)
                .opSet(copy.toString())
                return
            }
        }

        let newCapacity = value.count + 1
        .grow(newCapacity)
        .length = newCapacity - 1
        let buffer = .buffer!
        Memory.copy(buffer, value.buffer, .length)
        buffer[.length] = 0
    }

    // Returns a view of the bytes from `lower` to `upper`, both included.
    mtd const opSlice(lower, upper: u64)->string
    {
        Swag.assert(lower <= upper and lower < .length and upper < .length)
        return Swag.makeString(.buffer + lower, (upper + 1) - lower)
    }

    // Returns whether the string holds the same bytes as `other`.
    mtd const opEquals(other: string?)->bool
    {
        if .buffer == other.buffer do
            return true
        if .length != other.count do
            return false
        return Memory.compare(.buffer, other.buffer, .length) == 0
    }

    // Compares the bytes of the string with `other`, returning -1, 0 or 1.
    mtd const opCompare(other: string)->s32 => Utf8.compare(.toString(), other, .Latin1)

    // Adds `value` to, or subtracts it from, the byte at `index`, wrapping around.
    mtd(op: Swag.Operator) opIndexAssign(index: u64, value: u8)
        where op == .AddAssign or op == .SubAssign
    {
        Debug.safetyBoundCheck(index < .length, "index out of range")
        let buffer = .buffer!
        #static switch op
        {
        case .AddAssign: buffer[index] += #wrap value
        case .SubAssign: buffer[index] -= #wrap value
        }
    }

    // Sets the byte at `index`.
    mtd opIndexSet(index: u64, value: u8)
    {
        Debug.safetyBoundCheck(index < .length, "index out of range")
        let buffer = .buffer!
        buffer[index] = value
    }

    // Appends `value` with `+=`: a string, a rune or a byte, or a slice of them appended in order.
    mtd(op: Swag.Operator) opAssign(value: const [..] string)
        where op == .AddAssign
    {
        for v in value do
            .append(v)
    }

    mtd(op: Swag.Operator) opAssign(value: const [..] rune)
        where op == .AddAssign
    {
        for v in value do
            .append(v)
    }

    mtd(op: Swag.Operator) opAssign(value: const [..] u8)
        where op == .AddAssign
    {
        for v in value do
            .append(v)
    }

    mtd(op: Swag.Operator) opAssign(value: string?)
        where op == .AddAssign
    {
        .append(value)
    }

    mtd(op: Swag.Operator) opAssign(value: rune)
        where op == .AddAssign
    {
        .append(value)
    }

    mtd(op: Swag.Operator) opAssign(value: u8)
        where op == .AddAssign
    {
        .append(value)
    }

    // Points a moved small string back at its own inline storage.
    mtd opPostMove()
    {
        if .buffer and .capacity <= StringSmallSize do
            .buffer = cast() &.padding[0]
    }

    // Gives a copied string storage of its own.
    mtd opPostCopy()
    {
        if not .buffer do
            return

        if .capacity <= StringSmallSize do
            .buffer = cast() &.padding[0]
        else
        {
            let oldBuffer = .buffer
            .buffer   = null
            .capacity = 0
            .reserve(.length + 1)
            Memory.copy(.buffer, oldBuffer, .length + 1)
        }
    }

    // Releases the allocated storage, if any.
    mtd opDrop()
    {
        if not .buffer do
            return

        if .buffer != cast() &.padding[0] do
            Memory.free(.buffer, .capacity, .allocator)
    }

    // Returns the byte at `index`.
    #[Inline]
    mtd const opIndex(index: u64)->u8
    {
        Debug.safetyBoundCheck(index < .length, "index out of range")
        let buffer = .buffer!
        return buffer[index]
    }

    // Returns a mutable borrowed view of the UTF-8 bytes.
    #[Inline]
    mtd bytes()->[..] u8 => .toSlice()

    // Returns an immutable borrowed view of the UTF-8 bytes.
    #[Inline]
    mtd const bytes()->const [..] u8 => .toSlice()

    // Returns a zero-allocation view that decodes Unicode scalar values lazily.
    #[Inline]
    mtd const runes()->StringRunes => {bytes: .toSlice()}

    // Returns a zero-allocation view that traverses the UTF-8 bytes from last to first.
    mtd reversed()->ReversedSlice'u8 => reverseSlice(.toSlice())

    // Returns an immutable zero-allocation view that traverses the UTF-8 bytes from last to first.
    mtd const reversed()->ConstReversedSlice'u8 => reverseSlice(.toSlice())

    // Visits each byte with its index, in storage order.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(var item, var index: u64))
    {
        if not .length do
            return
        let buffer = .buffer!
        for index in .length
        {
            #static if ptr do
                #inject(stmt, item = cast(*u8) (buffer + index), index = index)
            else do
                #inject(stmt, item = buffer[index], index = index)
        }
    }

    // Empties the string, keeping its storage.
    #[Inline]
    mtd clear()
    {
        .length = 0

        // The guard binds the pointer instead of testing the field: a published inline body is
        // re-analyzed at the call site, where the receiver may be an expression that narrowing
        // cannot follow, such as an array element.
        let buffer = .buffer
        if buffer do
            buffer[0] = 0
    }

    // Returns whether the length is zero.
    #[Inline]
    mtd const isEmpty()->bool => .length == 0

    // Returns whether the string owns no storage.
    #[Inline]
    mtd const isNull()->bool => .buffer == null

    // Returns whether the string owns no storage or has zero length.
    #[Inline]
    mtd const isNullOrEmpty()->bool => .buffer == null or .length == 0

    // Makes a null string empty, pointing it at its inline storage.
    mtd ensureNotNull()
    {
        if .buffer do
            return
        .buffer = cast() &.padding[0]
    }

    // Replaces every occurrence of the rune `what` with `by`.
    mtd replace(what: rune, by: string)
    {
        if not .length do
            return
        if .buffer
        {
            let dataof = by.buffer
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(by)
                .replace(what, copy.toString())
                return
            }
        }

        var encoded: [4] u8
        let whatLength = cast(u64) Utf8.encodeRune(encoded, what)
        let byLength   = by.count

        var idx = Utf8.indexOf(.toString(), what, 0)
        while idx != Swag.U64.Max
        {
            .grow(.length - whatLength + byLength + 1)
            let buffer = .buffer!
            Memory.copyOverlapping(buffer + idx + byLength, buffer + idx + whatLength, .length - idx - whatLength)
            Memory.copy(buffer + idx, by.buffer, byLength)
            .length = .length - whatLength + byLength
            idx += byLength
            if idx == .length do
                break
            idx = Utf8.indexOf(.toString(), what, idx)
        }

        let buffer = .buffer!
        buffer[.length] = 0
    }

    // Replaces every occurrence of `what` with `by` under the case policy `comparisonType`.
    //
    // An empty `what` changes nothing, and a null `by` removes each occurrence.
    mtd replace(what: string, by: string?, comparisonType = Utf8.ComparisonType.Latin1)
    {
        let whatLength = what.count
        if not whatLength or whatLength > .length do
            return
        if .buffer
        {
            let whatDataof = what.buffer
            if whatDataof >= .buffer and whatDataof < .buffer + .length
            {
                let copy = String.from(what)
                .replace(copy.toString(), by, comparisonType)
                return
            }

            let byDataof = by.buffer
            if byDataof >= .buffer and byDataof < .buffer + .length
            {
                let copy = String.from(by)
                .replace(what, copy.toString(), comparisonType)
                return
            }
        }

        let byLength = by.count

        var idx = Utf8.indexOf(.toString(), what, 0, comparisonType)
        while idx != Swag.U64.Max
        {
            .reserve(.length + byLength + 1)
            Memory.copyOverlapping(.buffer + idx + byLength, .buffer + idx + whatLength, .length - (idx + whatLength) + 1)
            Memory.copy(.buffer + idx, by.buffer, byLength)
            .length -= whatLength
            .length += byLength
            idx     += byLength
            if idx == .length do
                break
            idx = Utf8.indexOf(.toString(), what, idx, comparisonType)
        }

        let buffer = .buffer!
        buffer[.length] = 0
    }

    // Returns the last byte, or 0 when the string is empty.
    mtd back()->u8
    {
        if not .length do
            return 0
        let buffer = .buffer!
        return buffer[.length - 1]
    }

    // Removes `byteCount` bytes starting at `byteIndex`.
    mtd remove(byteIndex: u64, byteCount: u64 = 1)
    {
        if not byteCount do
            return
        Debug.safetyBoundCheck(byteIndex + byteCount <= .length, "index out of range")
        let buffer = .buffer!
        Memory.copyOverlapping(buffer + byteIndex, buffer + byteIndex + byteCount, .length - (byteIndex + byteCount))
        .length         -= byteCount
        buffer[.length] = 0
    }

    // Removes the last `byteCount` bytes.
    mtd removeBack(byteCount: u64 = 1)
    {
        if not byteCount do
            return
        Debug.safetyBoundCheck(byteCount <= .length, "index out of range")
        let buffer = .buffer!
        .length         -= byteCount
        buffer[.length] = 0
    }

    // Inserts the byte `value` at `byteIndex`, which may be the length to append it.
    //
    // `value` must not be zero.
    mtd insert(byteIndex: u64, value: u8)
    {
        if byteIndex == .length
        {
            .append(value)
            return
        }

        Debug.safetyBoundCheck(byteIndex < .length, "index out of range")
        Swag.assert(value != 0)

        .grow(.length + 2)
        let buffer = .buffer!
        Memory.copyOverlapping(buffer + byteIndex + 1, buffer + byteIndex, .length - byteIndex + 1)
        buffer[byteIndex] = value
        .length += 1
    }

    // Inserts `value` at `byteIndex`, which may be the length to append it.
    //
    // `value` may view this string's own storage.
    mtd insert(byteIndex: u64, value: string)
    {
        if byteIndex == .length
        {
            .append(value)
            return
        }

        Debug.safetyBoundCheck(byteIndex < .length, "index out of range")
        let countof = value.count
        if not countof do
            return
        if .buffer
        {
            let dataof = value.buffer
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(value)
                .insert(byteIndex, copy.toString())
                return
            }
        }

        .grow(.length + countof + 1)
        Memory.copyOverlapping(.buffer + byteIndex + countof, .buffer + byteIndex, .length - byteIndex + 1)
        Memory.copy(.buffer + byteIndex, value.buffer, countof)
        .length += countof
    }

    // Appends `format` formatted with `values`, following the rules of [[Core.Format.toString]].
    mtd appendFormat(format: string, values: ...)
    {
        .append(Format.toString(format, values))
    }

    // Appends the byte `value`.
    #[Inline]
    mtd append(value: u8)
    {
        .grow(.length + 2)

        // One 16-bit store writes the byte and the zero terminator together.
        let buffer = .buffer!
        var ptr    = cast(*u16) (buffer + .length)
        ptr[]   = value
        .length += 1
    }

    // Appends the UTF-8 encoding of `value`, which must be a valid rune.
    mtd append(value: rune)
    {
        Swag.assert(Utf8.isValidRune(value), "invalid rune")
        var tmp: [4] u8
        let eat = Utf8.encodeRune(tmp, value)
        .grow(.length + eat + 1)
        let buffer = .buffer!
        for i in eat do
            buffer[.length + i] = tmp[i]
        .length         += eat
        buffer[.length] = 0
    }

    // Appends `value`, which may view this string's own storage.
    mtd append(value: string?)
    {
        let concatLength = value.count
        if concatLength == 0 do
            return
        if .buffer
        {
            let dataof = value.buffer
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(value)
                .append(copy.toString())
                return
            }
        }

        let newLength = .length + concatLength + 1
        .grow(newLength)
        let buffer = .buffer!
        Memory.copy(buffer + .length, value.buffer, concatLength)
        .length         = newLength - 1
        buffer[.length] = 0
    }

    // Returns the concatenation of `values`.
    func join(values: string...)->String
    {
        var result: retval
        for v in values do
            result += v
        return result
    }

    // Returns the concatenation of `values`, with `separator` between each pair.
    func joinWith(separator: string, values: string...)->String
    {
        var result: retval
        for v, index in values
        {
            if separator.count and index do
                result += separator
            result += v
        }

        return result
    }

    // Ensures room for `wantedCapacity` bytes, at least doubling the capacity when it grows.
    #[Inline]
    mtd grow(wantedCapacity: u64)
    {
        if wantedCapacity <= .capacity do
            return
        .reserve(Math.max(.capacity * 2, wantedCapacity))
    }

    // Sets the capacity to `newCapacity` bytes, truncating the text that no longer fits.
    //
    // A capacity up to [[Core.StringSmallSize]] uses the inline storage and releases any allocation.
    mtd reserve(newCapacity: u64)
    {
        .length = Math.min(.length, newCapacity)
        if .allocator == null do
            .allocator = Swag.getContext().allocator

        // A small capacity always uses the inline storage.
        if newCapacity <= StringSmallSize
        {
            // Free dynamic memory if this is not a small string
            if .buffer and .buffer != cast() &.padding[0]
            {
                Memory.copy(&.padding[0], .buffer, Math.min(newCapacity, .length + 1))
                Memory.free(.buffer, .capacity, .allocator)
            }

            // This is a small string again
            .capacity = StringSmallSize
            .buffer   = cast() &.padding[0]
        }

        // We were in small size mode, and we are no more
        elif .buffer == cast() &.padding[0]
        {
            let oldBuffer = .buffer
            .buffer = cast() Memory.alloc(newCapacity, .allocator)
            Memory.copy(.buffer, oldBuffer, Math.min(newCapacity, .length + 1))
            .capacity = newCapacity
        }

        // First allocation directly to dynamic storage
        elif not .buffer
        {
            .buffer   = cast() Memory.alloc(newCapacity, .allocator)
            .capacity = newCapacity
        }

        // We were in dynamic mode, so just realloc memory
        else
        {
            .buffer   = cast() Memory.realloc(.buffer, newCapacity, .capacity, .allocator)
            .capacity = newCapacity
        }
    }

    // Removes the white space at the start of the string, as judged by [[Core.Unicode.isSpace]].
    mtd trimStart()
    {
        if not .length do
            return

        let buffer     = .buffer!
        let asciiBytes = Latin1.firstNonSpace(.toSlice(), includeLatin1: false)
        var ptr        = buffer + asciiBytes
        .length -= asciiBytes
        for
        {
            let {c, eat} = Utf8.decodeRune(Swag.makeSlice(ptr, .length))
            if not Unicode.isSpace(c) do
                break
            .length -= eat
            ptr     += eat
        }

        Memory.copyOverlapping(buffer, ptr, .length)
        buffer[.length] = 0
    }

    // Removes the white space at the end of the string, as judged by [[Core.Unicode.isSpace]].
    mtd trimEnd()
    {
        if not .length do
            return

        let buffer = .buffer!
        .length = Latin1.lastNonSpace(.toSlice(), includeLatin1: false)
        for
        {
            let {c, eat} = Utf8.decodeLastRune(Swag.makeSlice(buffer, .length))
            if not Unicode.isSpace(c) do
                break
            .length -= eat
        }

        buffer[.length] = 0
    }

    // Removes the white space at both ends of the string, as judged by [[Core.Unicode.isSpace]].
    mtd trim()
    {
        .trimStart()
        .trimEnd()
    }

    // Returns the runes of the string, decoded from UTF-8.
    mtd const toRuneArray()->Array'rune => Unicode.fromUtf8(.toSlice())

    // Returns a new string holding a copy of `value`.
    func from(value: string?)->String
    {
        var result: retval = value
        return result
    }

    // Returns a `string` view of the bytes, borrowing the storage.
    #[Inline]
    mtd const toString()->string => Swag.makeString(.buffer, .length)

    // Returns a mutable view of the bytes, borrowing the storage.
    #[Inline]
    mtd toSlice()->[..] u8 => Swag.makeSlice(.buffer, .length)

    // Returns an immutable view of the bytes, borrowing the storage.
    #[Inline]
    mtd const toSlice()->const [..] u8 => Swag.makeSlice(.buffer, .length)

    // Replaces the content with the UTF-8 encoding of `runes`, keeping the allocator.
    private mtd setRunes(runes: const [..] rune)
    {
        // Four bytes per rune in the worst case, and one more for the terminator.
        .reserve(runes.count * 4 + 1)
        let buffer = .buffer!
        .length         = Utf8.fromUnicode(Swag.makeSlice(buffer, runes.count * 4), runes)
        buffer[.length] = 0
    }

    // Converts the string to upper case in place.
    //
    // `.Latin1` keeps the byte count; `.Unicode` re-encodes the whole text.
    mtd makeUpper(set = CharacterSet.Latin1)
    {
        switch set
        {
        case .Latin1:
            Core.Latin1.makeUpper(.toSlice())

        case .Unicode:
            var uni32 = Core.Unicode.fromUtf8(.toString())
            Core.Unicode.makeUpper(uni32.toSlice())
            .setRunes(uni32.toSlice())
        }
    }

    // Converts the string to lower case in place.
    //
    // `.Latin1` keeps the byte count; `.Unicode` re-encodes the whole text.
    mtd makeLower(set = CharacterSet.Latin1)
    {
        switch set
        {
        case .Latin1:
            Core.Latin1.makeLower(.toSlice())

        case .Unicode:
            var uni32 = Core.Unicode.fromUtf8(.toString())
            Core.Unicode.makeLower(uni32.toSlice())
            .setRunes(uni32.toSlice())
        }
    }

    // Returns a copy of the string converted to upper case, like [[Core.String.makeUpper]].
    mtd const toUpper(set = CharacterSet.Latin1)->String
    {
        var result: retval = me
        result.makeUpper(set)
        return result
    }

    // Returns a new string holding `str` converted to upper case, like [[Core.String.makeUpper]].
    func toUpper(str: string, set = CharacterSet.Latin1)->String
    {
        var result: retval = str
        result.makeUpper(set)
        return result
    }

    // Returns a copy of the string converted to lower case, like [[Core.String.makeLower]].
    mtd const toLower(set = CharacterSet.Latin1)->String
    {
        var result: retval = me
        result.makeLower(set)
        return result
    }

    // Returns a new string holding `str` converted to lower case, like [[Core.String.makeLower]].
    func toLower(str: string?, set = CharacterSet.Latin1)->String
    {
        var result: retval = str
        result.makeLower(set)
        return result
    }

    {
        // Returns whether the string contains `what`, as [[Core.Utf8.contains]] decides.
        mtd const contains(what: u8)->bool            => Utf8.contains(.toSlice(), what)
        mtd const contains(what: rune)->bool          => Utf8.contains(.toSlice(), what)
        mtd const contains(what: string)->bool        => Utf8.contains(.toSlice(), what)
        mtd const contains(what: const [..] u8)->bool => Utf8.contains(.toSlice(), what)

        // Returns whether the string starts with `str` under the case policy `comparisonType`.
        mtd const startsWith(str: string, comparisonType = Utf8.ComparisonType.Latin1)->bool => Utf8.startsWith(.toSlice(), str, comparisonType)

        // Returns whether the string ends with `str` under the case policy `comparisonType`.
        mtd const endsWith(str: string, comparisonType = Utf8.ComparisonType.Latin1)->bool => Utf8.endsWith(.toSlice(), str, comparisonType)

        // Returns the byte index of the first `what` at or after `startByteIndex`, or `Swag.U64.Max` when it is absent.
        mtd const indexOf(what: string, startByteIndex = 0'u64, comparisonType = Utf8.ComparisonType.Latin1)->u64 => Utf8.indexOf(.toSlice(), what, startByteIndex, comparisonType)
        mtd const indexOf(what: rune, startByteIndex = 0'u64)->u64 => Utf8.indexOf(.toSlice(), what, startByteIndex)
    }
}

impl Hash.IHash32 for String
{
    func impl compute(const me)->u32
    {
        // Same function as the one used for 'string', so a 'String' and the text it
        // holds always hash alike.
        return Hash.hashBytes32(.toSlice())
    }
}

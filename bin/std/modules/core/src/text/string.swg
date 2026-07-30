#global public

using Swag

// Defines string small size.
const StringSmallSize = 16'u64
#assert(#sizeof(String) == 56)

// Selects character set.
enum CharacterSet
{
    Latin1      // Selects latin1.
    Unicode     // Selects unicode.
}

// Represents string.
struct String
{
    buffer:    #null [*] u8             // Buffer associated with this value.
    length:    u64                      // Length associated with this value.
    capacity:  u64                      // Capacity associated with this value.
    allocator: #null IAllocator         // Allocator associated with this value.
    padding:   [StringSmallSize] u8     // Padding associated with this value.
}

impl String
{
    // Returns the number of elements.
    #[Inline]
    mtd const opCount()->u64
    {
        return .length
    }

    // Returns the underlying data address.
    #[Inline]
    mtd const opData()->#null const [*] u8
    {
        return .buffer
    }

    // Converts this value to another representation.
    // Converts this value to another representation.
    #[Implicit, Inline]
    mtd const opCast()->#null cstring
    {
        return .buffer
    }

    #[Implicit, Inline]
    mtd const opCast()->string
    {
        return @mkstring(.buffer, .length)
    }

    #[Implicit, Inline]
    mtd const opCast()->const [..] u8
    {
        return @mkslice(.buffer, .length)
    }

    // Assigns a value.
    #[Implicit]
    mtd opSet(value: #null string)
    {
        if @dataof(value) == null
        {
            .length = 0
            if .buffer do
                .buffer[0] = 0
            return
        }

        if .buffer
        {
            let dataof = @dataof(value)
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(value)
                .opSet(copy.toString())
                return
            }
        }

        let newCapacity = @countof(value) + 1
        .length = newCapacity - 1
        .grow(newCapacity)
        let buffer = notnull .buffer
        Memory.copy(buffer, @dataof(value), .length)
        buffer[.length] = 0
    }

    // Returns a slice of this value.
    mtd const opSlice(lower, upper: u64)->string
    {
        Debug.assert(lower <= upper and lower < .length and upper < .length)
        return @mkstring(.buffer + lower, (upper + 1) - lower)
    }

    // Returns whether two values are equal.
    mtd const opEquals(other: #null string)->bool
    {
        if .buffer == @dataof(other) do
            return true
        if .length != @countof(other) do
            return false
        return Memory.compare(.buffer, @dataof(other), .length) == 0
    }

    // Compares this value with another value.
    mtd const opCompare(other: string)->s32
    {
        return Utf8.compare(.toString(), other, Utf8.ComparisonType.Latin1)
    }

    // Applies an assignment operator to the byte at the requested index.
    mtd(op: Swag.Operator) opIndexAssign(index: u64, value: u8)
    {
        Debug.safetyBoundCheck(index < .length, "index out of range")
        let buffer = notnull .buffer
        #static switch op
        {
        case .AddAssign: buffer[index] += #wrap value
        case .SubAssign: buffer[index] -= #wrap value
        default:         #error("invalid operator '" ++ op.symbol() ++ "'")
        }
    }

    // Sets an element by index.
    mtd opIndexSet(index: u64, value: u8)
    {
        Debug.safetyBoundCheck(index < .length, "index out of range")
        let buffer = notnull .buffer
        buffer[index] = value
    }

    // Applies an assignment operator with a sequence of strings.
    mtd(op: Swag.Operator) opAssign(value: const [..] string)
    {
        #static if op == .AddAssign do
            for v in value do
                .append(v)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    mtd(op: Swag.Operator) opAssign(value: const [..] string)
    {
        #static if op == .AddAssign do
            for v in value do
                .append(v)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    mtd(op: Swag.Operator) opAssign(value: const [..] rune)
    {
        #static if op == .AddAssign do
            for v in value do
                .append(v)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    mtd(op: Swag.Operator) opAssign(value: const [..] u8)
    {
        #static if op == .AddAssign do
            for v in value do
                .append(v)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    mtd(op: Swag.Operator) opAssign(value: #null string)
    {
        #static if op == .AddAssign do
            .append(value)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    mtd(op: Swag.Operator) opAssign(value: rune)
    {
        #static if op == .AddAssign do
            .append(value)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    mtd(op: Swag.Operator) opAssign(value: u8)
    {
        #static if op == .AddAssign do
            .append(value)
        else do
            #error("invalid operator '" ++ op.symbol() ++ "'")
    }

    // Completes a moved value.
    mtd opPostMove()
    {
        if .buffer and .capacity <= StringSmallSize do
            .buffer = cast() &.padding[0]
    }

    // Completes a copied value.
    mtd opPostCopy()
    {
        if !.buffer do
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

    // Releases resources owned by this value.
    mtd opDrop()
    {
        if !.buffer do
            return

        if .buffer != cast() &.padding[0] do
            Memory.free(.buffer, .capacity, .allocator)
    }

    // Returns the byte at the given index
    #[Inline]
    mtd const opIndex(index: u64)->u8
    {
        Debug.safetyBoundCheck(index < .length, "index out of range")
        let buffer = notnull .buffer
        return buffer[index]
    }

    // Visit the String runes
    // See [[Utf8.visitRunes]] for the block parameters: the code value is forwarded as-is.
    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool, back: bool) const opVisitRunes(stmt: #code(c: rune, charIdx: u64, byteIdx: u64))
    {
        #static if ptr do
            #error("visiting runes by pointer is not supported")
        #static if back do
            #error("visiting runes in reverse order is not supported")
        Utf8.visitRunes(.toSlice(), stmt)
    }

    // Visit the String utf8 bytes
    // Block parameters: 'item' is the byte (or the pointer to it), 'index' the byte index.
    #[Macro]
    mtd(ptr: bool, back: bool) const opVisitBytes(stmt: #code(var item, var index: u64))
    {
        if !.length do
            return

        // Little trick to avoid labels. That way a 'continue' in the user code will work correctly
        let buffer = notnull .buffer

        #static if back do
            var scan = buffer + .length
        else do
            var scan = buffer - 1

        for .length
        {
            #static if back do
                scan -= 1
            else do
                scan += 1

            #static if back do
                let visitIdx = me.length - @index - 1
            else do
                let visitIdx = @index

            #static if ptr do
                #inject(stmt, item = cast(&u8) scan, index = visitIdx)
            else do
                #inject(stmt, item = dref scan, index = visitIdx)
        }
    }

    // Default element iteration, by bytes: the code value is forwarded to 'opVisitBytes' as-is.
    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(var item, var index: u64))
    {
        .opVisitBytes'(ptr, back)(stmt)
    }

    // Set the length of the String to 0
    #[Inline]
    mtd clear()
    {
        .length = 0
        if .buffer do
            .buffer[0] = 0
    }

    // Returns true if the String has zero length
    #[Inline]
    mtd const isEmpty()->bool
    {
        return .length == 0
    }

    // Returns true if the String is null (undefined)
    #[Inline]
    mtd const isNull()->bool
    {
        return .buffer == null
    }

    // Returns true if the String is null or empty
    #[Inline]
    mtd const isNullOrEmpty()->bool
    {
        return .buffer == null or .length == 0
    }

    // Transform a null string in an empty one
    mtd ensureNotNull()
    {
        if .buffer do
            return
        .buffer = cast() &.padding[0]
    }

    // Replace all occurences of 'what' with 'by'
    mtd replace(what: rune, by: string)
    {
        if !.length do
            return
        if .buffer
        {
            let dataof = @dataof(by)
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(by)
                .replace(what, copy.toString())
                return
            }
        }

        let byLength = @countof(by)

        var idx = Utf8.indexOf(.toString(), what, 0)
        while idx != Swag.U64.Max
        {
            .reserve(.length + byLength + 1)
            Memory.copyOver(.buffer + idx + byLength, .buffer + idx + 1, .length - idx)
            Memory.copy(.buffer + idx, @dataof(by), byLength)
            .length -= 1
            .length += byLength
            idx     += byLength
            if idx == .length do
                break
            idx = Utf8.indexOf(.toString(), what, idx)
        }

        let buffer = notnull .buffer
        buffer[.length] = 0
    }

    // Replace all occurences of 'what' with 'by'
    mtd replace(what: string, by: #null string, comparisonType = Utf8.ComparisonType.Latin1)
    {
        let whatLength = @countof(what)
        if !whatLength or whatLength > .length do
            return
        if .buffer
        {
            let whatDataof = @dataof(what)
            if whatDataof >= .buffer and whatDataof < .buffer + .length
            {
                let copy = String.from(what)
                .replace(copy.toString(), by, comparisonType)
                return
            }

            let byDataof = @dataof(by)
            if byDataof >= .buffer and byDataof < .buffer + .length
            {
                let copy = String.from(by)
                .replace(what, copy.toString(), comparisonType)
                return
            }
        }

        let byLength = @countof(by)

        var idx = Utf8.indexOf(.toString(), what, 0, comparisonType)
        while idx != Swag.U64.Max
        {
            .reserve(.length + byLength + 1)
            Memory.copyOver(.buffer + idx + byLength, .buffer + idx + whatLength, .length - (idx + whatLength) + 1)
            Memory.copy(.buffer + idx, @dataof(by), byLength)
            .length -= whatLength
            .length += byLength
            idx     += byLength
            if idx == .length do
                break
            idx = Utf8.indexOf(.toString(), what, idx, comparisonType)
        }

        let buffer = notnull .buffer
        buffer[.length] = 0
    }

    // Get the last byte
    mtd back()->u8
    {
        if !.length do
            return 0
        let buffer = notnull .buffer
        return buffer[.length - 1]
    }

    // Remove some bytes at the given index
    mtd remove(byteIndex: u64, byteCount: u64 = 1)
    {
        if !byteCount do
            return
        Debug.safetyBoundCheck(byteIndex + byteCount <= .length, "index out of range")
        let buffer = notnull .buffer
        Memory.copyOver(buffer + byteIndex, buffer + byteIndex + byteCount, .length - (byteIndex + byteCount))
        .length         -= byteCount
        buffer[.length] = 0
    }

    // Remove some bytes at the end
    mtd removeBack(byteCount: u64 = 1)
    {
        if !byteCount do
            return
        Debug.safetyBoundCheck(byteCount <= .length, "index out of range")
        let buffer = notnull .buffer
        .length         -= byteCount
        buffer[.length] = 0
    }

    // Insert an ascii byte at the given position
    mtd insert(byteIndex: u64, value: u8)
    {
        if byteIndex == .length
        {
            .append(value)
            return
        }

        Debug.safetyBoundCheck(byteIndex < .length, "index out of range")
        Debug.assert(value != 0)

        .grow(.length + 2)
        let buffer = notnull .buffer
        Memory.copyOver(buffer + byteIndex + 1, buffer + byteIndex, .length - byteIndex + 1)
        buffer[byteIndex] = value
        .length           += 1
    }

    // Insert a substring at the given position
    mtd insert(byteIndex: u64, value: string)
    {
        if byteIndex == .length
        {
            .append(value)
            return
        }

        Debug.safetyBoundCheck(byteIndex < .length, "index out of range")
        let countof = @countof(value)
        if !countof do
            return
        if .buffer
        {
            let dataof = @dataof(value)
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(value)
                .insert(byteIndex, copy.toString())
                return
            }
        }

        .grow(.length + countof + 1)
        Memory.copyOver(.buffer + byteIndex + countof, .buffer + byteIndex, .length - byteIndex + 1)
        Memory.copy(.buffer + byteIndex, @dataof(value), countof)
        .length += countof
    }

    // Append a formatted string
    mtd appendFormat(format: string, values: ...)
    {
        .append(Format.toString(format, values))
    }

    // Append a byte to the String
    #[Inline]
    mtd append(value: u8)
    {
        .grow(.length + 2)
        let buffer = notnull .buffer
        var ptr    = cast(*u16) (buffer + .length)
        dref ptr = value
        .length  += 1
    }

    // Append a rune to the String
    mtd append(value: rune)
    {
        Debug.assert(Utf8.isValidRune(value), "invalid rune")
        var tmp: [4] u8
        let eat = Utf8.encodeRune(tmp, value)
        .grow(.length + eat + 1)
        let buffer = notnull .buffer
        for [i] in eat do
            buffer[.length + i] = tmp[i]
        .length                 += eat
        buffer[.length]         = 0
    }

    // Append a string to the String
    mtd append(value: #null string)
    {
        let concatLength = @countof(value)
        if concatLength == 0 do
            return
        if .buffer
        {
            let dataof = @dataof(value)
            if dataof >= .buffer and dataof < .buffer + .length
            {
                let copy = String.from(value)
                .append(copy.toString())
                return
            }
        }

        let newLength = .length + concatLength + 1
        .grow(newLength)
        let buffer = notnull .buffer
        Memory.copy(buffer + .length, @dataof(value), concatLength)
        .length         = newLength - 1
        buffer[.length] = 0
    }

    // Join a list of strings to make a unique one
    func join(values: string...)->String
    {
        var result: String
        for values do
            result += values[@index]
        return result
    }

    // Join an list of strings to make a unique one, by using a given 'separator'
    // between them
    func joinWith(separator: string, values: string...)->String
    {
        var result: String
        for values
        {
            if separator and @index do
                result += separator
            result     += values[@index]
        }

        return result
    }

    // Ensure the String is big enough to store a given amount of bytes
    #[Inline]
    mtd grow(wantedCapacity: u64)
    {
        if wantedCapacity <= .capacity do
            return
        let newCapacity = Math.max(.capacity * 2, wantedCapacity)
        .reserve(newCapacity)
    }

    // Reserve room for at least 'newCapacity' bytes
    mtd reserve(newCapacity: u64)
    {
        .length = Math.min(.length, newCapacity)
        if .allocator == null do
            .allocator = @getcontext().allocator

        // Small size, just be sure with have a valid buffer address
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
        elif !.buffer
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

    // Remove whitespaces at the start of the String
    mtd trimStart()
    {
        if !.length do
            return

        let buffer = notnull .buffer
        var ptr    = buffer
        for
        {
            let sl       = @mkslice(ptr, .length)
            let {c, eat} = Utf8.decodeRune(sl)
            if !Unicode.isSpace(c) do
                break
            .length -= eat
            ptr     += eat
        }

        Memory.copy(buffer, ptr, .length)
        buffer[.length] = 0
    }

    // Remove whitespaces at the end of the String
    mtd trimEnd()
    {
        if !.length do
            return

        let buffer = notnull .buffer
        for
        {
            let sl       = @mkslice(buffer, .length)
            let {c, eat} = Utf8.decodeLastRune(sl)
            if !Unicode.isSpace(c) do
                break
            .length -= eat
        }

        buffer[.length] = 0
    }

    // Removes all leading and trailing white-space characters from the current String
    mtd trim()
    {
        .trimStart()
        .trimEnd()
    }

    // Convert string to a 32 bits character array
    mtd const toRuneArray()->Array'rune
    {
        return Unicode.fromUtf8(@mkslice(.buffer, .length))
    }

    // Convert a literal string to a String
    func from(value: #null string)->String
    {
        var val: retval = value
        return val
    }

    // Returns a string type
    #[Inline]
    mtd const toString()->string
    {
        return @mkstring(.buffer, .length)
    }

    // Returns a slice type
    #[Inline]
    mtd toSlice()->[..] u8
    {
        return @mkslice(.buffer, .length)
    }

    // Returns a slice type
    #[Inline]
    mtd const toSlice()->const [..] u8
    {
        return @mkslice(.buffer, .length)
    }

    // Convert the string inplace to upper case.
    mtd makeUpper(set = CharacterSet.Latin1)
    {
        let sl = @mkslice(.buffer, .length)
        switch set
        {
        case .Latin1:
            Core.Latin1.makeUpper(sl)

        case .Unicode:
            var uni32 = Core.Unicode.fromUtf8(.toString())
            Core.Unicode.makeUpper(uni32.toSlice())
            .reserve(uni32.count * 4)
            .length = Utf8.fromUnicode(@mkslice(.buffer, .capacity), uni32.toSlice())
        }
    }

    // Convert the string inplace to lower case.
    mtd makeLower(set = CharacterSet.Latin1)
    {
        let sl = @mkslice(.buffer, .length)
        switch set
        {
        case .Latin1:
            Core.Latin1.makeLower(sl)

        case .Unicode:
            var uni32 = Core.Unicode.fromUtf8(.toString())
            Core.Unicode.makeLower(uni32.toSlice())
            .reserve(uni32.count * 4)
            .length = Utf8.fromUnicode(@mkslice(.buffer, .capacity), uni32.toSlice())
        }
    }

    // Returns a new String in upper case
    mtd toUpper(set = CharacterSet.Latin1)->String
    {
        var result: retval = me
        result.makeUpper(set)
        return result
    }

    // Returns a new String in lower case
    func toUpper(str: string, set = CharacterSet.Latin1)->String
    {
        var result: retval = str
        result.makeUpper(set)
        return result
    }

    // Returns a new String in lower case
    mtd toLower(set = CharacterSet.Latin1)->String
    {
        var result: retval = me
        result.makeLower(set)
        return result
    }

    // Returns a new String in lower case
    func toLower(str: #null string, set = CharacterSet.Latin1)->String
    {
        var result: retval = str
        result.makeLower(set)
        return result
    }

    {
        // Returns true if the string contains 'what'
        mtd const contains(what: u8)->bool            => Utf8.contains(.toSlice(), what)
        mtd const contains(what: rune)->bool          => Utf8.contains(.toSlice(), what)
        mtd const contains(what: string)->bool        => Utf8.contains(.toSlice(), what)
        mtd const contains(what: const [..] u8)->bool => Utf8.contains(.toSlice(), what)

        // Return true if the string starts with 'str'
        mtd const startsWith(str: string, comparisonType = Utf8.ComparisonType.Latin1)->bool => Utf8.startsWith(.toSlice(), str, comparisonType)

        // Find 'what', and returns the byte index of it
        mtd const indexOf(what: string, startByteIndex = 0'u64, comparisonType = Utf8.ComparisonType.Latin1)->u64 => Utf8.indexOf(.toSlice(), what, startByteIndex, comparisonType)
        mtd const indexOf(what: rune, startByteIndex = 0'u64)->u64                                                => Utf8.indexOf(.toSlice(), what, startByteIndex)
    }
}

impl Hash.IHash32 for String
{
    func impl compute(const me)->u32
    {
        // Same function as the one used for 'string', so a 'String' and the text it
        // holds always hash alike
        return Hash.hashBytes32(@mkslice(.buffer, .length))
    }
}

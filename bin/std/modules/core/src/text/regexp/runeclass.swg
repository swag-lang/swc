#global namespace Parser.Regex
#global internal

// One inclusive interval of scalar values.
struct RuneRange
{
    lo: rune     // First scalar value of the interval.
    hi: rune     // Last scalar value of the interval, included.
}

// A set of scalar values, kept as sorted disjoint intervals.
//
// Every character class of a pattern — a literal, `[a-z]`, `\d`, `\pL`, `.` — becomes one of
// these before anything is compiled. Keeping one representation means case folding, negation
// and the UTF-8 automaton are each written once.
struct RuneClass
{
    ranges: Array'RuneRange     // Sorted, disjoint, non-adjacent once normalized.
}

impl RuneClass
{
    // Adds one interval; the class stays unnormalized until 'normalize' runs.
    mtd add(lo, hi: rune)
    {
        if lo > hi do
            return
        .ranges.add({lo, hi})
    }

    // Adds one scalar value.
    mtd addRune(value: rune)
    {
        .ranges.add({value, value})
    }

    // Adds every interval of another class.
    mtd addClass(other: RuneClass)
    {
        for range in other.ranges do
            .ranges.add(range)
    }

    // Adds a Unicode table, expanding the strided entries the tables use for scattered blocks.
    mtd addTable(table: const [..] Unicode.Range)
    {
        for &range in table
        {
            if range.stride == 1
            {
                .ranges.add({range.lo, range.hi})
                continue
            }

            var scalar = range.lo
            while scalar <= range.hi
            {
                .ranges.add({scalar, scalar})
                scalar += range.stride
            }
        }
    }

    mtd const isEmpty() => .ranges.isEmpty()

    // Sorts the intervals and merges the ones that touch, which every other operation assumes.
    mtd normalize()
    {
        if .ranges.count <= 1 do
            return

        .ranges.sort(func||(left, right) { return left.lo <=> right.lo })

        var writeIndex = 0'u64
        for var readIndex = 1'u64; readIndex < .ranges.count; readIndex += 1
        {
            let currentRange = .ranges[readIndex]
            if currentRange.lo <= .ranges[writeIndex].hi + 1
            {
                if currentRange.hi > .ranges[writeIndex].hi do
                    .ranges[writeIndex].hi = currentRange.hi
                continue
            }

            writeIndex += 1
            .ranges[writeIndex] = currentRange
        }

        .ranges.resize(writeIndex + 1)
    }

    // Replaces the class with its complement over the whole scalar range.
    mtd negate()
    {
        .normalize()

        var result: Array'RuneRange
        var nextScalar = 0'rune
        for &range in .ranges
        {
            if range.lo > nextScalar do
                result.add({nextScalar, range.lo - 1})
            if range.hi >= Utf8.MaxRune
            {
                .ranges = #move result
                return
            }

            nextScalar = range.hi + 1
        }

        result.add({nextScalar, Utf8.MaxRune})
        .ranges = #move result
    }

    // Adds the other case of every scalar value the class holds, so the class matches
    // both cases of everything it names.
    //
    // A very wide interval is left alone: it already covers the folded values of anything
    // inside it, and walking it scalar by scalar would cost more than the pattern.
    mtd foldCase()
    {
        .normalize()

        const WidestFoldedRange = 4096'rune

        var folded: RuneClass
        for &range in .ranges
        {
            if range.hi - range.lo >= WidestFoldedRange do
                continue

            var scalar = range.lo
            while scalar <= range.hi
            {
                let upper = Unicode.toUpper(scalar)
                let lower = Unicode.toLower(scalar)
                if upper != scalar do
                    folded.addRune(upper)
                if lower != scalar do
                    folded.addRune(lower)
                scalar += 1
            }
        }

        if folded.isEmpty() do
            return

        .addClass(folded)
        .normalize()
    }

    // Returns whether one scalar value belongs to the class.
    mtd const contains(value: rune)->bool
    {
        var low  = 0'u64
        var high = .ranges.count
        while low < high
        {
            let middle = (low + high) / 2
            let range  = .ranges[middle]
            if value < range.lo do
                high = middle
            elif value > range.hi do
                low = middle + 1
            else do
                return true
        }

        return false
    }

    // Returns whether every scalar value of the class is an ASCII one, which is what lets a
    // class become a plain byte range instead of a UTF-8 automaton.
    mtd const isAscii()->bool
    {
        if .ranges.isEmpty() do
            return true
        return .ranges.back().hi < 0x80
    }
}

// The named classes a pattern can ask for, by their POSIX and shorthand spellings.
impl RuneClass
{
    // Returns the class of one POSIX name, without its brackets, or an empty result
    // when the name is not a POSIX class.
    func posix(name: string)->{ value: RuneClass, known: bool }
    {
        var result: retval

        with let value = &result.value
        {
            switch name
            {
            case "digit":
                .add('0', '9')

            case "xdigit":
                .add('0', '9')
                .add('a', 'f')
                .add('A', 'F')

            case "alpha":
                .add('a', 'z')
                .add('A', 'Z')

            case "alnum":
                .add('0', '9')
                .add('a', 'z')
                .add('A', 'Z')

            case "lower":
                .add('a', 'z')

            case "upper":
                .add('A', 'Z')

            case "blank":
                .addRune(' ')
                .addRune('\t')

            case "space":
                .add('\t', '\r')
                .addRune(' ')

            case "word":
                .add('0', '9')
                .add('a', 'z')
                .add('A', 'Z')
                .addRune('_')

            case "ascii":
                .add(0, 0x7F)

            case "punct":
                .add('!', '/')
                .add(':', '@')
                .add('[', '`')
                .add('{', '~')

            case "cntrl":
                .add(0, 0x1F)
                .addRune(0x7F)

            case "graph":
                .add('!', '~')

            case "print":
                .add(' ', '~')

            default:
                return result
            }

            .normalize()
        }

        result.known = true
        return result
    }

    // Returns the class of one Unicode property name, or an empty result when the name is
    // not a supported property.
    func unicodeProperty(name: string)->{ value: RuneClass, known: bool }
    {
        var result: retval

        with let value = &result.value
        {
            switch name
            {
            case "L", "Letter":            .addTable(Unicode.TableLetter)
            case "Ll", "Lowercase_Letter": .addTable(Unicode.TableLower)
            case "Lu", "Uppercase_Letter": .addTable(Unicode.TableUpper)
            case "Lt", "Titlecase_Letter": .addTable(Unicode.TableTitle)
            case "N", "Number":            .addTable(Unicode.TableNumber)
            case "Nd", "Decimal_Number":   .addTable(Unicode.TableDigit)
            case "S", "Symbol":            .addTable(Unicode.TableSymbol)
            case "Sm", "Math_Symbol":      .addTable(Unicode.TableSymbolMath)
            case "Z", "Separator":         .addTable(Unicode.TableSeparator)
            case "White_Space":            .addTable(Unicode.TableWhiteSpace)
            default: return result
            }

            .normalize()
        }

        result.known = true
        return result
    }
}

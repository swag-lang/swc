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

// The largest scalar value, so a negation has a bound.
const MaxRune = 0x10FFFF'rune

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
        for r in other.ranges do
            .ranges.add(r)
    }

    // Adds a Unicode table, expanding the strided entries the tables use for scattered blocks.
    mtd addTable(table: const [..] Unicode.Range)
    {
        for &r in table
        {
            if r.stride == 1
            {
                .ranges.add({r.lo, r.hi})
                continue
            }

            var c = r.lo
            while c <= r.hi
            {
                .ranges.add({c, c})
                c += r.stride
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

        var write = 0'u64
        for var read = 1'u64; read < .ranges.count; read += 1
        {
            let cur = .ranges[read]
            if cur.lo <= .ranges[write].hi + 1
            {
                if cur.hi > .ranges[write].hi do
                    .ranges[write].hi = cur.hi
                continue
            }

            write          += 1
            .ranges[write] = cur
        }

        .ranges.resize(write + 1)
    }

    // Replaces the class with its complement over the whole scalar range.
    mtd negate()
    {
        .normalize()

        var result: Array'RuneRange
        var next = 0'rune
        for &r in .ranges
        {
            if r.lo > next do
                result.add({next, r.lo - 1})
            if r.hi >= MaxRune
            {
                .ranges = #move result
                return
            }

            next = r.hi + 1
        }

        result.add({next, MaxRune})
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
        for &r in .ranges
        {
            if r.hi - r.lo >= WidestFoldedRange do
                continue

            var c = r.lo
            while c <= r.hi
            {
                let upper = Unicode.toUpper(c)
                let lower = Unicode.toLower(c)
                if upper != c do
                    folded.addRune(upper)
                if lower != c do
                    folded.addRune(lower)
                c += 1
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
            let mid = (low + high) / 2
            let r   = .ranges[mid]
            if value < r.lo do
                high = mid
            elif value > r.hi do
                low = mid + 1
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

        switch name
        {
        case "digit":
            result.value.add('0', '9')

        case "xdigit":
            result.value.add('0', '9')
            result.value.add('a', 'f')
            result.value.add('A', 'F')

        case "alpha":
            result.value.add('a', 'z')
            result.value.add('A', 'Z')

        case "alnum":
            result.value.add('0', '9')
            result.value.add('a', 'z')
            result.value.add('A', 'Z')

        case "lower":
            result.value.add('a', 'z')

        case "upper":
            result.value.add('A', 'Z')

        case "blank":
            result.value.addRune(' ')
            result.value.addRune('\t')

        case "space":
            result.value.add('\t', '\r')
            result.value.addRune(' ')

        case "word":
            result.value.add('0', '9')
            result.value.add('a', 'z')
            result.value.add('A', 'Z')
            result.value.addRune('_')

        case "ascii":
            result.value.add(0, 0x7F)

        case "punct":
            result.value.add('!', '/')
            result.value.add(':', '@')
            result.value.add('[', '`')
            result.value.add('{', '~')

        case "cntrl":
            result.value.add(0, 0x1F)
            result.value.addRune(0x7F)

        case "graph":
            result.value.add('!', '~')

        case "print":
            result.value.add(' ', '~')

        default:
            return result
        }

        result.value.normalize()
        result.known = true
        return result
    }

    // Returns the class of one Unicode property name, or an empty result when the name is
    // not a supported property.
    func unicodeProperty(name: string)->{ value: RuneClass, known: bool }
    {
        var result: retval

        switch name
        {
        case "L", "Letter":                   result.value.addTable(Unicode.TableLetter)
        case "Ll", "Lowercase_Letter":        result.value.addTable(Unicode.TableLower)
        case "Lu", "Uppercase_Letter":        result.value.addTable(Unicode.TableUpper)
        case "Lt", "Titlecase_Letter":        result.value.addTable(Unicode.TableTitle)
        case "N", "Number":                   result.value.addTable(Unicode.TableNumber)
        case "Nd", "Decimal_Number":          result.value.addTable(Unicode.TableDigit)
        case "S", "Symbol":                   result.value.addTable(Unicode.TableSymbol)
        case "Sm", "Math_Symbol":             result.value.addTable(Unicode.TableSymbolMath)
        case "Z", "Separator", "White_Space": result.value.addTable(Unicode.TableWhiteSpace)
        default:                              return result
        }

        result.value.normalize()
        result.known = true
        return result
    }
}

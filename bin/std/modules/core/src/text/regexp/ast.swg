#global namespace Parser.Regex
#global internal

using Errors

// What a node of the pattern tree is.
enum NodeKind
{
    Empty         // Matches the empty string.
    Literal       // One scalar value.
    Class         // One set of scalar values.
    Concat        // Its children, in order.
    Alternate     // Its children, first match wins.
    Repeat        // Its single child, between 'minCount' and 'maxCount' times.
    Group         // Its single child, capturing when 'capture' is not zero.
    Assert        // A zero-width assertion.
    Backref       // What capture group 'reference' matched.
}

// A zero-width assertion, resolved from the bytes around a position.
enum AssertKind
{
    StartText           // Start of the subject.
    EndText             // End of the subject.
    StartLine           // Start of the subject, or just after a line feed.
    EndLine             // End of the subject, or just before a line feed.
    WordBoundary        // Between a word scalar value and a non-word one.
    NotWordBoundary     // Anywhere a word boundary is not.
}

// One node of the pattern tree. Children live in 'Ast.kids', so a node is a plain value.
struct Node
{
    kind:       NodeKind       // What this node is.
    value:      rune           // Literal: the scalar value.
    classIndex: u32            // Class: index into 'Ast.classes'.
    assertion:  AssertKind     // Assert: which assertion.
    minCount:   u32            // Repeat: smallest number of repetitions.
    maxCount:   u32            // Repeat: largest number of repetitions, 'RepeatInfinite' when unbounded.
    reference:  u32            // Backref: the capture group it refers to.
    capture:    u32            // Group: the capture index, zero when the group does not capture.
    first:      u32            // Index of the first child in 'Ast.kids'.
    count:      u32            // Number of children.
    greedy:     bool           // Repeat: whether it prefers to consume more.
}

// An unbounded repetition, as 'maxCount'.
const RepeatInfinite = 0xFFFF_FFFF'u32

// The most repetitions a counted form may unroll into, because '{n,m}' compiles by unrolling.
const MaxRepeatCount = 1000'u32

// Which spellings of the same scalar value a pattern accepts, and what '.' and the line
// assertions mean.
struct Flags
{
    ignoreCase: bool            // Whether a literal and a class match both cases.
    multiline:  bool            // Whether '^' and '$' also match around a line feed.
    dotAll:     bool = true     // Whether '.' also matches a line feed.
}

// The parsed form of a pattern.
//
// The tree is stored as three flat arrays rather than as linked values: a node names its
// children by a range of 'kids', and a class by an index into 'classes'. Building the program
// then walks the tree without following a single pointer, and the whole tree is released in
// three deallocations.
struct Ast
{
    nodes:        Array'Node          // Every node; 'root' names the top one.
    kids:         Array'u32           // Child lists, each named by a node's 'first' and 'count'.
    classes:      Array'RuneClass     // The classes the 'Class' nodes point at.
    captureNames: Array'String        // Name of each capture group, empty when it has none.
    root:         u32                 // Index of the root node.
    captureCount: u32                 // Number of capturing groups.
    ignoreCase:   bool                // Whether the pattern was parsed without case, which a backreference also obeys.
    hasBackref:   bool                // Whether a backreference appears anywhere.

    // Parse state, kept here so the tree and its cursor are one value.
    private
    {
        pattern: Array'rune     // The pattern, as scalar values.
        pos:     u64            // Reading position in 'pattern'.
        flags:   Flags          // Flags in effect at the reading position.
    }
}

impl Ast
{
    // Parses one pattern into a tree.
    func parse(pattern: string, flags: Flags)->Ast fail
    {
        var result: retval

        result.pattern    = Unicode.fromUtf8(pattern)
        result.flags      = flags
        result.ignoreCase = flags.ignoreCase

        // Capture zero is the whole match, and it has no name.
        result.captureNames.add(String{})

        result.root = result.parseAlternate()
        if !result.atEnd()
        {
            if result.peek() == ')' do
                fail SyntaxError{"unexpected ')'"}
            fail SyntaxError{"unexpected character"}
        }

        return result
    }

    //
    // Reading the pattern.
    //

    mtd const atEnd() => .pos >= .pattern.count

    mtd const peek()->rune
    {
        if .pos >= .pattern.count do
            return 0
        return .pattern[.pos]
    }

    mtd const peekAt(offset: u64)->rune
    {
        if .pos + offset >= .pattern.count do
            return 0
        return .pattern[.pos + offset]
    }

    mtd advance()
    {
        .pos += 1
    }

    mtd eat(value: rune)->bool
    {
        if .peek() != value or .atEnd() do
            return false
        .advance()
        return true
    }

    //
    // Building nodes.
    //

    mtd addNode(node: Node)->u32
    {
        .nodes.add(node)
        return cast(u32) .nodes.count - 1
    }

    mtd addChildren(children: const [..] u32)->{ first: u32, count: u32 }
    {
        var result: retval
        result.first = cast(u32) .kids.count
        result.count = cast(u32) children.count
        .kids.add(children)
        return result
    }

    mtd addChild(child: u32)->{ first: u32, count: u32 }
    {
        var result: retval
        result.first = cast(u32) .kids.count
        result.count = 1
        .kids.add(child)
        return result
    }

    // Wraps a list of nodes into one node of 'kind', collapsing the trivial cases.
    mtd addList(kind: NodeKind, children: const [..] u32)->u32
    {
        if children.count == 0 do
            return .addNode({kind: .Empty})
        if children.count == 1 do
            return children[0]

        let range = .addChildren(children)
        return .addNode({kind: kind, first: range.first, count: range.count})
    }

    // Adds a class node, folding case when the flags ask for it.
    mtd addClassNode(value: RuneClass)->u32
    {
        var cls = value
        if .flags.ignoreCase do
            cls.foldCase()
        else do
            cls.normalize()

        // A class holding one scalar value is a literal, which is what literal extraction
        // and the prefilters look for.
        if cls.ranges.count == 1 and cls.ranges[0].lo == cls.ranges[0].hi do
            return .addNode({kind: .Literal, value: cls.ranges[0].lo})

        .classes.add(cls)
        return .addNode({kind: .Class, classIndex: cast(u32) .classes.count - 1})
    }

    // Adds a class node whose case folding is already done, so a negated class is not
    // folded a second time — which would put back the very values the negation removed.
    mtd addFinalClassNode(value: RuneClass)->u32
    {
        var cls = value
        cls.normalize()

        if cls.ranges.count == 1 and cls.ranges[0].lo == cls.ranges[0].hi do
            return .addNode({kind: .Literal, value: cls.ranges[0].lo})

        .classes.add(cls)
        return .addNode({kind: .Class, classIndex: cast(u32) .classes.count - 1})
    }

    // Adds a literal node, which becomes a class when the flags fold its case.
    mtd addLiteralNode(value: rune)->u32
    {
        if !.flags.ignoreCase do
            return .addNode({kind: .Literal, value: value})

        var cls: RuneClass
        cls.addRune(value)
        return .addClassNode(cls)
    }

    //
    // The grammar.
    //

    mtd parseAlternate()->u32 fail
    {
        var branches: Array'u32
        branches.add(.parseConcat())

        while .peek() == '|' and !.atEnd()
        {
            .advance()
            branches.add(.parseConcat())
        }

        return .addList(.Alternate, branches.toSlice())
    }

    mtd parseConcat()->u32 fail
    {
        var items: Array'u32
        while !.atEnd() and .peek() != '|' and .peek() != ')'
        {
            let item = .parseRepeat()
            if item != NoNode do
                items.add(item)
        }

        return .addList(.Concat, items.toSlice())
    }

    // Parses one item and the repetition operators applied to it.
    mtd parseRepeat()->u32 fail
    {
        var current = .parseSingle()
        if current == NoNode do
            return NoNode

        for
        {
            var minCount, maxCount: u32
            switch .peek()
            {
            case '*':
                .advance()
                minCount = 0
                maxCount = RepeatInfinite

            case '+':
                .advance()
                minCount = 1
                maxCount = RepeatInfinite

            case '?':
                .advance()
                minCount = 0
                maxCount = 1

            case '{':
                let counted = .parseCounted()
                if !counted.valid do
                    return current

                minCount = counted.minCount
                maxCount = counted.maxCount

            default:
                return current
            }

            if !.canRepeat(current) do
                fail SyntaxError{"nothing to repeat"}

            var greedy = true
            if .peek() == '?'
            {
                .advance()
                greedy = false
            }
            elif .peek() == '+'
            {
                // A possessive form would need atomic groups; reject it rather than
                // silently matching something else.
                fail SyntaxError{"possessive repetition is not supported"}
            }

            let range = .addChild(current)
            current = .addNode({kind: .Repeat, minCount: minCount, maxCount: maxCount, greedy: greedy, first: range.first, count: range.count})
        }

        return current
    }

    // Returns whether an item may carry a repetition operator. An assertion may not, so
    // '^*' is a syntax error rather than a silent no-op.
    mtd const canRepeat(node: u32)->bool
    {
        let kind = .nodes[node].kind
        return kind != NodeKind.Assert
    }

    // Parses '{n}', '{n,}' or '{n,m}'. An opening brace that does not spell one of those is
    // not a repetition, and the caller turns it into a literal.
    mtd parseCounted()->{ valid: bool, minCount: u32, maxCount: u32 } fail
    {
        var result: retval
        let start = .pos

        .advance()
        if !.isDigit(.peek())
        {
            .pos = start
            return result
        }

        result.minCount = .parseNumber()
        result.maxCount = result.minCount

        if .peek() == ','
        {
            .advance()
            if .isDigit(.peek()) do
                result.maxCount = .parseNumber()
            else do
                result.maxCount = RepeatInfinite
        }

        if .peek() != '}'
        {
            .pos = start
            return result
        }

        .advance()

        if result.maxCount != RepeatInfinite and result.maxCount < result.minCount do
            fail SyntaxError{"repetition range is empty, the low bound is above the high one"}
        if result.minCount > MaxRepeatCount or (result.maxCount != RepeatInfinite and result.maxCount > MaxRepeatCount) do
            fail SyntaxError{"repetition count is too large"}

        result.valid = true
        return result
    }

    mtd const isDigit(value: rune) => value >= '0' and value <= '9'

    mtd parseNumber()->u32
    {
        var result: retval
        while .isDigit(.peek()) and result <= MaxRepeatCount
        {
            result = result * 10 + cast(u32) (.peek() - '0')
            .advance()
        }

        return result
    }

    // Parses one item. Returns 'NoNode' when the construct produces nothing, as an inline
    // flag group does.
    mtd parseSingle()->u32 fail
    {
        switch .peek()
        {
        case '(':
            return .parseGroup()

        case '[':
            return .addClassNode(.parseClass())

        case '.':
            .advance()
            var cls: RuneClass
            cls.add(0, MaxRune)
            if !.flags.dotAll
            {
                cls.negate()
                cls.addRune('\n')
                cls.negate()
            }

            .classes.add(cls)
            return .addNode({kind: .Class, classIndex: cast(u32) .classes.count - 1})

        case '^':
            .advance()
            return .addNode({kind: .Assert, assertion: .flags.multiline ? AssertKind.StartLine : AssertKind.StartText})

        case '$':
            .advance()
            return .addNode({kind: .Assert, assertion: .flags.multiline ? AssertKind.EndLine : AssertKind.EndText})

        case '\\':
            return .parseEscape()

        case '*', '+', '?':
            fail SyntaxError{"nothing to repeat"}

        case '{':

            // A repetition with nothing in front of it is a mistake; a brace that does not
            // spell one is just a brace.
            let counted = .parseCounted()
            if counted.valid do
                fail SyntaxError{"nothing to repeat"}
            .advance()
            return .addLiteralNode('{')

        case ')':
            fail SyntaxError{"unexpected ')'"}

        case ']':
            fail SyntaxError{"unmatched ']'"}
        }

        let value = .peek()
        .advance()
        return .addLiteralNode(value)
    }

    mtd parseGroup()->u32 fail
    {
        .advance()

        let savedFlags = .flags
        var capture    = 0'u32
        var name: String

        if .peek() == '?'
        {
            .advance()
            switch .peek()
            {
            case ':':
                .advance()

            case '<', '\'':
                if .peek() == '<' and (.peekAt(1) == '=' or .peekAt(1) == '!') do
                    fail SyntaxError{"look-around is not supported"}
                name    = .parseGroupName()
                capture = .newCapture(name)

            case 'P':
                .advance()
                if .peek() != '<' do
                    fail SyntaxError{"expected '<' after '(?P'"}
                name    = .parseGroupName()
                capture = .newCapture(name)

            case '=', '!':
                fail SyntaxError{"look-around is not supported"}

            default:

                // Inline flags, either scoped to the enclosing group or to this one.
                if !.parseInlineFlags() do
                    fail SyntaxError{"invalid group modifier"}

                // A flag group with no body sets the flags for the rest of the enclosing
                // group, so the saved ones must not come back here.
                if .eat(')') do
                    return NoNode

                if !.eat(':') do
                    fail SyntaxError{"expected ':' or ')' after inline flags"}
            }
        }
        else
        {
            capture = .newCapture(String{})
        }

        let inner = .parseAlternate()
        if !.eat(')') do
            fail SyntaxError{"missing ')'"}
        .flags = savedFlags

        let range = .addChild(inner)
        return .addNode({kind: .Group, capture: capture, first: range.first, count: range.count})
    }

    mtd newCapture(name: String)->u32
    {
        .captureCount += 1
        .captureNames.add(name)
        return .captureCount
    }

    mtd parseGroupName()->String fail
    {
        let closing = .peek() == '\'' ? '\'' : '>'
        .advance()

        var result: retval
        while !.atEnd() and .peek() != closing
        {
            result.append(.peek())
            .advance()
        }

        if !.eat(closing) do
            fail SyntaxError{"unterminated capture group name"}
        if result.isEmpty() do
            fail SyntaxError{"empty capture group name"}
        return result
    }

    // Reads the letters of an inline flag group, up to its ')' or ':'.
    mtd parseInlineFlags()->bool
    {
        var negate = false
        var seen   = false

        for
        {
            switch .peek()
            {
            case 'i':
                .flags.ignoreCase = !negate

            case 'm':
                .flags.multiline = !negate

            case 's':
                .flags.dotAll = !negate

            case '-':
                if negate do
                    return false
                negate = true

            case ')', ':':
                return seen or negate

            default:
                return false
            }

            seen = true
            .advance()
        }

        return false
    }

    //
    // Escapes.
    //

    mtd parseEscape()->u32 fail
    {
        .advance()
        if .atEnd() do
            fail SyntaxError{"pattern ends with a backslash"}

        let value = .peek()
        switch value
        {
        case 'A':
            .advance()
            return .addNode({kind: .Assert, assertion: AssertKind.StartText})

        case 'z':
            .advance()
            return .addNode({kind: .Assert, assertion: AssertKind.EndText})

        case 'b':
            .advance()
            return .addNode({kind: .Assert, assertion: AssertKind.WordBoundary})

        case 'B':
            .advance()
            return .addNode({kind: .Assert, assertion: AssertKind.NotWordBoundary})

        case '1', '2', '3', '4', '5', '6', '7', '8', '9':
            .advance()
            .hasBackref = true
            return .addNode({kind: .Backref, reference: cast(u32) (value - '0')})
        }

        let cls = .parseClassEscape()
        if cls.isClass do
            return .addClassNode(cls.value)
        return .addLiteralNode(cls.scalar)
    }

    // Parses the escape sequences that mean a class or a single scalar value, which are the
    // ones a character class also accepts. The cursor is on the character after the backslash.
    mtd parseClassEscape()->{ isClass: bool, value: RuneClass, scalar: rune } fail
    {
        var result: retval

        let value = .peek()
        switch value
        {
        case 'd', 'D', 'w', 'W', 's', 'S', 'l', 'L', 'u', 'U':
            .advance()
            result.isClass = true
            result.value   = .shorthandClass(value)
            return result

        case 'p', 'P':
            .advance()
            result.isClass = true
            result.value   = .parseUnicodeClass(value == 'P')
            return result

        case 'a':
            .advance()
            result.scalar = '\a'
            return result

        case 'e':
            .advance()
            result.scalar = 0x1B
            return result

        case 'f':
            .advance()
            result.scalar = '\f'
            return result

        case 'n':
            .advance()
            result.scalar = '\n'
            return result

        case 'r':
            .advance()
            result.scalar = '\r'
            return result

        case 't':
            .advance()
            result.scalar = '\t'
            return result

        case 'v':
            .advance()
            result.scalar = '\v'
            return result

        case '0':
            .advance()
            result.scalar = 0
            return result

        case 'x':
            .advance()
            result.scalar = .parseHexEscape()
            return result
        }

        // Any other escaped punctuation is that character. An escaped letter or digit that
        // is not one of the sequences above is a mistake, not a literal.
        if (value >= 'a' and value <= 'z') or (value >= 'A' and value <= 'Z') or (value >= '0' and value <= '9') do
            fail SyntaxError{"unknown escape sequence"}

        .advance()
        result.scalar = value
        return result
    }

    // Parses '\xHH' and '\x{H...}'; the cursor is just after the 'x'.
    mtd parseHexEscape()->rune fail
    {
        var value = 0'u32

        if .eat('{')
        {
            var digits = 0
            while !.atEnd() and .peek() != '}'
            {
                value  = value * 16 + .hexDigit(.peek())
                digits += 1
                .advance()
            }

            if digits == 0 or digits > 6 do
                fail SyntaxError{"invalid hexadecimal escape"}
            if !.eat('}') do
                fail SyntaxError{"unterminated hexadecimal escape"}
        }
        else
        {
            for 2
            {
                value = value * 16 + .hexDigit(.peek())
                .advance()
            }
        }

        if value > MaxRune do
            fail SyntaxError{"hexadecimal escape is above the largest scalar value"}
        return cast(rune) value
    }

    mtd hexDigit(value: rune)->u32 fail
    {
        if value >= '0' and value <= '9' do
            return cast(u32) (value - '0')
        if value >= 'a' and value <= 'f' do
            return cast(u32) (value - 'a') + 10
        if value >= 'A' and value <= 'F' do
            return cast(u32) (value - 'A') + 10
        fail SyntaxError{"invalid hexadecimal escape"}
    }

    // Returns the class of a one-letter shorthand, negated for its upper-case spelling.
    mtd shorthandClass(letter: rune)->RuneClass
    {
        var result: retval

        switch letter
        {
        case 'd', 'D': result = RuneClass.posix("digit").value
        case 'w', 'W': result = RuneClass.posix("word").value
        case 's', 'S': result = RuneClass.posix("space").value
        case 'l', 'L': result = RuneClass.posix("lower").value
        case 'u', 'U': result = RuneClass.posix("upper").value
        }

        if letter == 'D' or letter == 'W' or letter == 'S' or letter == 'L' or letter == 'U' do
            result.negate()
        return result
    }

    // Parses '\pL', '\p{Lu}' and their negated '\P' spellings; the cursor is just after
    // the letter.
    mtd parseUnicodeClass(negated: bool)->RuneClass fail
    {
        var name: String

        if .eat('{')
        {
            while !.atEnd() and .peek() != '}'
            {
                name.append(.peek())
                .advance()
            }

            if !.eat('}') do
                fail SyntaxError{"unterminated Unicode property name"}
        }
        else
        {
            if .atEnd() do
                fail SyntaxError{"missing Unicode property name"}
            name.append(.peek())
            .advance()
        }

        let found = RuneClass.unicodeProperty(name.toString())
        if !found.known do
            fail SyntaxError{"unknown Unicode property"}

        var result = found.value
        if negated do
            result.negate()
        return result
    }

    //
    // Character classes.
    //

    mtd parseClass()->RuneClass fail
    {
        .advance()

        var result: retval
        var negated = .eat('^')
        var first   = true

        while !.atEnd() and (.peek() != ']' or first)
        {
            first = false

            // A POSIX class, which is the only construct nested brackets may spell.
            if .peek() == '[' and .peekAt(1) == ':'
            {
                result.addClass(.parsePosixClass())
                continue
            }

            let low = .parseClassItem()
            if low.isClass
            {
                if .peek() == '-' and .peekAt(1) != ']' and .peekAt(1) != 0 do
                    fail SyntaxError{"a class cannot be the bound of a range"}
                result.addClass(low.value)
                continue
            }

            // A range, unless the '-' is the last character of the class.
            if .peek() == '-' and .peekAt(1) != ']' and .peekAt(1) != 0
            {
                .advance()
                let high = .parseClassItem()
                if high.isClass do
                    fail SyntaxError{"a class cannot be the bound of a range"}

                var lo = low.scalar
                var hi = high.scalar
                if lo > hi do
                    swap(&lo, &hi)
                result.add(lo, hi)
                continue
            }

            result.addRune(low.scalar)
        }

        if !.eat(']') do
            fail SyntaxError{"unterminated '['"}

        // Case folding happens before the negation: '[^a]' with case folding must reject
        // both spellings of the letter, not accept the other one.
        if .flags.ignoreCase do
            result.foldCase()
        else do
            result.normalize()
        if negated do
            result.negate()

        return result
    }

    // Parses one member of a character class: a scalar value or a nested class.
    mtd parseClassItem()->{ isClass: bool, value: RuneClass, scalar: rune } fail
    {
        if .peek() != '\\'
        {
            var result: retval
            result.scalar = .peek()
            .advance()
            return result
        }

        .advance()
        if .atEnd() do
            fail SyntaxError{"pattern ends with a backslash"}

        // Inside a class, '\b' is a backspace rather than a word boundary.
        if .peek() == 'b'
        {
            .advance()
            var result: retval
            result.scalar = 0x08
            return result
        }

        return .parseClassEscape()
    }

    mtd parsePosixClass()->RuneClass fail
    {
        // Skip '[:'.
        .advance()
        .advance()

        let negated = .eat('^')

        var name: String
        while !.atEnd() and .peek() != ':' and .peek() != ']'
        {
            name.append(.peek())
            .advance()
        }

        if !.eat(':') or !.eat(']') do
            fail SyntaxError{"unterminated POSIX character class"}

        let found = RuneClass.posix(name.toString())
        if !found.known do
            fail SyntaxError{"unknown POSIX character class"}

        var result = found.value
        if negated do
            result.negate()
        return result
    }
}

// Facts about the tree that the program compiler and the search need before compiling.
impl Ast
{
    // Whether every way of matching begins at the start of the subject, which lets a search
    // give up after one attempt instead of walking the whole subject.
    mtd const startsAnchored()->bool => .nodeStartsAnchored(.root)

    mtd const nodeStartsAnchored(node: u32)->bool
    {
        let current = .nodes[node]
        switch current.kind
        {
        case .Assert:
            return current.assertion == AssertKind.StartText

        case .Group:
            return .nodeStartsAnchored(.kids[current.first])

        case .Repeat:
            return current.minCount > 0 and .nodeStartsAnchored(.kids[current.first])

        case .Concat:
            return current.count > 0 and .nodeStartsAnchored(.kids[current.first])

        case .Alternate:
            for var i = 0'u32; i < current.count; i += 1
            {
                if !.nodeStartsAnchored(.kids[current.first + i]) do
                    return false
            }

            return current.count > 0
        }

        return false
    }

    // Shortest match of one node, in bytes. A lower bound is enough: it only ever stops a
    // search that could not have matched anyway.
    mtd const minLength(node: u32)->u32
    {
        const Ceiling = 0xFFFF'u32

        let current = .nodes[node]
        switch current.kind
        {
        case .Literal:
            return encodedLength(current.value)

        case .Class:
            var shortest = Ceiling
            for &r in .classes[current.classIndex].ranges
            {
                let length = encodedLength(r.lo)
                if length < shortest do
                    shortest = length
            }

            return shortest == Ceiling ? 0 : shortest

        case .Group:
            return .minLength(.kids[current.first])

        case .Repeat:
            let inner = .minLength(.kids[current.first])
            let total = cast(u64) inner * current.minCount
            return total > Ceiling ? Ceiling : cast(u32) total

        case .Concat:
            var total = 0'u32
            for var i = 0'u32; i < current.count; i += 1
            {
                total += .minLength(.kids[current.first + i])
                if total > Ceiling do
                    return Ceiling
            }

            return total

        case .Alternate:
            var shortest = Ceiling
            for var i = 0'u32; i < current.count; i += 1
            {
                let length = .minLength(.kids[current.first + i])
                if length < shortest do
                    shortest = length
            }

            return current.count == 0 ? 0 : shortest
        }

        return 0
    }
}

// A literal that every match must contain, and the part of the pattern that precedes it.
impl Ast
{
    // Finds a literal run inside the pattern that every match has to contain, and builds the
    // node for everything before it.
    //
    // This is what lets a search skip over the parts of a subject that cannot hold a match
    // even though the pattern does not begin with a literal: `[a-z]+@[a-z.]+` has no usable
    // first byte — a match can begin with any letter — but every match contains an `@`, and
    // ordinary text holds very few of those.
    //
    // Only a run of literals directly inside the top-level concatenation qualifies: those are
    // the ones no repetition or alternation can make optional.
    mtd extractInnerLiteral()->{ found: bool, bytes: Array'u8, prefixRoot: u32 }
    {
        var result: retval

        let rootNode = .nodes[.root]
        if rootNode.kind != NodeKind.Concat do
            return result

        var bestStart = 0'u32
        var bestEnd   = 0'u32
        var bestScore = 0xFFFF'u32

        var index = 1'u32
        while index < rootNode.count
        {
            if .nodes[.kids[rootNode.first + index]].kind != NodeKind.Literal
            {
                index += 1
                continue
            }

            var last = index
            while last + 1 < rootNode.count and .nodes[.kids[rootNode.first + last + 1]].kind == NodeKind.Literal do
                last += 1

            let score = .literalRunScore(rootNode, index, last)
            if score < bestScore
            {
                bestScore = score
                bestStart = index
                bestEnd   = last
            }

            index = last + 1
        }

        if bestScore == 0xFFFF do
            return result

        var buffer: [4] u8
        for var i = bestStart; i <= bestEnd; i += 1
        {
            let value = .nodes[.kids[rootNode.first + i]].value
            let count = Utf8.encodeRune(buffer, value)
            for var b = 0'u32; b < count; b += 1 do
                result.bytes.add(buffer[b])
        }

        // The part of the pattern before the literal, as one node.
        var prefixKids: Array'u32
        for var i = 0'u32; i < bestStart; i += 1 do
            prefixKids.add(.kids[rootNode.first + i])

        result.prefixRoot = .addList(.Concat, prefixKids.toSlice())
        result.found      = true
        return result
    }

    // How often a run of literals is expected to appear in ordinary text, per thousand bytes.
    // A rarer run is a better place to look.
    mtd const literalRunScore(rootNode: Node, first, last: u32)->u32
    {
        var rarest = 0xFFFF'u32
        var second = 0xFFFF'u32

        var buffer: [4] u8
        for var i = first; i <= last; i += 1
        {
            let value = .nodes[.kids[rootNode.first + i]].value
            let count = Utf8.encodeRune(buffer, value)
            for var b = 0'u32; b < count; b += 1
            {
                let score = cast(u32) ByteFrequency[buffer[b]]
                if score < rarest
                {
                    second = rarest
                    rarest = score
                }
                elif score < second do
                    second = score
            }
        }

        if second == 0xFFFF do
            return rarest

        // Two bytes are compared at once, so what stops the scan is the pair.
        let paired = (rarest * second) / 1000
        return paired < 1 ? 1 : paired
    }
}

// The index that means "no node at all".
const NoNode = 0xFFFF_FFFF'u32

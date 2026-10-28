#global internal
#global namespace Pipeline

using Core, Pixel

/*
What the compiler printed about the inspected function, read as a story.

An inspecting build prints the function once per offered stage, and a pass the optimizer runs
several times prints it each time, in the order the passes ran. Swag Prism keeps every printing as
a [[Snapshot]], and reads the story from them: the listing of a stage is the last time that pass
left the function, and the steps of the frieze are the printings that changed something.
*/
struct Inspection
{
    snapshots: Array'Snapshot     // Every printing of the function, in the order the passes ran.
    steps:     Array'u64          // Printings that changed the code, with the first and the last.
    report:    Array'String       // The compiler's own lines about the build: what it checked, tuned, forged.
}

// One printing of the inspected function.
struct Snapshot
{
    stage:        u32 = Swag.U32.Max     // Index of the printing's stage in [[Stages]], or `U32.Max` for another name.
    function:     String                 // Name of the function, as the compiler qualifies it.
    location:     String                 // Where the function is declared.
    optimize:     String                 // The compiler's summary of the optimization level and its gain.
    lines:        Array'ListingLine      // Instructions, labels and source lines, in the order printed.
    instructions: u32                    // Number of instructions as the compiler counts them: labels in, source lines out.
}

// What one line of a listing is.
enum ListingLineKind
{
    Instruction     // An instruction of the backend.
    Label           // A place a jump lands on.
    Source          // The line of source the instructions after it come from.
}

// One line of a listing, cut into the parts Swag Prism can show apart.
struct ListingLine
{
    kind:     ListingLineKind
    id:       String          // Identity of an instruction or a label, kept from stage to stage; number of a source line.
    opcode:   ColoredText     // The instruction as the backend spells it.
    operands: ColoredText     // Its operands, as the backend spells them.
    readable: ColoredText     // The instruction as a reader writes it, the name of a label, or the source line.
    target:   String          // Label a jump goes to, or empty.
}

// A piece of compiler text with the colors the compiler gave it.
struct ColoredText
{
    text: String
    runs: Array'TextRun
}

// A span of a [[ColoredText]] drawn in one color.
struct TextRun
{
    start, end: u64       // Byte range of the span in the text.
    color:      Color     // The compiler's color, or zero to follow the theme.
}

// How a line of a compared listing stands against the stage before it.
enum DiffMark
{
    Same        // The line is in both stages.
    Removed     // The line was in the stage before and is not any more.
    Added       // The line is new in this stage.
}

// One line of a compared listing.
struct DiffLine
{
    line:   const *ListingLine
    mark:   DiffMark
    number: u32 = Swag.U32.Max     // Place of the line among the instructions and labels of its stage; `U32.Max` for a source line.
}

// A stage compared with the stage before it: the merged lines, and what changed.
struct Difference
{
    lines:   Array'DiffLine
    removed: u32
    added:   u32
}

// The innermost loop of a listing: from the label a backward jump goes to, to that jump.
struct LoopRange
{
    first:        u64 = Swag.U64.Max     // Line of the label, or `U64.Max` when the listing has no loop.
    last:         u64 = Swag.U64.Max     // Line of the jump back.
    instructions: u32     // Instructions in the loop, counted as the compiler counts them.
}

impl ColoredText
{
    // Appends the bytes `start until end` of `output`, with the colors of the runs they cross.
    //
    // `cursor` is the first run that can still reach the text; pieces are appended in the order
    // of the output, so the runs before it are never looked at again.
    mtd append(output: const *CompilerOutput, start, end: u64, cursor: *u64)
    {
        if end <= start do
            return

        let base = .text.length
        .text.append(output.text.toString()[start until end])
        while cursor[] < output.runs.count and output.runs[cursor[]].end <= start do
            cursor[] += 1

        var index = cursor[]
        while index < output.runs.count and output.runs[index].start < end
        {
            let run = output.runs[index]
            var color: Color
            if run.style do
                color = output.colors[run.style - 1]
            .runs.add(TextRun{base + Math.max(run.start, start) - start, base + Math.min(run.end, end) - start, color})
            index += 1
        }
    }

    // Appends `text` in the color of the theme.
    mtd appendPlain(text: string)
    {
        let base = .text.length
        .text.append(text)
        .runs.add(TextRun{start: base, end: .text.length})
    }
}

impl ListingLine
{
    // Returns what tells two lines apart when two stages are compared: an instruction by what it
    // does, a label by its name. Where the line sits and its identity are not part of it.
    mtd const key()->String
    {
        var result: #returntype
        if .kind == .Label
        {
            result.append(":")
            result.append(.id)
            return result
        }

        result.append(.opcode.text)
        result.append(" ")
        result.append(.operands.text)
        return result
    }
}

impl Snapshot
{
    // Returns whether `other` holds the same instructions and labels, in the same order.
    mtd const sameCode(other: const *Snapshot)->bool
    {
        var mine, theirs: u64
        for
        {
            while mine < .lines.count and .lines[mine].kind == .Source do
                mine += 1
            while theirs < other.lines.count and other.lines[theirs].kind == .Source do
                theirs += 1
            if mine == .lines.count or theirs == other.lines.count do
                return mine == .lines.count and theirs == other.lines.count
            if .lines[mine].key() != other.lines[theirs].key() do
                return false
            mine, theirs += 1
        }
    }

    // Returns the innermost loop: the shortest stretch from a label to a jump back to it.
    mtd const innermostLoop()->LoopRange
    {
        var result: #returntype
        for line, index in .lines where line.kind == .Instruction and not line.target.isEmpty()
        {
            for back in reversed(index) where .lines[back].kind == .Label and .lines[back].id == line.target
            {
                if result.first == Swag.U64.Max or index - back < result.last - result.first
                {
                    result.first = back
                    result.last  = index
                }

                break
            }
        }

        if result.first != Swag.U64.Max
        {
            for index in result.first to result.last where .lines[index].kind != .Source do
                result.instructions += 1
        }

        return result
    }
}

impl Inspection
{
    // Reads what the compiler printed for an inspecting build, colors included.
    func parse(output: string)->Inspection
    {
        var result:  #returntype
        var colored: CompilerOutput
        colored.parse(output)

        let text   = colored.text.toString()
        var cursor = 0'u64
        var current: *Snapshot?
        var header = false
        var start  = 0'u64
        while start < text.count
        {
            var end = Utf8.indexOf(text, '\n'rune, start)
            if end == Swag.U64.Max do
                end = text.count
            var stop = end
            if stop > start and text[stop - 1] == '\r' do
                stop -= 1
            let line = text[start until stop]

            // A printing opens on its marker, then names what it prints in `key : value` lines.
            if line == "[micro]"
            {
                result.snapshots.add({})
                current = result.snapshots.backPtr()
                header  = true
            }
            elif header and
                 current and
                 Utf8.startsWith(line, "  ") and
                 Utf8.indexOf(line, " : ") != Swag.U64.Max
            {
                let colon = Utf8.indexOf(line, " : ")
                let value = Latin1.trim(line[colon + 3 to])
                switch Latin1.trim(line[until colon])
                {
                case "stage":    current.stage = stageIndex(value)
                case "function": current.function = value
                case "location": current.location = value
                case "optimize": current.optimize = value
                }
            }
            elif current and line.count and Latin1.isDigit(line[0])
            {
                header = false
                readListingLine(current, &colored, start, line, &cursor)
            }
            else
            {
                // The listing ends on a blank line or on the next line the compiler writes about the
                // build, which goes to the report without its leading mark.
                header  = false
                current = null
                let words = Latin1.trim(line)
                let space = Utf8.indexOf(words, ' 'rune)
                if space != Swag.U64.Max do
                    result.report.add(Latin1.trim(words[space to]))
            }

            start = end + 1
        }

        for index in result.snapshots.count
        {
            if index == 0 or
               index == result.snapshots.count - 1 or
               not result.snapshots[index].sameCode(&result.snapshots[index - 1]) do
                result.steps.add(index)
        }

        return result
    }

    // Returns the last printing of the stage `stage`, or `U64.Max` when that pass never ran.
    mtd const lastOf(stage: u32)->u64
    {
        for index in reversed(.snapshots.count) where .snapshots[index].stage == stage do
            return index
        return Swag.U64.Max
    }

    // Returns the step in force at the printing `snapshot`: the last one printed before or at it.
    mtd const stepAt(snapshot: u64)->u64
    {
        for index in reversed(.steps.count) where .steps[index] <= snapshot do
            return index
        return 0
    }
}

// Returns the index of `name` in [[Stages]], or `U32.Max` for a name Swag Prism does not offer.
private func stageIndex(name: string)->u32
{
    for stage, index in Stages where stage == name do
        return cast(u32, index)
    return Swag.U32.Max
}

// Reads one numbered line of a printing: `<number> <id> <opcode> <operands> | <readable>` for an
// instruction, `<number> <id>` for a label, and `<number> <source>` for the source line the next
// instructions come from. `start` is where `line` starts in the parsed output.
private func readListingLine(snapshot: *Snapshot, output: const *CompilerOutput, start: u64, line: string, cursor: *u64)
{
    var number = 0'u64
    while number < line.count and Latin1.isDigit(line[number]) do
        number += 1
    if number == line.count or line[number] != ' ' do
        return

    let idStart = number + 1
    var idEnd   = idStart
    while idEnd < line.count and Latin1.isDigit(line[idEnd]) do
        idEnd += 1

    var result: ListingLine
    if idEnd == idStart or (idEnd < line.count and line[idEnd] != ' ')
    {
        result.kind = .Source
        result.id   = line[until number]
        result.readable.append(output, start + idStart, start + line.count, cursor)
        snapshot.lines.add(#move result)
        return
    }

    result.id = line[idStart until idEnd]
    var opcode = idEnd
    while opcode < line.count and line[opcode] == ' ' do
        opcode += 1
    if opcode == line.count
    {
        result.kind = .Label
        result.readable.append(output, start + idStart, start + idEnd, cursor)
        result.readable.appendPlain(":")
        snapshot.instructions += 1
        snapshot.lines.add(#move result)
        return
    }

    // The backend's spelling ends where the readable form starts, after the bar.
    result.kind = .Instruction
    var opcodeEnd = opcode
    while opcodeEnd < line.count and line[opcodeEnd] != ' ' do
        opcodeEnd += 1
    let bar         = Utf8.indexOf(line, " | ", opcodeEnd)
    var operandsEnd = bar == Swag.U64.Max ? line.count : bar
    while operandsEnd > opcodeEnd and line[operandsEnd - 1] == ' ' do
        operandsEnd -= 1

    result.opcode.append(output, start + opcode, start + opcodeEnd, cursor)
    if operandsEnd > opcodeEnd do
        result.operands.append(output, start + opcodeEnd + 1, start + operandsEnd, cursor)
    if bar == Swag.U64.Max do
        result.readable.append(output, start + opcode, start + operandsEnd, cursor)
    else do
        result.readable.append(output, start + bar + 3, start + line.count, cursor)

    // A jump names the label it lands on last.
    if Utf8.startsWith(result.opcode.text, "jump")
    {
        let operands = result.operands.text.toString()
        let space    = Utf8.lastIndexOf(operands, ' 'rune)
        let label    = space == Swag.U64.Max ? operands : operands[space + 1 to]
        var digits   = label.count != 0
        for index in label.count where not Latin1.isDigit(label[index]) do
            digits = false
        if digits do
            result.target = label
    }

    snapshot.instructions += 1
    snapshot.lines.add(#move result)
}

// The largest comparison table [[compare]] builds before it gives up marking the changes.
private const MaxDiffCells = 4_000_000'u64

/*
Compares a stage of one function with the stage before it.

The lines of `after` come back in order, with the lines of `before` it no longer has merged in
where they stood, and each line is marked. The instructions and labels of the two stages are
matched as the longest sequence they share, so a line that only moved reads as removed in one
place and added in the other — which is what the pass did. Source lines are not compared: they
come with the instructions after them.

Without `before`, or past [[MaxDiffCells]], every line of `after` comes back unmarked.
*/
func compare(before: const *Snapshot?, after: const *Snapshot)->Difference
{
    var result: #returntype

    var newLines: Array'u64
    var newKeys:  Array'String
    for line, index in after.lines where line.kind != .Source
    {
        newLines.add(index)
        newKeys.add(line.key())
    }

    var oldLines: Array'u64
    var oldKeys:  Array'String
    if before
    {
        for line, index in before.lines where line.kind != .Source
        {
            oldLines.add(index)
            oldKeys.add(line.key())
        }
    }

    let n = oldLines.count
    let m = newLines.count
    if not before or n * m > MaxDiffCells
    {
        var number = 0'u32
        for line in after.lines
        {
            if line.kind == .Source
            {
                result.lines.add(DiffLine{line, .Same})
            }
            else
            {
                result.lines.add(DiffLine{line, .Same, number})
                number += 1
            }
        }

        return result
    }

    // The length of the longest shared sequence of every pair of suffixes.
    let width = m + 1
    var table: Array'u32
    table.resize((n + 1) * width)
    for i in reversed(n)
    {
        for j in reversed(m)
        {
            if oldKeys[i] == newKeys[j] do
                table[i * width + j] = table[(i + 1) * width + j + 1] + 1
            else do
                table[i * width + j] = Math.max(table[(i + 1) * width + j], table[i * width + j + 1])
        }
    }

    // Walks the table, giving each source line of `after` its place before the next instruction.
    var i, j, next: u64
    while i < n or j < m
    {
        let same = i < n and j < m and oldKeys[i] == newKeys[j]
        if not same and i < n and (j == m or table[(i + 1) * width + j] >= table[i * width + j + 1])
        {
            result.lines.add(DiffLine{&before.lines[oldLines[i]], .Removed, cast(u32, i)})
            result.removed += 1
            i += 1
            continue
        }

        for index in next until newLines[j] do
            result.lines.add(DiffLine{&after.lines[index], .Same})
        result.lines.add(DiffLine{&after.lines[newLines[j]], same ? DiffMark.Same : DiffMark.Added, cast(u32, j)})
        next = newLines[j] + 1
        if same do
            i += 1
        else do
            result.added += 1
        j += 1
    }

    for index in next until after.lines.count do
        result.lines.add(DiffLine{&after.lines[index], .Same})
    return result
}

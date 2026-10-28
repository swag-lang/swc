#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Every printing of the function is read with its stage, its listing and its count; the steps are
// the printings that changed the code, the first and the last included.
#test
{
    let inspection = Pipeline.Inspection.parse(fixture("micro.dot.o2.txt"))
    Swag.assert(inspection.snapshots.count == 32)
    Swag.assert(inspection.snapshots[0].stage == 0 and inspection.snapshots[0].function == "Prismpreview.dot")
    Swag.assert(inspection.snapshots[0].optimize == "O2 (instr: 35 -> 35, gain: 0.00%)")
    Swag.assert(inspection.steps[0] == 0 and inspection.steps.back() == inspection.snapshots.count - 1)
    Swag.assert(inspection.steps.count > 2 and inspection.steps.count < inspection.snapshots.count)
    for index in 1 until inspection.steps.count - 1
    {
        let step = inspection.steps[index]
        Swag.assert(not inspection.snapshots[step].sameCode(&inspection.snapshots[step - 1]))
    }

    let finalStage = &inspection.snapshots[inspection.lastOf(Pipeline.DefaultStage)]
    Swag.assert(finalStage.instructions == 16)
    Swag.assert(inspection.stepAt(inspection.snapshots.count - 1) == inspection.steps.count - 1)
    Swag.assert(inspection.lastOf(Pipeline.Stages.count) == Swag.U64.Max)
    Swag.assert(not inspection.report.isEmpty())

    // An instruction keeps its colors, its readable form and its identity; a jump names its label.
    var jumps = 0'u64
    for line in finalStage.lines where line.kind == .Instruction
    {
        Swag.assert(not line.opcode.text.isEmpty() and not line.readable.text.isEmpty() and not line.id.isEmpty())
        Swag.assert(not line.readable.runs.isEmpty())
        if not line.target.isEmpty() do
            jumps += 1
    }

    Swag.assert(jumps != 0)
}

// A stage compared with the printing before it marks what the pass removed and added, and every
// line of the stage is in the merged listing once.
#test
{
    let inspection = Pipeline.Inspection.parse(fixture("micro.dot.o2.txt"))
    for index in 1 until inspection.steps.count
    {
        let after      = &inspection.snapshots[inspection.steps[index]]
        let before     = &inspection.snapshots[inspection.steps[index] - 1]
        let difference = Pipeline.compare(before, after)
        Swag.assert(difference.removed + difference.added != 0 or index == inspection.steps.count - 1)

        var kept, added, removed: u64
        for line in difference.lines
        {
            switch line.mark
            {
            case .Same:    kept += 1
            case .Added:   added += 1
            case .Removed: removed += 1
            }
        }

        Swag.assert(kept + added == after.lines.count and
                    added == difference.added and
                    removed == difference.removed)
    }

    // Alone, a stage comes back unmarked.
    let alone = Pipeline.compare(null, &inspection.snapshots[0])
    Swag.assert(alone.lines.count == inspection.snapshots[0].lines.count and
                alone.removed == 0 and
                alone.added == 0)
}

// The innermost loop runs from the label a jump goes back to, to that jump, and optimizing the dot
// product shortens it.
#test
{
    let optimized   = Pipeline.Inspection.parse(fixture("micro.dot.o2.txt"))
    let unoptimized = Pipeline.Inspection.parse(fixture("micro.dot.o0.txt"))
    let fast        = optimized.snapshots[optimized.lastOf(Pipeline.DefaultStage)].innermostLoop()
    let slow        = unoptimized.snapshots[unoptimized.lastOf(Pipeline.DefaultStage)].innermostLoop()
    Swag.assert(fast.first != Swag.U64.Max and slow.first != Swag.U64.Max)
    Swag.assert(fast.first < fast.last and fast.instructions < slow.instructions)
    Swag.assert(unoptimized.lastOf(1) == Swag.U64.Max)
}

// A compiler that stopped leaves no printing, and its words are kept for the listing.
#test
{
    let inspection = Pipeline.Inspection.parse("error: something went wrong\n")
    Swag.assert(inspection.snapshots.isEmpty() and inspection.steps.isEmpty())
}

/*
--- Part Two ---
As you watch the crane operator expertly rearrange the crates, you notice the process isn't following your prediction.

Some mud was covering the writing on the side of the crane, and you quickly wipe it away. The crane isn't a CrateMover 9000 - it's a CrateMover 9001.

The CrateMover 9001 is notable for many new and exciting features: air conditioning, leather seats, an extra cup holder, and the ability to pick up and move multiple crates at once.

Again considering the example above, the crates begin in the same configuration:

    [D]
[N] [C]
[Z] [M] [P]
 1   2   3
Moving a single crate from stack 2 to stack 1 behaves the same as before:

[D]
[N] [C]
[Z] [M] [P]
 1   2   3
However, the action of moving three crates from stack 1 to stack 3 means that those three moved crates stay in the same order, resulting in this new configuration:

        [D]
        [N]
    [C] [Z]
    [M] [P]
 1   2   3
Next, as both crates are moved from stack 2 to stack 1, they retain their order as well:

        [D]
        [N]
[C]     [Z]
[M]     [P]
 1   2   3
Finally, a single crate is still moved from stack 1 to stack 2, but now it's crate C that gets moved:

        [D]
        [N]
        [Z]
[M] [C] [P]
 1   2   3
In this example, the CrateMover 9001 has put the crates in a totally different order: MCD.

Before the rearrangement process finishes, update your simulation so that the Elves know where they should stand to be ready to unload the final supplies. After the rearrangement procedure completes, what crate ends up on top of each stack?
*/

using Core

func day5B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "5.txt")
    let lines    = expect File.readAllLines(dataPath)

    var stacks: Array'String
    var r:      Parser.RegExp
    var moveMode = false
    for l in lines
    {
        if moveMode
        {
            if not expect r.match(#raw "move (\d+) from (\d+) to (\d+)", l[]) do
                continue
            let crateCount       = expect StrConv.toU64(r.getCapture(1))
            let sourceStack      = expect StrConv.toS32(r.getCapture(2)) - 1
            let destinationStack = expect StrConv.toS32(r.getCapture(3)) - 1

            let movedCrates = String.from(stacks[sourceStack][0 until crateCount])
            stacks[destinationStack].insert(0, movedCrates.toString())
            stacks[sourceStack].remove(0, crateCount)
        }
        elif l[1] == '1'
        {
            moveMode = true
        }
        else
        {
            for stackIndex in (l.length + 3) / 4
            {
                let column = stackIndex * 4
                if stackIndex >= stacks.count do
                    stacks.add("")
                if l[column] == '[' do
                    stacks[stackIndex].append(l[column + 1])
            }
        }
    }

    var total: String
    for stack in stacks do
        total += stack[0]

    Swag.assert(total == "RNLFDJMCT")
}

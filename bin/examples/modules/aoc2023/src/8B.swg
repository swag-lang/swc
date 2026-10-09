/*
--- Part Two ---
The sandstorm is upon you and you aren't any closer to escaping the wasteland. You had the camel follow the instructions, but you've barely left your starting position. It's going to take significantly more steps to escape!

What if the map isn't for people - what if the map is for ghosts? Are ghosts even bound by the laws of spacetime? Only one way to find out.

After examining the maps a bit longer, your attention is drawn to a curious fact: the number of nodes with names ending in A is equal to the number ending in Z! If you were a ghost, you'd probably just start at every node that ends with A and follow all of the paths at the same time until they all simultaneously end up at nodes that end with Z.

For example:

LR

11A = (11B, XXX)
11B = (XXX, 11Z)
11Z = (11B, XXX)
22A = (22B, XXX)
22B = (22C, 22C)
22C = (22Z, 22Z)
22Z = (22B, 22B)
XXX = (XXX, XXX)
Here, there are two starting nodes, 11A and 22A (because they both end with A). As you follow each left/right instruction, use that instruction to simultaneously navigate away from both nodes you're currently on. Repeat this process until all of the nodes you're currently on end with Z. (If only some of the nodes you're on end with Z, they act like any other node and you continue as normal.) In this example, you would proceed as follows:

Step 0: You are at 11A and 22A.
Step 1: You choose all of the left paths, leading you to 11B and 22B.
Step 2: You choose all of the right paths, leading you to 11Z and 22C.
Step 3: You choose all of the left paths, leading you to 11B and 22Z.
Step 4: You choose all of the right paths, leading you to 11Z and 22B.
Step 5: You choose all of the left paths, leading you to 11B and 22C.
Step 6: You choose all of the right paths, leading you to 11Z and 22Z.
So, in this example, you end up entirely on nodes that end in Z after 6 steps.

Simultaneously start on every node that ends with A. How many steps does it take before you're only on nodes that end with Z?
*/

using Core

// This puzzle input makes the first-hit lengths sufficient; combine them with an LCM.

// An inline anonymous struct cannot carry a per-field attribute, so the node shape is
// named: 'name' is filled once the whole map has been read.
struct Node
{
    late name: string
    left:      u64
    right:     u64
}

func day8B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "8.txt")
    let lines    = expect File.readAllLines(dataPath)

    var instructions:    string = ""
    var nodes:           Array'Node
    var nodeIndexByName: HashTable'(string, u64)

    var startNodeIndices: Array'u64

    for l, i in lines
    {
        if i == 0
        {
            instructions = l.toString()
        }
        elif i > 1
        {
            let name = l[0 to 2]
            nodeIndexByName.add(name, i - 2)
            if name[2] == 'A' do
                startNodeIndices.add(i - 2)
        }
    }

    nodes.resize(lines.count - 2)
    for l, i in lines
    {
        if i <= 1 do
            continue
        let name           = l[0 to 2]
        let left           = l[7 to 9]
        let right          = l[12 to 14]
        let leftNodeIndex  = nodeIndexByName.find(left).value
        let rightNodeIndex = nodeIndexByName.find(right).value
        nodes[i - 2] = {name, leftNodeIndex, rightNodeIndex}
    }

    var currentNodeIndices = startNodeIndices

    var stepsToFirstEnd: Array'u64
    stepsToFirstEnd.resize(startNodeIndices.count)

    // For each starting node, count steps until its first node ending in Z.
    for startIndex in currentNodeIndices.count
    {
        var instructionIndex: u64
        for
        {
            let instruction = instructions[instructionIndex]
            instructionIndex = (instructionIndex + 1) % instructions.count

            let currentNodeIndex = currentNodeIndices[startIndex]
            if instruction == 'L' do
                currentNodeIndices[startIndex] = nodes[currentNodeIndex].left
            else do
                currentNodeIndices[startIndex] = nodes[currentNodeIndex].right
            stepsToFirstEnd[startIndex] += 1
            if nodes[currentNodeIndices[startIndex]].name[2] == 'Z' do
                break
        }
    }

    var steps = stepsToFirstEnd[0]
    for i in 1 until stepsToFirstEnd.count do
        steps = Math.lcm(cast(s64, steps), cast(s64, stepsToFirstEnd[i]))

    Swag.assert(steps == 16187743689077)
}

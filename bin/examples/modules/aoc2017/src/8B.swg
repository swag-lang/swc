/*
--- Part Two ---
To be safe, the CPU also needs to know the highest value held in any register during this process so that it can decide how much memory to allocate to these operations. For example, in the above instructions, the highest value ever held was 10 (in register c after the third instruction was evaluated).
*/

using Core

func day8B()
{
    let dataPath = Path.combine(Path.directoryName(#file), "8.txt")
    let lines    = expect File.readAllLines(dataPath)

    var re = expect Parser.RegExp.create(#raw "(\w+) (\w+) (-?\d+) if (\w+) ([[:ascii:]]+) (-?\d+)")
    var regs:  HashTable'(string, s32)
    var total: s32

    for l in lines
    {
        Swag.assert(re.match(l[]))
        var v0 = expect StrConv.toS32(re[3])
        let v1 = expect StrConv.toS32(re[6])
        if !regs.contains(re[1]) do
            regs.add(re[1], 0)
        if !regs.contains(re[4]) do
            regs.add(re[4], 0)
        if re[2] == "dec" do
            v0 = -v0

        let test  = regs[re[4]]
        var valid = false
        switch re[5]
        {
        case "==": valid = test == v1
        case "!=": valid = test != v1
        case ">=": valid = test >= v1
        case "<=": valid = test <= v1
        case ">":  valid = test > v1
        case "<":  valid = test < v1
        }

        if valid
        {
            let it = regs.find(re[1])
            it.value += v0
            total    = Math.max(it.value, total)
        }
    }

    Swag.assert(total == 4829)
}

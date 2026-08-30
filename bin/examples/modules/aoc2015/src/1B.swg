/*
--- Part Two ---
Now, given the same instructions, find the position of the first character that causes him to enter the basement (floor -1). The first character in the instructions has position 1, the second character has position 2, and so on.

For example:

) causes him to enter the basement at character position 1.
()()) causes him to enter the basement at character position 5.
What is the position of the character that causes Santa to first enter the basement?
*/

using Core

func day1B()
{
    let dataPath = Path.combine(Path.directoryName(#file), "1.txt")
    let lines    = expect File.readAllText(dataPath)

    var total = 0
    for c in lines.bytes()
    {
        total += c == '(' ? 1 : -1
        if total == -1
        {
            total = 1 + cast(s32) Swag.index
            break
        }
    }

    // Console.print("total: ", total)
    Swag.assert(total == 1783)
}

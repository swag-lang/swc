/*
--- Part Two ---
Now, take the signal you got on wire a, override wire b to that signal, and reset the other wires (including wire a). What new signal is ultimately provided to wire a?
*/

using Core

#ast
{
    let dataPath = Path.combine(Path.getDirectoryName(#file), "7.txt")

    var result: String
    var r:      Parser.RegExp

    var map: HashTable'(string, string)
    map = [{"AND", "&"}, {"OR", "|"}, {"LSHIFT", "<<"}, {"RSHIFT", ">>"}]

    assume
    {
        for &l in File.readAllLines(dataPath)
        {
            l.makeUpper()
            result += "internal const "
            if r.match(#"(\w+) -> B"#, l)
            {
                result += "B = 46065"
            }
            elif r.match(#"(\w+) -> (\w+)"#, l)
            {
                result += r[2]
                result += " = "
                result += r[1]
            }
            elif r.match(#"(\w+) (\w+) (\w+) -> (\w+)"#, l)
            {
                result += r[4]
                result += " = "
                result += r[1]
                result += " "
                result += map.find(r[2]).value
                result += " "
                result += r[3]
            }
            elif r.match(#"NOT (\w+) -> (\w+)"#, l)
            {
                result += r[2]
                result += " = ~"
                result += r[1]
            }
            result += "\n"
        }
    }

    return cast(string) result
}
func day7B()
{
    @assert(A == 14134)
}

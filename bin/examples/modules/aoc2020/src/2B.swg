/*
--- Part Two ---
While it appears you validated the passwords correctly, they don't seem to be what the Official Toboggan Corporate Authentication System is expecting.

The shopkeeper suddenly realizes that he just accidentally explained the password policy rules from his old job at the sled rental place down the street! The Official Toboggan Corporate Policy actually works a little differently.

Each policy actually describes two positions in the password, where 1 means the first character, 2 means the second character, and so on. (Be careful; Toboggan Corporate Policies have no concept of "index zero"!) Exactly one of these positions must contain the given letter. Other occurrences of the letter are irrelevant for the purposes of policy enforcement.

Given the same example list from above:

1-3 a: abcde is valid: position 1 contains a and position 3 does not.
1-3 b: cdefg is invalid: neither position 1 nor position 3 contains b.
2-9 c: ccccccccc is invalid: both position 2 and position 9 contain c.
How many passwords are valid according to the new interpretation of the policies?
*/

using Core

func day2B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "2.txt")
    let lines    = expect File.readAllLines(dataPath)

    var r: Parser.RegExp
    expect r.compile(#raw "(\d+)-(\d+) ([a-z]): ([a-z]+)")

    var total: u32
    for l in lines
    {
        discard r.match(l[])

        let firstPosition  = expect StrConv.toS32(r.getCapture(1)) - 1
        let secondPosition = expect StrConv.toS32(r.getCapture(2)) - 1
        let requiredLetter = r.getCapture(3)[0]
        let password       = r.getCapture(4)

        let firstMatch  = password[firstPosition] == requiredLetter
        let secondMatch = password[secondPosition] == requiredLetter
        let matchCount  = cast(s32, firstMatch) + cast(s32, secondMatch)
        total += matchCount == 1 ? 1 : 0
    }

    Swag.assert(total == 485)
}

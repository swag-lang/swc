/*
--- Part Two ---
The line is moving more quickly now, but you overhear airport security talking about how passports with invalid data are getting through. Better add some data validation, quick!

You can continue to ignore the cid field, but each other field has strict rules about what values are valid for automatic validation:

byr (Birth Year) - four digits; at least 1920 and at most 2002.
iyr (Issue Year) - four digits; at least 2010 and at most 2020.
eyr (Expiration Year) - four digits; at least 2020 and at most 2030.
hgt (Height) - a number followed by either cm or in:
If cm, the number must be at least 150 and at most 193.
If in, the number must be at least 59 and at most 76.
hcl (Hair Color) - a # followed by exactly six characters 0-9 or a-f.
ecl (Eye Color) - exactly one of: amb blu brn gry grn hzl oth.
pid (Passport ID) - a nine-digit number, including leading zeroes.
cid (Country ID) - ignored, missing or not.
Your job is to count the passports where all required fields are both present and valid according to the above rules. Here are some example values:

byr valid:   2002
byr invalid: 2003

hgt valid:   60in
hgt valid:   190cm
hgt invalid: 190in
hgt invalid: 190

hcl valid:   #123abc
hcl invalid: #123abz
hcl invalid: 123abc

ecl valid:   brn
ecl invalid: wat

pid valid:   000000001
pid invalid: 0123456789
Here are some invalid passports:

eyr:1972 cid:100
hcl:#18171d ecl:amb hgt:170 pid:186cm iyr:2018 byr:1926

iyr:2019
hcl:#602927 eyr:1967 hgt:170cm
ecl:grn pid:012533040 byr:1946

hcl:dab227 iyr:2012
ecl:brn hgt:182cm pid:021572410 eyr:2020 byr:1992 cid:277

hgt:59cm ecl:zzz
eyr:2038 hcl:74454a iyr:2023
pid:3556412378 byr:2007
Here are some valid passports:

pid:087499704 hgt:74in ecl:grn iyr:2012 eyr:2030 byr:1980
hcl:#623a2f

eyr:2029 ecl:blu cid:129 byr:1989
iyr:2014 pid:896056539 hcl:#a97842 hgt:165cm

hcl:#888785
hgt:164cm byr:2001 iyr:2015 cid:88
pid:545766238 ecl:hzl
eyr:2022

iyr:2010 hgt:158cm hcl:#b6652a ecl:blu byr:1944 eyr:2021 pid:093154719
Count the number of valid passports - those that have all required fields and valid values. Continue to treat cid as optional. In your batch file, how many passports are valid?
*/

using Core

func day4B()
{
    day4BWithExplicitChecks()
    day4BWithRegexRules()
}

func day4BWithExplicitChecks()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "4.txt")
    let lines    = expect File.readAllLines(dataPath)

    var validPassportCount, validFields: u32
    for line, lineIndex in lines
    {
        for field in Tokenize.split(line[], ' 'u8)
        {
            let fieldParts = Tokenize.split(field, ':'u8)
            let fieldValue = fieldParts[1]
            switch fieldParts[0]
            {
            case "byr":
                let year = catch StrConv.toS32(fieldValue)
                if year >= 1920 and year <= 2002 do
                    validFields |= 1

            case "iyr":
                let year = catch StrConv.toS32(fieldValue)
                if year >= 2010 and year <= 2020 do
                    validFields |= 2

            case "eyr":
                let year = catch StrConv.toS32(fieldValue)
                if year >= 2020 and year <= 2030 do
                    validFields |= 4

            case "hgt":
                let height = catch StrConv.parseS32(fieldValue) as err
                if err != null do
                    break
                if height.eat == fieldValue.count do
                    break
                let unit = fieldValue[height.eat to]
                if unit != "cm" and unit != "in" do
                    break
                if unit == "cm" and height.value >= 150 and height.value <= 193 do
                    validFields |= 8
                elif unit == "in" and height.value >= 59 and height.value <= 76 do
                    validFields |= 8

            case "hcl":
                if fieldValue.count != 7 or fieldValue[0] != '#' do
                    break
                discard catch StrConv.parseX64(fieldValue[1 to]) as err
                if err == null do
                    validFields |= 16

            case "ecl":
                if Slice.contains(["amb", "blu", "brn", "gry", "grn", "hzl", "oth"], fieldValue) do
                    validFields |= 32

            case "pid":
                discard catch StrConv.toS32(fieldValue) as err
                if err == null and fieldValue.count == 9 do
                    validFields |= 64
            }
        }

        if lineIndex == lines.count - 1 or lines[lineIndex + 1].isEmpty()
        {
            if validFields & 0b1111111 == 0b1111111 do
                validPassportCount += 1
            validFields = 0
        }
    }

    Swag.assert(validPassportCount == 224)
}

// One field rule: the expression a value has to match, and the bit it sets once it does.
struct Day4Rule
{
    expression: Parser.RegExp
    fieldMask:  u32
}

func day4BWithRegexRules()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "4.txt")
    let lines    = expect File.readAllLines(dataPath)

    // A compiled expression owns its program, so a rule states no copy: build it in a local
    // and hand it over with '#move'.
    var rulesByField: HashTable'(string, Day4Rule)
    var rule: Day4Rule

    rule = {expect Parser.RegExp.create("19[2-9][0-9]|200[0-2]"), 1}
    rulesByField.add("byr", #move rule)
    rule = {expect Parser.RegExp.create("201[0-9]|2020"), 2}
    rulesByField.add("iyr", #move rule)
    rule = {expect Parser.RegExp.create("202[0-9]|2030"), 4}
    rulesByField.add("eyr", #move rule)
    rule = {expect Parser.RegExp.create("((1[5678][0-9])|(19[0-3]))cm|(59|6[0-9]|7[0-6])in"), 8}
    rulesByField.add("hgt", #move rule)
    rule = {expect Parser.RegExp.create("#([a-f0-9]){6}"), 16}
    rulesByField.add("hcl", #move rule)
    rule = {expect Parser.RegExp.create("amb|blu|brn|gry|grn|hzl|oth"), 32}
    rulesByField.add("ecl", #move rule)
    rule = {expect Parser.RegExp.create("[0-9]{9}"), 64}
    rulesByField.add("pid", #move rule)

    var validPassportCount, validFields: u32
    for line, lineIndex in lines
    {
        for field in Tokenize.split(line[], ' 'u8)
        {
            let fieldParts = Tokenize.split(field, ':'u8)
            let fieldRule  = rulesByField.tryFind(fieldParts[0])
            if fieldRule and fieldRule.value.expression.match(fieldParts[1]) do
                validFields |= fieldRule.value.fieldMask
        }

        if lineIndex == lines.count - 1 or lines[lineIndex + 1].isEmpty()
        {
            validPassportCount += cast(s32, (validFields == 0b1111111))
            validFields = 0
        }
    }

    Swag.assert(validPassportCount == 224)
}

#global internal
#global namespace Viewers.Docx

using Core

private struct NumberLevel
{
    abstractId: String
    level:      u8
    format:     String
    start:      s32 = 1
    text:       String
}

private struct NumberOverride
{
    numberId:      String
    level:         u8
    startOverride: s32
    levelStart:    s32 = -1
    format:        String
    text:          String
    hasLevel:      bool
}

// The HTML list representation supported by one Word numbering level.
struct ListStyle
{
    tag:     String
    type:    String
    start:   s32 = 1
    limited: bool
}

// Resolves numbering IDs to a bounded, safe HTML list style.
struct NumberingCatalog
{
    private levels:    Array!{NumberLevel}
    private overrides: Array!{NumberOverride}
    private numbers:   HashTable!{String, String}
    limited:           bool
}

impl NumberingCatalog
{
    func parse(source: string)->NumberingCatalog fail
    {
        var result:          #returntype
        var scan            = Package.Scanner.create(source)
        var token:           Package.Token
        var currentAbstract = String{}
        var currentNumber   = String{}
        var currentLevel:    NumberLevel
        var currentOverride: NumberOverride
        var inAbstract      = false
        var inNumber        = false
        var inLevel         = false
        var inOverride      = false
        var inOverrideLevel = false
        var levelCount      = 0_u64
        var numberCount     = 0_u64
        var sawRoot         = false

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if not sawRoot
                {
                    if not token.isElement("numbering")
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    sawRoot = true
                }

                if token.isElement("abstractNum")
                {
                    inAbstract      = true
                    currentAbstract = token.attribute("abstractNumId") orelse ""
                    if currentAbstract.isEmpty() or currentAbstract.count > 32
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    for &level in result.levels where level.abstractId == currentAbstract
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }
                }
                else if token.isElement("num")
                {
                    inNumber      = true
                    currentNumber = token.attribute("numId") orelse ""
                    if currentNumber.isEmpty() or currentNumber.count > 32
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    numberCount += 1
                    if numberCount > 4096
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }
                }
                else if inNumber and token.isElement("lvlOverride")
                {
                    if inOverride
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    let level = catch StrConv.toS32(token.attribute("ilvl") orelse "") orelse -1
                    if level < 0 or level > 8
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    currentOverride = {numberId: currentNumber, level: cast(u8, level)}
                    inOverride      = not token.empty
                    if token.empty
                    {
                        for &item in result.overrides where item.numberId == currentOverride.numberId and item.level == currentOverride.level
                        {
                            fail Errors.InvalidFormatError{texts().err_Invalid}
                        }

                        result.overrides.add(#move currentOverride)
                    }
                }
                else if inOverride and token.isElement("lvl")
                {
                    let level = catch StrConv.toS32(token.attribute("ilvl") orelse "") orelse -1
                    if level != cast(s32, currentOverride.level)
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    currentLevel    = {level: currentOverride.level}
                    currentOverride.hasLevel = true
                    inOverrideLevel = not token.empty
                    if token.empty
                    {
                        currentOverride.format     = currentLevel.format
                        currentOverride.levelStart = currentLevel.start
                        currentOverride.text       = currentLevel.text
                    }
                }
                else if inOverride and token.isElement("startOverride")
                {
                    let start = catch StrConv.toS32(token.attribute("val") orelse "") orelse 0
                    if start < 1 or start > 1_000_000 or currentOverride.startOverride
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    currentOverride.startOverride = start
                }
                else if inAbstract and token.isElement("lvl")
                {
                    let value = catch StrConv.toS32(token.attribute("ilvl") orelse "") orelse -1
                    if value < 0 or value > 8
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    currentLevel = {abstractId: currentAbstract, level: cast(u8, value), format: String.from("decimal")}
                    levelCount   += 1
                    if levelCount > 36_864
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    inLevel = not token.empty
                    if token.empty
                    {
                        result.levels.add(#move currentLevel)
                    }
                }
                else if inNumber and token.isElement("abstractNumId")
                {
                    let abstractId = token.attribute("val") orelse ""
                    if abstractId.count == 0 or abstractId.count > 32
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    if result.numbers.tryFind(currentNumber)
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    result.numbers.add(currentNumber, abstractId)
                }
                else if inOverrideLevel and token.isElement("numFmt")
                {
                    currentLevel.format = token.attribute("val") orelse ""
                }
                else if inOverrideLevel and token.isElement("start")
                {
                    let start = catch StrConv.toS32(token.attribute("val") orelse "") orelse 0
                    if start < 1 or start > 1_000_000
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    currentLevel.start = start
                }
                else if inOverrideLevel and token.isElement("lvlText")
                {
                    currentLevel.text = token.attribute("val") orelse ""
                }
                else if inOverrideLevel and
                        (token.isElement("pPr") or token.isElement("rPr") or token.isElement("lvlJc") or token.isElement("suff") or token.isElement("lvlRestart") or token.isElement("isLgl") or token.isElement("legacy") or token.isElement("lvlPicBulletId"))
                {
                    result.limited = true
                }
                else if inOverride and
                        not inOverrideLevel and
                        not token.isElement("lvlOverride") and
                        not token.isElement("lvl") and
                        not token.isElement("startOverride")
                {
                    result.limited = true
                }
                else if inLevel
                {
                    if token.isElement("numFmt")
                    {
                        currentLevel.format = token.attribute("val") orelse ""
                    }
                    else if token.isElement("start")
                    {
                        let start = catch StrConv.toS32(token.attribute("val") orelse "") orelse 0
                        if start < 1 or start > 1_000_000
                        {
                            fail Errors.InvalidFormatError{texts().err_Invalid}
                        }

                        currentLevel.start = start
                    }
                    else if token.isElement("lvlText")
                    {
                        currentLevel.text = token.attribute("val") orelse ""
                    }
                }
            }

            if token.kind == .End or token.empty
            {
                if token.isElement("lvl") and inOverrideLevel
                {
                    currentOverride.format     = currentLevel.format
                    currentOverride.levelStart = currentLevel.start
                    currentOverride.text       = currentLevel.text
                    inOverrideLevel            = false
                }
                else if token.isElement("lvlOverride") and inOverride
                {
                    for &item in result.overrides where item.numberId == currentOverride.numberId and item.level == currentOverride.level
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    result.overrides.add(#move currentOverride)
                    inOverride = false
                }
                else if token.isElement("lvl") and inLevel
                {
                    result.levels.add(#move currentLevel)
                    inLevel = false
                }
                else if token.isElement("abstractNum")
                {
                    inAbstract = false
                }
                else if token.isElement("num")
                {
                    inNumber = false
                }
            }
        }

        if scan.damaged or
           inLevel or
           inAbstract or
           inNumber or
           inOverride or
           inOverrideLevel or
           (source.count and not sawRoot)
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        return result
    }

    mtd const lookup(numberId: string, level: u8)->ListStyle
    {
        var result: #returntype
        result.tag     = "ol"
        result.type    = "1"
        result.limited = .limited
        let abstractId = .numbers.tryFind(String.from(numberId))
        if not abstractId
        {
            result.limited = true
            return result
        }

        var found = false
        for &entry in .levels
        {
            if entry.abstractId != abstractId.value or entry.level != level
            {
                continue
            }

            found = true
            var numberStart  = entry.start
            var numberFormat = entry.format
            var numberText   = entry.text
            for &override in .overrides where override.numberId == numberId and override.level == level
            {
                if override.hasLevel
                {
                    if not override.format.isEmpty()
                    {
                        numberFormat = override.format
                    }

                    if override.levelStart > 0
                    {
                        numberStart = override.levelStart
                    }

                    if not override.text.isEmpty()
                    {
                        numberText = override.text
                    }
                }

                if override.startOverride > 0
                {
                    numberStart = override.startOverride
                }
            }

            result.start = numberStart
            if numberFormat != "bullet"
            {
                var marker: String = "%"
                marker += cast(u8, '1'_u8 + entry.level)
                var markerWithPeriod = marker
                markerWithPeriod += "."
                var markerWithParenthesis = marker
                markerWithParenthesis += ")"
                if numberText != markerWithPeriod and numberText != markerWithParenthesis
                {
                    result.limited = true
                }
            }

            switch cast(string, numberFormat.toSlice())
            {
            case "decimal":
                result.tag  = "ol"
                result.type = "1"

            case "lowerLetter":
                result.tag  = "ol"
                result.type = "a"

            case "upperLetter":
                result.tag  = "ol"
                result.type = "A"

            case "lowerRoman":
                result.tag  = "ol"
                result.type = "i"

            case "upperRoman":
                result.tag  = "ol"
                result.type = "I"

            case "bullet":
                result.tag  = "ul"
                result.type = numberText == "o" ? "circle" : numberText == "▪" or numberText == "■" ? "square" : "disc"
                if numberText != "•" and
                   numberText != "" and
                   numberText != "·" and
                   numberText != "o" and
                   numberText != "▪" and
                   numberText != "■"
                {
                    result.limited = true
                }

            default:
                result.tag     = "ol"
                result.type    = "1"
                result.limited = true
            }

            return result
        }

        result.limited = true
        if not found
        {
            result.tag = "ol"
        }

        return result
    }
}

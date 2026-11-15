#global internal
#global namespace Viewers.Docx

using Core

// Paragraph geometry in Word's twips, with explicit presence for zero and negative indents.
struct ParagraphFormat
{
    alignment:  String
    outline:    s32 = -1
    before:     s32 = -1
    after:      s32 = -1
    left:       s32
    right:      s32
    first:      s32
    indentMask: u8
    line:       s32 = -1
    lineRule:   String
    pageBefore: FormatSwitch
    limited:    bool
}

impl ParagraphFormat
{
    mtd overlay(other: const *ParagraphFormat)
    {
        if not other.alignment.isEmpty() do
            .alignment = other.alignment
        if other.outline >= 0 do
            .outline = other.outline
        if other.before >= 0 do
            .before = other.before
        if other.after >= 0 do
            .after = other.after
        if other.indentMask & 1 do
            .left = other.left
        if other.indentMask & 2 do
            .right = other.right
        if other.indentMask & 4 do
            .first = other.first
        .indentMask |= other.indentMask
        if other.line >= 0 do
            .line = other.line
        if not other.lineRule.isEmpty() do
            .lineRule = other.lineRule
        if other.pageBefore != .Inherit do
            .pageBefore = other.pageBefore
        .limited = .limited or other.limited
    }

    mtd read(token: const *Package.Token)
    {
        func distance(value: string?)->{valid: bool, value: s32}
        {
            var result: #returntype
            if not value do
                return result
            result.value = catch StrConv.toS32(value) { return result; }
            result.valid = result.value >= -31680 and result.value <= 31680
            return result
        }

        let value = token.attribute("val") orelse ""
        if token.isElement("jc")
        {
            switch value
            {
            case "center":             .alignment = "center"
            case "right", "end":       .alignment = "right"
            case "both", "distribute": .alignment = "justify"
            case "left", "start":      .alignment = "left"
            default:                   .limited = true
            }
        }
        elif token.isElement("outlineLvl")
        {
            let level = catch StrConv.toS32(value) orelse -1
            if level >= 0 and level <= 9 do
                .outline = level
            else do
                .limited = true
        }
        elif token.isElement("spacing")
        {
            if let before = token.attribute("before")
            {
                let parsed = distance(before)
                if parsed.valid and parsed.value >= 0 do
                    .before = parsed.value
                else do
                    .limited = true
            }

            if let after = token.attribute("after")
            {
                let parsed = distance(after)
                if parsed.valid and parsed.value >= 0 do
                    .after = parsed.value
                else do
                    .limited = true
            }

            if let line = token.attribute("line")
            {
                let parsed = distance(line)
                if parsed.valid and parsed.value > 0 do
                    .line = parsed.value
                else do
                    .limited = true
            }

            if let rule = token.attribute("lineRule")
            {
                if rule == "auto" or rule == "exact" or rule == "atLeast" do
                    .lineRule = rule
                else do
                    .limited = true
            }

            if token.attribute("beforeAutospacing") == "1" or token.attribute("afterAutospacing") == "1" do
                .limited = true
        }
        elif token.isElement("ind")
        {
            if let left = token.attribute("start") orelse token.attribute("left")
            {
                let parsed = distance(left)
                if parsed.valid
                {
                    .left       = parsed.value
                    .indentMask |= 1
                }
                else
                {
                    .limited = true
                }
            }

            if let right = token.attribute("end") orelse token.attribute("right")
            {
                let parsed = distance(right)
                if parsed.valid
                {
                    .right      = parsed.value
                    .indentMask |= 2
                }
                else
                {
                    .limited = true
                }
            }

            let hanging = token.attribute("hanging")
            let first   = hanging orelse token.attribute("firstLine")
            if first
            {
                let parsed = distance(first)
                if parsed.valid and parsed.value >= 0
                {
                    .first      = hanging ? -parsed.value : parsed.value
                    .indentMask |= 4
                }
                else
                {
                    .limited = true
                }
            }
        }
        elif token.isElement("pageBreakBefore")
        {
            .pageBefore = value == "0" or value == "false" or value == "off" ? .Off : .On
        }
    }

    mtd const heading()->u32 => .outline >= 0 and .outline < 9 ? cast(u32, Math.min(.outline + 1, 6)) : 0

    mtd const css()->String
    {
        var result:  #returntype
        let numbers: Globalization.NumberFormatInfo
        if not .alignment.isEmpty() do
            result += Format.toString("text-align:%;", .alignment)
        if .before >= 0 do
            result += Format.toString("margin-top:%pt;", numbers.format(cast(f64, .before) / 20, 2))
        if .after >= 0 do
            result += Format.toString("margin-bottom:%pt;", numbers.format(cast(f64, .after) / 20, 2))
        if .indentMask & 1 do
            result += Format.toString("margin-left:%pt;", numbers.format(cast(f64, .left) / 20, 2))
        if .indentMask & 2 do
            result += Format.toString("margin-right:%pt;", numbers.format(cast(f64, .right) / 20, 2))
        if .indentMask & 4 do
            result += Format.toString("text-indent:%pt;", numbers.format(cast(f64, .first) / 20, 2))
        if .line > 0
        {
            if .lineRule == "exact" do
                result += Format.toString("line-height:%pt;", numbers.format(cast(f64, .line) / 20, 2))
            elif .lineRule == "atLeast" do
                result += Format.toString("line-height:max(1.2em,%pt);", numbers.format(cast(f64, .line) / 20, 2))
            else do
                result += Format.toString("line-height:%;", numbers.format(cast(f64, .line) / 240, 3))
        }

        return result
    }
}

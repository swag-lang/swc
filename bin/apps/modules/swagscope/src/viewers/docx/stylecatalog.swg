#global internal
#global namespace Viewers.Docx

using Core

enum StyleKind
{
    Other
    Paragraph
    Character
}

struct ResolvedStyle
{
    run:       RunFormat
    paragraph: ParagraphFormat
    limited:   bool
}

private struct DocumentStyle
{
    id:        String
    parent:    String
    kind:      StyleKind
    run:       RunFormat
    paragraph: ParagraphFormat
    resolved:  ResolvedStyle
}

// Named Word styles are resolved once; callers never walk untrusted inheritance chains.
struct StyleCatalog
{
    private styles:     Array!{DocumentStyle}
    private index:      HashTable!{String, u64}
    defaultParagraphId: String
    defaultRun:         RunFormat
    defaultParagraph:   ParagraphFormat
    loaded:             bool
}

impl StyleCatalog
{
    func parse(source: string, theme: const *Package.OfficeTheme)->StyleCatalog fail
    {
        var result: #returntype
        result.loaded = source.count != 0
        var scan        = Package.Scanner.create(source)
        var token:   Package.Token
        var current: DocumentStyle
        var inStyle     = false
        var inDefaults  = false
        var inRun       = false
        var inParagraph = false
        var styleCount  = 0_u64
        var isDefault   = false
        var sawRoot     = false
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if not sawRoot
                {
                    if not token.isElement("styles")
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    sawRoot = true
                }

                if token.isElement("docDefaults")
                {
                    inDefaults = not token.empty
                }
                else if token.isElement("style")
                {
                    if inStyle
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    styleCount += 1
                    if styleCount > 4096
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    current    = {}
                    current.id = token.attribute("styleId") orelse ""
                    if current.id.count > 256
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    let kind = token.attribute("type") orelse ""
                    current.kind = kind == "paragraph" ? .Paragraph : kind == "character" ? .Character : .Other
                    isDefault    = token.attribute("default") == "1" or token.attribute("default") == "true"
                    inStyle      = true
                }
                else if inStyle and token.isElement("basedOn")
                {
                    current.parent = token.attribute("val") orelse ""
                    if current.parent.count > 256
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }
                }
                else if (inStyle or inDefaults) and token.isElement("pPr")
                {
                    inParagraph = not token.empty
                }
                else if (inStyle or inDefaults) and not inParagraph and token.isElement("rPr")
                {
                    inRun = not token.empty
                }
                else if inRun
                {
                    if inStyle
                    {
                        current.run.read(&token, theme)
                    }
                    else
                    {
                        result.defaultRun.read(&token, theme)
                    }
                }
                else if inParagraph
                {
                    if inStyle
                    {
                        current.paragraph.read(&token)
                    }
                    else
                    {
                        result.defaultParagraph.read(&token)
                    }
                }
            }

            if (token.kind == .End or token.empty) and token.isElement("style") and inStyle
            {
                if not current.id.isEmpty() and current.kind != .Other
                {
                    if result.index.tryFind(current.id)
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    if isDefault and current.kind == .Paragraph
                    {
                        result.defaultParagraphId = current.id
                    }

                    result.index.add(current.id, result.styles.count)
                    result.styles.add(#move current)
                }

                inStyle     = false
                inRun       = false
                inParagraph = false
            }

            if token.kind == .End
            {
                if token.isElement("docDefaults")
                {
                    inDefaults = false
                }
                else if token.isElement("rPr")
                {
                    inRun = false
                }
                else if token.isElement("pPr")
                {
                    inParagraph = false
                }
            }
        }

        if scan.damaged or inStyle or (result.loaded and not sawRoot)
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        if result.defaultParagraphId.isEmpty() and result.index.tryFind(String.from("Normal"))
        {
            result.defaultParagraphId = "Normal"
        }

        for index in result.styles.count
        {
            let resolved = result.resolve(index)
            result.styles[index].resolved = resolved
        }

        return result
    }

    private mtd const resolve(index: u64)->ResolvedStyle
    {
        var result: #returntype
        var chain:  Array!{u64}
        var current = index
        while true
        {
            var repeated = false
            for previous in chain where previous == current
            {
                repeated = true
            }

            if repeated or chain.count >= 64
            {
                result.limited = true
                break
            }

            chain.add(current)
            let style = &.styles[current]
            if style.parent.isEmpty()
            {
                break
            }

            let parent = .index.tryFind(style.parent)
            if not parent or .styles[parent.value].kind != style.kind
            {
                result.limited = true
                break
            }

            current = parent.value
        }

        for offset in chain.count
        {
            let style = &.styles[chain[chain.count - 1 - offset]]
            result.run.applyStyle(&style.run)
            result.paragraph.overlay(&style.paragraph)
        }

        return result
    }

    mtd const lookup(id: String, kind: StyleKind)->const *ResolvedStyle?
    {
        let item = .index.tryFind(id)
        if not item or .styles[item.value].kind != kind
        {
            return null
        }

        return &.styles[item.value].resolved
    }
}

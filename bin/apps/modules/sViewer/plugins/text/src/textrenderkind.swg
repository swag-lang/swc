#global internal

using Core

enum TextRenderKind
{
    None
    Plain
    Markdown
    Html
    Code
}

func textRenderKind(fileName: string)->TextRenderKind
{
    var extension = String.from(Path.extension(fileName) orelse "")
    extension = extension.toLower()
    switch extension.toString()
    {
    case ".txt", ".log", ".csv", ".tsv": return .Plain
    case ".md", ".markdown": return .Markdown
    case ".htm", ".html": return .Html
    case ".swg", ".swgs": return .Code
    }
    if textCodeLanguage(fileName) != .None do
        return .Code
    return .None
}

func textRenderName(kind: TextRenderKind, fileName: string)->String
{
    switch kind
    {
    case .None: return "Text"
    case .Plain: return "Text"
    case .Markdown: return "Markdown"
    case .Html: return "HTML"
    case .Code:
        var extension = String.from(Path.extension(fileName) orelse "Code")
        extension = extension.toUpper()
        if extension == ".SWG" or extension == ".SWGS" do
            return "Swag"
        if !extension.isEmpty() and extension[0] == '.' do
            extension.remove(0, 1)
        return String.from(extension.toString())
    }
}

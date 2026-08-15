#global internal

using Core, Gui

struct CodeTextRenderer
{
    genericLexer: TextCodeLexer
    swagLexer:    RichEditLexerSwag
}

impl CodeTextRenderer
{
    mtd configure(editor: *RichEditCtrl, fileName: string, forcedLanguage = TextCodeLanguage.None)
    {
        editor.setFlags(.ReadOnly)

        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        if extension == ".swg" or extension == ".swgs"
        {
            editor.setLexer(.swagLexer)
            editor.lexAll()
            return
        }

        let language = forcedLanguage != .None ? forcedLanguage : textCodeLanguage(fileName)
        if language == .None do
            return
        .genericLexer = TextCodeLexer.create(language)
        editor.setLexer(.genericLexer)
        editor.lexAll()
    }
}

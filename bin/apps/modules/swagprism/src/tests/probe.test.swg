#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The attribute is written immediately above the first function, not at the top of the snippet.
#test
{
    const Source = """\
        // a comment
        const Limit = 4

        func first()
        {
        }
        """

    let inspected = Pipeline.inspectedSource(Source, "pre-emit", true)
    let text      = inspected.toString()

    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro(\"pre-emit\"), Swag.Optimize(true)]") != Swag.U64.Max)
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "const Limit = 4") < Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro"))
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro") < Utf8.indexOf(cast(const [..] u8) text, "func first()"))
}

// The requested stage and optimization level reach the attribute unchanged.
#test
{
    const Source = "func only()\n{\n}"

    let off  = Pipeline.inspectedSource(Source, "post-regalloc", false)
    let text = off.toString()
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro(\"post-regalloc\"), Swag.Optimize(false)]") != Swag.U64.Max)
}

// A snippet with no function of its own is left exactly as it was written.
#test
{
    const Source = "const Only = 1\n"

    let inspected = Pipeline.inspectedSource(Source, "pre-emit", true)
    Swag.assert(inspected.toString() == Source)
}

// Only a `func` that starts its own line is taken for the declaration the reader meant.
#test
{
    const Source = """\
        // a func in a comment
        var name = "func in a string"
        func real()
        {
        }
        """

    let inspected = Pipeline.inspectedSource(Source, "pre-emit", true)
    let text      = inspected.toString()
    let attribute = Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro")

    Swag.assert(attribute != Swag.U64.Max)
    Swag.assert(attribute > Utf8.indexOf(cast(const [..] u8) text, "func in a string"))
    Swag.assert(attribute < Utf8.indexOf(cast(const [..] u8) text, "func real()"))
}

// Color the compiler wrote for a console is removed, and everything else survives.
#test
{
    let colored = "\x1B[38;2;255;0;0mrax\x1B[0m = \x1B[1mrbx\x1B[0m"
    let plain   = Pipeline.withoutTerminalEscapes(colored)
    Swag.assert(plain.toString() == "rax = rbx")
}

// Text with no escape at all is returned byte for byte.
#test
{
    const Plain = "  0 | mov rax, [rsp+8]\n  1 | ret\n"

    let text = Pipeline.withoutTerminalEscapes(Plain)
    Swag.assert(text.toString() == Plain)
}

// A truncated sequence at the very end cannot walk past the buffer.
#test
{
    let text = Pipeline.withoutTerminalEscapes("value\x1B[")
    Swag.assert(text.toString() == "value")
}

// Every offered stage names a side and a pass, which is the only spelling the attribute takes.
#test
{
    Swag.assert(Pipeline.Stages.count != 0)
    Swag.assert(Pipeline.DefaultStage < Pipeline.Stages.count)

    for i in Pipeline.Stages.count
    {
        let name     = cast(const [..] u8) Pipeline.Stages[i]
        let isBefore = Utf8.startsWith(name, "pre-")
        let isAfter  = Utf8.startsWith(name, "post-")
        Swag.assert(isBefore or isAfter)
    }
}

// Every stage has a name to pick it by, in every language the application ships.
#test
{
    for language in Gui.languages()
    {
        discard catch Gui.applyLanguage(&g_App.resources, language.tag)

        let labels = Pipeline.stageLabels()
        Swag.assert(labels.count == Pipeline.Stages.count)
        for i in labels.count do
            Swag.assert(labels[i].count != 0)
    }
}

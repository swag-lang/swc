#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Simultaneous viewers claim distinct temporary modules and retain them until each probe closes.
#test
{
    var probes: [16] Pipeline.Probe
    var tasks:  [16] Swag.Task
    for index in probes.count
    {
        let probe = &probes[index]
        tasks[index].submit(func|probe|() { expect probe.open() })
    }

    for &task in tasks do
        task.wait()
    for &probe, index in probes
    {
        Swag.assert(Directory.exists(probe.root))
        for previous in index do
            Swag.assert(probe.session != probes[previous].session)
    }
}

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

    let inspected = Pipeline.inspectedSource(Source, "pre-emit")
    let text      = inspected.toString()

    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro(\"pre-emit\")]") != Swag.U64.Max)
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "const Limit = 4") < Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro"))
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro") < Utf8.indexOf(cast(const [..] u8) text, "func first()"))
}

// The requested stage reaches the attribute unchanged.
#test
{
    const Source = "func only()\n{\n}"

    let off  = Pipeline.inspectedSource(Source, "post-regalloc")
    let text = off.toString()
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro(\"post-regalloc\")]") != Swag.U64.Max)
}

// A snippet with no function of its own is left exactly as it was written.
#test
{
    const Source = "const Only = 1\n"

    let inspected = Pipeline.inspectedSource(Source, "pre-emit")
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

    let inspected = Pipeline.inspectedSource(Source, "pre-emit")
    let text      = inspected.toString()
    let attribute = Utf8.indexOf(cast(const [..] u8) text, "#[Swag.PrintMicro")

    Swag.assert(attribute != Swag.U64.Max)
    Swag.assert(attribute > Utf8.indexOf(cast(const [..] u8) text, "func in a string"))
    Swag.assert(attribute < Utf8.indexOf(cast(const [..] u8) text, "func real()"))
}

// Each optimization level reaches the real compiler, whose RGB output survives capture.
#test
{
    var probe: Pipeline.Probe
    const Levels: [?] Swag.BuildCfgBackendOptimLevel = [.O0, .O1, .O2]
    for level in Levels
    {
        let result = expect probe.compile("func value()->s32 { return 42 }", "pre-emit", level)
        Swag.assert(!result.failed)
        Swag.assert(Utf8.indexOf(cast(const [..] u8) result.text.toString(), "\x1B[38;2;") != Swag.U64.Max)

        var output: CompilerOutput
        output.parse(result.text.toString())
        let expected = Format.toString("  optimize : O%", cast(u8) level)
        Swag.assert(Utf8.indexOf(cast(const [..] u8) output.text.toString(), expected.toString()) != Swag.U64.Max)
    }
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

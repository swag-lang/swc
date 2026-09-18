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
    Swag.assert(inspected.contains("#[Swag.PrintMicro(\"pre-emit\")]"))
    Swag.assert(inspected.indexOf("const Limit = 4") < inspected.indexOf("#[Swag.PrintMicro"))
    Swag.assert(inspected.indexOf("#[Swag.PrintMicro") < inspected.indexOf("func first()"))
}

// The requested stage reaches the attribute unchanged.
#test
{
    const Source = "func only()\n{\n}"

    let inspected = Pipeline.inspectedSource(Source, "post-regalloc")
    Swag.assert(inspected.contains("#[Swag.PrintMicro(\"post-regalloc\")]"))
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
    let attribute = inspected.indexOf("#[Swag.PrintMicro")

    Swag.assert(attribute != Swag.U64.Max)
    Swag.assert(attribute > inspected.indexOf("func in a string"))
    Swag.assert(attribute < inspected.indexOf("func real()"))
}

// Each optimization level reaches the real compiler, whose RGB output survives capture.
#test
{
    var probe: Pipeline.Probe
    const Levels: [?] Swag.BuildCfgBackendOptimLevel = [.O0, .O1, .O2]
    for level in Levels
    {
        let result = expect probe.compile("func value()->s32 { return 42 }", "pre-emit", level)
        Swag.assert(not result.failed)
        Swag.assert(result.text.contains("\x1B[38;2;"))

        var output: CompilerOutput
        output.parse(result.text.toString())
        let expected = Format.toString("  optimize : O%", cast(u8) level)
        Swag.assert(output.text.contains(expected.toString()))
    }
}

// Microcode does not import the rendering stack implicitly.
#test
{
    var probe: Pipeline.Probe
    let result = expect probe.compile("using Pixel\nfunc value()->u32 { return 0 }", "pre-emit", .O0)
    Swag.assert(result.failed)
    Swag.assert(result.text.contains("Pixel"))
}

// Every offered stage names a side and a pass, which is the only spelling the attribute takes.
#test
{
    Swag.assert(Pipeline.Stages.count != 0)
    Swag.assert(Pipeline.DefaultStage < Pipeline.Stages.count)

    for stage in Pipeline.Stages
    {
        let name     = cast(const [..] u8) stage
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
        for label in labels do
            Swag.assert(label.count != 0)
    }
}

// The worker count fits the machine and always leaves it something to draw the interface with.
#test
{
    let workers = Pipeline.compilerWorkerCount()
    let machine = Hardware.processorCount()
    Swag.assert(workers >= 1 and workers <= 12)
    Swag.assert(workers < machine or machine <= 2)
}

// Writing what a file already holds leaves its modification time alone, which is what the
// compiler reads to decide whether it can answer a module's setup from its cache. The delay is
// what lets a millisecond clock tell a write apart from a skip.
#test
{
    var probe: Pipeline.Probe
    expect probe.open()

    let path     = Path.combine(probe.root, "module.swg")
    let original = expect File.readAllText(path.toString())
    let before   = expect File.info(path.toString())

    Threading.Thread.sleep(5'ms)
    expect Pipeline.writeIfChanged(path.toString(), original.toString())
    let kept = expect File.info(path.toString())
    Swag.assert(kept.lastWriteTime == before.lastWriteTime)

    Threading.Thread.sleep(5'ms)
    expect Pipeline.writeIfChanged(path.toString(), "// replaced\n")
    let rewritten = expect File.info(path.toString())
    let content   = expect File.readAllText(path.toString())
    Swag.assert(content.toString() == "// replaced\n")
    Swag.assert(rewritten.lastWriteTime != before.lastWriteTime)
}

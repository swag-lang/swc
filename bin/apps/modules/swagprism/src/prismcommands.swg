#global internal

using Core, Gui, Pixel

// The commands of the window.
//
// The window keeps no toolbar: each command is an entry of its lens, found by its name, and the
// ones a key runs are registered as shortcuts, so the lens writes the key beside the entry.
namespace PrismCommands
{
    const Lens               = "prism.lens"
    const LensKey            = "prism.lens.key"     // `Space`, which opens the lens unless it types.
    const Information        = "prism.sheet"
    const InformationKey     = "prism.sheet.key"     // `I`, which shows the sheet unless it types.
    const Compile            = "prism.compile"
    const FormatSource       = "prism.format"
    const LiveEdit           = "prism.liveEdit"
    const Columns            = "prism.layout.columns"
    const Stages             = "prism.layout.stages"
    const Compare            = "prism.layout.compare"
    const PreviousStage      = "prism.step.previous"
    const NextStage          = "prism.step.next"
    const ShowChange         = "prism.step.change"
    const SourceLines        = "prism.listing.source"
    const Opcodes            = "prism.listing.opcodes"
    const CopyListing        = "prism.listing.copy"
    const BuildConfiguration = "prism.build.configuration"
    const RestoreBuild       = "prism.build.restore"
    const PausePreview       = "prism.preview.pause"
}

impl MainWindow
{
    // Creates the lens, registers every command of the window under its family, and the source
    // that answers with the examples, the views, the stages, the levels and the presets.
    mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            .addSource(.None, func|window = me|(results) { window.describeChoices(results) })
            .addCommands(func()->string => appStrings().lens_Source,
                         [PrismCommands.Compile, PrismCommands.FormatSource, PrismCommands.LiveEdit])
            .addCommands(func()->string => appStrings().lens_View, [PrismCommands.Columns, PrismCommands.Stages, PrismCommands.Compare, PrismCommands.Information,
                                                                    PrismCommands.PreviousStage, PrismCommands.NextStage, PrismCommands.ShowChange,
                                                                    PrismCommands.SourceLines, PrismCommands.Opcodes, PrismCommands.CopyListing])
            .addCommands(func()->string => appStrings().lens_Build,
                         [PrismCommands.BuildConfiguration, PrismCommands.RestoreBuild, PrismCommands.PausePreview])
        }

        .appearanceButton.addToLens(.lens)

        // The door has a key of its own where nothing types, and a chord everywhere.
        .registerKeyShortcut(.None, .Space, PrismCommands.LensKey)
        .registerKeyShortcut(.Control, .K, PrismCommands.Lens)
        .registerKeyShortcut(.None, .I, PrismCommands.InformationKey)
        .registerKeyShortcut(.Control, .I, PrismCommands.Information)
        .registerKeyShortcut(.Control, .Return, PrismCommands.Compile)
        .registerKeyShortcut(.CtrlShift, .F, PrismCommands.FormatSource)
        .registerKeyShortcut(.Control, .D1, PrismCommands.Columns)
        .registerKeyShortcut(.Control, .D2, PrismCommands.Stages)
        .registerKeyShortcut(.Control, .D3, PrismCommands.Compare)
        .registerKeyShortcut(.None, .Left, PrismCommands.PreviousStage)
        .registerKeyShortcut(.None, .Right, PrismCommands.NextStage)
        .registerKeyShortcut(.CtrlShift, .C, PrismCommands.CopyListing)
    }

    // Answers the lens with the choices of the window, each in force checked: the examples, then
    // for each build shown its view, its stage, its optimization level and its preset.
    mtd describeChoices(results: *Lens.Results)
    {
        let strings = appStrings()
        let names   = [exampleName(.Plasma), exampleName(.Julia), exampleName(.Gui), exampleName(.Dot)]
        .addChoices(results, strings.lens_Examples, names, cast(u64, .selectedExample), .Example, 0)

        // Beside another build, each family is asked for one column at a time.
        for index in .panels.count where .isShown(index)
        {
            var side = ""
            if .view == .Compare do
                side = index == 0 ? strings.ui_RightColumn : strings.ui_LeftColumn
            .describePanelChoices(results, index, side)
        }
    }

    // Answers the lens with the choices of the build `panel`; `side` names its column, if needed.
    mtd describePanelChoices(results: *Lens.Results, panel: u64, side: string)
    {
        let strings = appStrings()
        let build   = .panels[panel]
        let views   = [viewerName(.Microcode), viewerName(.Render2D), viewerName(.Gui)]
        .addChoices(results, sectionLabel(strings.lens_ViewAs, side), views, cast(u64, build.kind), .View, panel)
        let micro = build.micro()
        if micro do
            .addChoices(results, sectionLabel(strings.lens_Stage, side), Pipeline.stageLabels(), micro.stage, .Stage, panel)
        .addChoices(results, sectionLabel(strings.lens_Optimization, side), LevelIds, cast(u64, build.level), .Level, panel)
        .addChoices(results, sectionLabel(strings.lens_Preset, side), BuildOptions.PresetNames, cast(u64, build.options.preset), .Preset, panel)
    }

    // Adds to `results` a section of the choices of `family` labelled `label`, with the row of
    // `chosen` checked: every row when the query answers the label, else the rows whose title
    // answers it. Choosing a row applies it to the build `panel`.
    mtd addChoices(results: *Lens.Results, label: string, titles: const [..] string, chosen: u64, family: LensChoice, panel: u64)
    {
        let all = Lens.match(results.query, label).matched
        var section: *Lens.Section?
        for title, index in titles
        {
            if not all and not Lens.match(results.query, title).matched do
                continue
            if not section do
                section = results.addSection(label)
            with let entry = section.addEntry(title)
            {
                .checked = index == chosen
                .run     = func|window = me, family, panel, index|() { window.applyChoice(family, panel, index) }
            }
        }
    }

    // Applies the choice `index` of `family` to the build `panel`, as a row of the lens asks.
    mtd applyChoice(family: LensChoice, panel: u64, index: u64)
    {
        let build = .panels[panel]
        switch #complete family
        {
        case .Example:
            .openExample(cast(ExampleKind, cast(u32, index)))

        case .View:
            build.selectViewer(cast(ViewerKind, cast(u32, index)))
            .compile()

        case .Stage:
            build.micro()?.setStage(cast(u32, index))

        case .Level:
            build.setLevel(cast(Swag.Build.BackendOptimLevel, cast(u32, index)))

        case .Preset:
            build.options.setPreset(cast(Pipeline.BuildPreset, cast(u32, index)))
        }
    }

    // Describes one command of the window for the lens: its name, its glyph, and whether it applies,
    // is available and is in force now.
    mtd computeCommandState(evt: *CommandStateEvent)->bool
    {
        // Controls ask for their state while the window is still being built.
        if .panels.count < 2 do
            return false

        let strings = appStrings()
        let main    = .panels[0]
        let micro   = main.micro()
        let stages  = .view == .Stages

        var name:     string = ""
        var icon:     Icon
        var hidden:   bool
        var disabled: bool
        var toggle:   bool
        var checked:  bool
        switch evt.id
        {
        case PrismCommands.Lens, PrismCommands.LensKey, PrismCommands.InformationKey:
            return false

        case PrismCommands.Information:
            name    = strings.cmd_Information
            toggle  = true
            checked = .infoSheet.isLocallyVisible()

        case PrismCommands.Compile:
            name = strings.cmd_Compile
            icon = .theme().icon(.Play, .themeMetrics().menuPopup_IconSize)

        case PrismCommands.FormatSource:
            name     = strings.cmd_FormatSource
            icon     = .icon(.Format)
            hidden   = .view != .Columns
            disabled = .formatStatus == .Working

        case PrismCommands.LiveEdit:
            name    = strings.cmd_LiveEdit
            toggle  = true
            checked = .liveEdit

        case PrismCommands.Columns:
            name    = strings.cmd_ShowColumns
            toggle  = true
            checked = .view == .Columns

        case PrismCommands.Stages:
            name    = strings.cmd_ShowStages
            toggle  = true
            checked = stages

        case PrismCommands.Compare:
            name    = strings.cmd_ShowCompare
            icon    = .icon(.Layout)
            toggle  = true
            checked = .view == .Compare

        case PrismCommands.PreviousStage:
            name     = strings.cmd_PreviousStage
            hidden   = not stages
            disabled = not micro or micro.step == 0

        case PrismCommands.NextStage:
            name     = strings.cmd_NextStage
            hidden   = not stages
            disabled = not micro or micro.step + 1 >= micro.inspection.steps.count

        case PrismCommands.ShowChange:
            name    = strings.cmd_ShowChange
            hidden  = not stages or not micro
            toggle  = true
            checked = micro != null and micro.showChange.isChecked()

        case PrismCommands.SourceLines:
            name    = strings.cmd_ShowSourceLines
            toggle  = true
            checked = .showSource

        case PrismCommands.Opcodes:
            name    = strings.cmd_ShowOpcodes
            toggle  = true
            checked = .listingForm == .Opcodes

        case PrismCommands.CopyListing:
            name     = strings.cmd_CopyListing
            disabled = not micro or not micro.listing.isListing()

        case PrismCommands.BuildConfiguration:
            name    = strings.cmd_BuildConfiguration
            toggle  = true
            checked = main.showingOptions

        case PrismCommands.RestoreBuild:
            name = strings.cmd_RestoreBuild

        case PrismCommands.PausePreview:
            name    = strings.cmd_PausePreview
            hidden  = main.kind == .Microcode
            toggle  = true
            checked = main.viewer != null and main.viewer.isPaused()

        default:
            return false
        }

        evt.name = name
        evt.updatedFields.add(.Name)
        if icon.isValid()
        {
            evt.icon = icon
            evt.updatedFields.add(.Icon)
        }

        if hidden
        {
            evt.hidden = true
            evt.updatedFields.add(.Hidden)
        }

        if disabled
        {
            evt.disabled = true
            evt.updatedFields.add(.Disabled)
        }

        if toggle
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        evt.accepted = true
        return true
    }

    // Runs one command of the window, and reports whether it was one.
    mtd runCommand(id: WndId)->bool
    {
        if .panels.count < 2 do
            return false

        let main  = .panels[0]
        let micro = main.micro()
        switch id
        {
        case PrismCommands.Lens:
            .openLens()

        case PrismCommands.Information:
            .toggleInformation()

        case PrismCommands.LensKey where not .typing():
            .openLens()

        case PrismCommands.InformationKey where not .typing():
            .toggleInformation()

        case PrismCommands.Compile:
            .compile(force: true)

        case PrismCommands.FormatSource:
            .format()

        case PrismCommands.LiveEdit:
            .setLiveEdit(not .liveEdit)

        case PrismCommands.Columns:
            .setView(.Columns)

        case PrismCommands.Stages:
            .setView(.Stages)

        case PrismCommands.Compare:
            .setView(.Compare)

        case PrismCommands.SourceLines:
            .setShowSource(not .showSource)

        case PrismCommands.Opcodes:
            .setListingForm(.listingForm == .Opcodes ? ListingForm.Readable : ListingForm.Opcodes)

        case PrismCommands.RestoreBuild:
            main.options.reset()

        case PrismCommands.PausePreview:
            main.setPaused(not main.viewer!.isPaused())

        // The steps answer their keys only stage by stage; elsewhere the keys belong to the work.
        case PrismCommands.PreviousStage where .view == .Stages and micro:
            micro!.stepBy(-1)

        case PrismCommands.NextStage where .view == .Stages and micro:
            micro!.stepBy(1)

        case PrismCommands.ShowChange where micro:
            micro!.showChange.setChecked(not micro.showChange.isChecked())
            micro.refreshListing()

        case PrismCommands.CopyListing where micro:
            Clipboard.setString(micro!.listing.copyText())

        case PrismCommands.BuildConfiguration:
            if .view == .Stages do
                .setView(.Columns)
            main.showOptions(not main.showingOptions)

        default:
            return false
        }

        return true
    }

    // Opens the lens; from then on the hint line stops teaching it.
    mtd openLens()
    {
        .doorKnown = true
        .refreshHints()
        .lens.open()
    }

    // Returns whether the keyboard is in a field that types the keys the lens and the sheet
    // answer without a chord.
    mtd typing()->bool
    {
        if .editor.hasFocus() do
            return true
        for panel in .panels where panel.options.editor.hasFocus() do
            return true
        return false
    }

    // Shows the source lines in every listing, or hides them.
    mtd setShowSource(show: bool)
    {
        .showSource = show
        .applyListingOptions()
    }

    // Writes the instructions of every listing as `form`.
    mtd setListingForm(form: ListingForm)
    {
        .listingForm = form
        .applyListingOptions()
    }

    // Gives every listing of the window the form and the source lines the reader chose, including
    // the listing of a viewer created since.
    mtd applyListingOptions()
    {
        for panel in .panels
        {
            let micro = panel.cachedMicro()
            if not micro do
                continue
            if micro.listing.form != .listingForm do
                micro.listing.setForm(.listingForm)
            if micro.listing.showSource != .showSource do
                micro.listing.setShowSource(.showSource)
        }
    }

    // Shows the sheet of readings about the main build, or hides it.
    mtd toggleInformation()
    {
        .refreshInformation()
        .infoSheet.toggle()
    }

    // Describes the main build in the sheet: the inspected function and its count, or the running
    // program; then what the compiler reported, and what the formatter did.
    mtd refreshInformation()
    {
        let strings = appStrings()
        let main    = .panels[0]
        let micro   = main.micro()
        var shown: const *Pipeline.Snapshot?
        if micro do
            shown = micro.shown()
        .infoSheet.clear()

        if micro and shown
        {
            let stage    = Pipeline.stageLabels()[Math.min(micro.stage, Pipeline.Stages.count - 1)]
            let function = shown.function.toString()
            let dot      = Utf8.lastIndexOf(function, '.'rune)
            .infoSheet.setTitle(dot == Swag.U64.Max ? function : function[dot + 1 to])
            .infoSheet.setIdentity(Pipeline.inspectedSignature(.editor.text()))
            .infoSheet.addFact(Format.toString("%", shown.instructions), shown.instructions == 1 ? strings.ui_InstructionOne : strings.ui_InstructionMany)
            .infoSheet.addReading(strings.ui_Stage, stage, mono: false)
            .infoSheet.addReading(strings.ui_Optimize, shown.optimize)
        }
        else
        {
            .infoSheet.setTitle(exampleName(.selectedExample))
            .infoSheet.setIdentity(exampleFileName(.selectedExample))
            if main.kind != .Microcode do
                .infoSheet.addReading(strings.ui_FrameSize, Format.toString("% × %", Pipeline.FrameChannel.Width, Pipeline.FrameChannel.Height))
        }

        let reading = main.viewer!.reading()
        if not reading.isEmpty() do
            .infoSheet.addReading(strings.ui_Build, reading)

        // The compiler's own lines about the build: each starts with what it did.
        if micro and micro.compiled and not micro.inspection.report.isEmpty()
        {
            .infoSheet.addSection(strings.ui_Compiler)
            for line in micro.inspection.report
            {
                let text  = line.toString()
                let space = Utf8.indexOf(text, ' 'rune)
                if space != Swag.U64.Max do
                    .infoSheet.addReading(text[until space], Latin1.trim(text[space to]))
            }
        }

        if .formatStatus != .None and .formatStatus != .Working
        {
            .infoSheet.addSection(strings.ui_Formatter)
            .infoSheet.addText(.reading())
            if .formatStatus == .Failed
            {
                var output: CompilerOutput
                output.parse(.formatResult.text)
                .infoSheet.addText(output.text)
            }
        }
    }
}

// Returns the label of a section of the lens: `label`, then the column it is about when `side`
// names one.
func sectionLabel(label: string, side: string)->String
{
    if side.count == 0 do
        return label
    return Format.toString("% · %", label, side)
}

// The families of choices the lens offers beside the commands.
enum LensChoice
{
    Example     // The example the source starts from.
    View        // The viewer a build shows.
    Stage       // The stage its instructions are listed at.
    Level       // Its optimization level.
    Preset      // The configuration it starts from.
}

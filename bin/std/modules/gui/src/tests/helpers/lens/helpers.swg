#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

const LensOpen     = "test.lens.open"

const LensSave     = "test.lens.save"

const LensTheme    = "test.lens.theme"

const LensHidden   = "test.lens.hidden"

const LensDisabled = "test.lens.disabled"

const LensCapture  = "test.lens.capture"

const LensArrow    = "test.lens.arrow"

// The lines of a small document a source answers from.
const LensLines: [5] string = ["if not .centerGroup do", "let group = .centerGroup", "return", "elif .fillCenterGroup do", "var width: f32"]

// Answers the command state of the test commands the way an application's actions do.
func lensCommandState(_: *Wnd, evt: IEvent)->bool
{
    if evt is CommandStateEvent as state where state.kind == .Compute
    {
        switch state.id
        {
        case LensOpen:     state.name = "Open…"
        case LensSave:     state.name = "Save as Image…"
        case LensTheme:    state.name = "Center Theme"
        case LensHidden:   state.name = "Hidden Command"
        case LensDisabled: state.name = "Center Disabled"
        case LensCapture:  state.name = "Capture Area"
        case LensArrow:    state.name = "Arrow"
        default:           return false
        }

        state.updatedFields.add(.Name)
        if state.id == LensSave
        {
            state.updatedFields.add(.Shortcut)
            state.shortcut = "Ctrl S"
        }

        if state.id == LensTheme
        {
            state.updatedFields.add(.Checked)
            state.checked = true
        }

        if state.id == LensHidden
        {
            state.updatedFields.add(.Hidden)
            state.hidden = true
        }

        if state.id == LensDisabled
        {
            state.updatedFields.add(.Disabled | .Reason)
            state.disabled = true
            state.reason   = "Nothing selected"
        }

        state.accepted = true
        return true
    }

    return false
}

// Builds a lens over the host root, with commands in two families and a source of lines.
func lensSetup(host: *Testing.HeadlessHost)->*Lens.View
{
    host.root.backgroundStyle = .Window
    host.root.hookOnEvent     = &lensCommandState

    with let lens = Lens.View.create(&host.root)
    {
        .addCommands("File", [LensOpen, LensSave, LensHidden])
        .addCommands("View", [LensTheme, LensDisabled])
        .addSource(.Line, func(results)
        {
            var section: *Lens.Section?
            for line, index in LensLines
            {
                if not Lens.match(results.query, line).matched do
                    continue
                if not section do
                    section = results.addSection("In this file")
                with let entry = section.addEntry(line)
                {
                    .lead      = Format.toString("%", index + 37)
                    .monoTitle = true
                }
            }

            if section do
                section.count = cast(u32, section.entries.count)
        })
    }

    return lens
}

func lensFooterActionPosition(lens: *Lens.View)->Math.Point
{
    let metrics = lens.themeMetrics()
    let bounds  = lens.clientRect()
    let top     = lens.input.position.y
    let width   = Math.min(metrics.lens_Width, bounds.width - 2 * metrics.floating_Inset)
    let last    = lens.rows.back()
    let content = last.top + last.height + metrics.lens_RowInset
    let fixed   = metrics.lens_InputHeight + metrics.lens_FooterHeight + 2 * metrics.separator_HairlineSize
    let room    = Math.max(Math.min(bounds.height * metrics.lens_MaxHeightRatio, bounds.height - metrics.floating_Inset - top), fixed)
    let height  = Math.min(fixed + content, room)
    return {bounds.horzCenter() + width * 0.5 - metrics.lens_TextInset - metrics.keycap_Padding,
            top + height - metrics.lens_FooterHeight * 0.5}
}

// Adds to `results` the ways of viewing a file as one row of segments, the second in force and
// the third unavailable; choosing one writes its index in `chosen`.
func addViewAsSection(results: *Lens.Results, chosen: *u64)
{
    let views = results.addSection("View As")
    views.inline = true
    for title, index in ["Code", "Plain Text", "Hexadecimal", "Binary"]
    {
        with let entry = views.addEntry(title)
        {
            .checked  = index == 1
            .disabled = index == 2
            .run      = func|chosen, index|() { chosen[] = index }
        }
    }
}

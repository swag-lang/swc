#global public
#global namespace Viewer

using Core, Gui

// The rows one viewer adds to the lens of its window, under its own name.
//
// The window is the document and keeps no toolbar, so every command a viewer offers — a button of
// its floating bar, a choice of one of its menus, its options — is also a row of the lens. The
// host builds one for each query and hands it to the viewer's [[Viewer.LensSource]]; a row joins
// the answer only when the query names it or names the viewer, so a viewer describes every
// command it has and the lens keeps what was asked for.
struct LensEntries
{
    public
    {
        results: *Lens.Results     // Answer the rows join.
        label:   String            // Section the rows stand under: the name of the viewer.
        query:   String            // What the reader typed, without its prefix.
    }

    section: *Lens.Section?
}

impl LensEntries
{
    // Starts the rows of the viewer named `label` for `results`.
    func create(results: *Lens.Results, label: string)->LensEntries => LensEntries{results: results, label: label, query: results.query}

    // Adds a row titled `title` that runs `run` once the lens has left the screen, and returns it.
    //
    // `shortcut` names the key that runs the same command, written at the end of the row; a
    // `checked` row is the choice or the setting in force, and a `disabled` one shows faint and
    // cannot be chosen. Returns `null` when the query answers neither the row nor the viewer.
    #[Swag.Discardable]
    mtd add(title: string, run: func||(), checked = false, disabled = false, shortcut: string = "")->*Lens.Entry?
    {
        if not Lens.match(.query, title).matched and not Lens.match(.query, .label).matched do
            return null
        if not .section do
            .section = .results.addSection(.label)

        with let entry = .section.addEntry(title)
        {
            .run        = run
            .checked    = checked
            .disabled   = disabled
            .detail     = shortcut
            .monoDetail = true
        }

        return entry
    }

    // Adds one of the zoom commands every reading viewer shares, at the zoom `percent` in force,
    // running `run` with the level it asks for already captured.
    //
    // A reading viewer adds all three: one notch in, one notch out, and back to the actual size;
    // see [[Viewer.zoomTarget]] for the level each one asks for.
    #[Swag.Discardable]
    mtd addZoom(command: ZoomCommand, percent: u32, run: func||())->*Lens.Entry?
    {
        let texts = appStrings()
        switch #complete command
        {
        case .In:    return .add(texts.cmd_ZoomIn, run, disabled: percent >= MaxZoom, shortcut: Input.formatKeyShortcut(.Control, .OemPlus))
        case .Out:   return .add(texts.cmd_ZoomOut, run, disabled: percent <= MinZoom, shortcut: Input.formatKeyShortcut(.Control, .OemMinus))
        case .Reset: return .add(texts.cmd_ZoomReset, run, checked: percent == 100, shortcut: Input.formatKeyShortcut(.Control, .D0))
        }
    }
}

// The zoom commands every reading viewer offers in the lens.
enum ZoomCommand
{
    In        // One notch larger.
    Out       // One notch smaller.
    Reset     // The actual size.
}

// Returns the zoom `command` asks for from `percent`.
func zoomTarget(command: ZoomCommand, percent: u32)->u32
{
    switch #complete command
    {
    case .In:    return zoomIn(percent)
    case .Out:   return zoomOut(percent)
    case .Reset: return 100
    }
}

// Answers the lens with the rows of one viewer.
//
// The host calls it for every query while the viewer is the one on screen. Each row runs after
// the lens has closed, with the viewer's floating commands on screen, so a menu or a sheet a row
// opens from one of the viewer's buttons opens where it always does.
alias LensSource = func||(*LensEntries)

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
        results: *Lens.Results     // Answer the rows join, holding the query they answer.
        label:   String            // Section the rows stand under: the name of the viewer.

        // What the reader typed, without its prefix: the query of `results`.
        readonly query: String
    }

    theme:        *Theme
    section:      *Lens.Section?
    labelAnswers: bool     // Whether the query names the viewer, which brings every row.
}

impl LensEntries
{
    // Starts the rows of the viewer named `label` for `results`, borrowing `theme` for their glyphs.
    // The theme must outlive these entries.
    //
    // A viewer adds dozens of rows for each keystroke, and the label is the same for all of them,
    // so it is matched once here; every row is matched against the query `results` folded once.
    func create(results: *Lens.Results, label: string, theme: *Theme)->LensEntries
    {
        return LensEntries{results: results,
                           label: label,
                           query: results.query,
                           theme: theme,
                           labelAnswers: Lens.match(results.folded, label).matched}
    }

    // Adds a row titled `title` with the shared action `icon`, running `run` after the lens closes.
    //
    // `shortcut` names the key that runs the same command, written at the end of the row; a
    // `checked` row is the choice or the setting in force, and a `disabled` one shows faint and
    // cannot be chosen. Returns `null` when the query answers neither the row nor the viewer.
    // A stable `bindId` exposes the action for user key bindings and `defaultKey` records its chord.
    #[Swag.Discardable]
    mtd add(title: string, icon: ThemeIcons, run: func||(), checked = false, disabled = false, shortcut: string = "",
            defaultKey: KeyShortcut = {}, bindId: WndId = "")->*Lens.Entry?
    {
        // The row takes the answer of its title along, so the lens does not match it again.
        var found = Lens.match(.results.folded, title)
        if not .labelAnswers and not found.matched do
            return null
        if not .section do
            .section = .results.addSection(.label)

        let glyph      = .theme.icon(icon, .theme.metrics.menuPopup_IconSize)
        with let entry = .section.addEntry(title, #move found)
        {
            .glyph      = glyph
            .run        = run
            .checked    = checked
            .disabled   = disabled
            .bindId     = bindId
            .defaultKey = defaultKey
            if defaultKey.key == .OemPlus do
                .alternateDefaultKey = {modifiers: defaultKey.modifiers, key: .Add}
            elif defaultKey.key == .OemMinus do
                .alternateDefaultKey = {modifiers: defaultKey.modifiers, key: .Subtract}
            .detail     = defaultKey.key == .None ? String.from(shortcut) : Input.formatKeyShortcut(defaultKey.modifiers, defaultKey.key)
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
        case .In:
            return .add(texts.cmd_ZoomIn, .ZoomIn, run, disabled: percent >= MaxZoom,
                        defaultKey: {modifiers: .Control, key: .OemPlus}, bindId: "scope.viewer.zoomIn")
        case .Out:
            return .add(texts.cmd_ZoomOut, .ZoomOut, run, disabled: percent <= MinZoom,
                        defaultKey: {modifiers: .Control, key: .OemMinus}, bindId: "scope.viewer.zoomOut")
        case .Reset:
            return .add(texts.cmd_ZoomReset, .ActualSize, run, checked: percent == 100,
                        defaultKey: {modifiers: .Control, key: .D0}, bindId: "scope.viewer.zoomReset")
        }
    }
}

// Returns the words of a lens row made from `title`, a format with one `%`, and `value`, the place
// it goes to, followed by `typed` when it spells that place otherwise, so the row answers the
// query it came from.
func jumpRowText(title: string, value: string, typed: string)->String
{
    let query = Latin1.trim(typed)
    if Utf8.compare(query, value, .Latin1NoCase) == 0 do
        return Format.toString(title, value)
    return Format.toString(title, Format.toString("% (%)", value, query))
}

// Tab stops a reader can choose in text and code, in space advances.
const TabWidths: [3] s32 = [2, 4, 8]

// Returns the words of the lens row choosing the tab stop `width`, after `title`.
func tabWidthRowText(title: string, width: s32)->String => Format.toString("% · %", title, width)

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

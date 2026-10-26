#global public
#global namespace OptionSheet

using Core, Pixel

// Fills one page of an option sheet with its rows.
//
// The sheet calls the builder of a page each time it shows the page: when it opens, when the
// reader comes back to it, and after every row that changed something. Build the rows from the
// current state of what they describe, so the value a row shows is always the one in force.
alias Builder = func||(*Page)

// Identifies what a row of an option sheet shows and does.
enum RowKind
{
    Link        // Names a setting with its current value, and opens the page of its choices.
    Choice      // One value of a setting, checked when it is the value in force.
    Toggle      // A setting that is on or off, switched in place.
    Stepper     // A value stepped down or up in place.
    Action      // A command run at once, such as resetting a setting.
    Heading     // Title of the group of rows that follows; never focused.
}

// One row of an option sheet page, as its builder described it.
struct Row
{
    public readonly
    {
        kind:        RowKind
        label:       RichString     // Wording of the row.
        value:       RichString     // Current value of a link or a stepper, written after the label.
        detail:      RichString     // Second line under the wording of a choice, or empty.
        icon:        Icon           // Glyph before a link or after a choice; invalid for none.
        checked:     bool           // Whether a choice is the value in force, or a toggle is on.
        disabled:    bool           // Whether the row cannot be activated.
        canDecrease: bool           // Whether a stepper can step down.
        canIncrease: bool           // Whether a stepper can step up.
        closesSheet: bool           // Whether an action closes the sheet and runs once it is gone.
    }

    open:   Builder?
    choose: (func||())?
    toggle: (func||(bool))?
    step:   (func||(s32))?
    run:    (func||())?
}

impl Row
{
    // Reports whether the keyboard and the pointer can land on the row.
    mtd const isFocusable()->bool => .kind != .Heading

    // Reports whether activating the row would do something.
    mtd const isActive()->bool => .kind != .Heading and not .disabled

    // Fills `page` with the rows of the page this link opens, as the sheet does when the reader activates it.
    //
    // This is how a test reads what a sheet would show two pages deep without opening it.
    mtd const buildLink(page: *Page)
    {
        Swag.assert(.kind == .Link, "only a link opens a page")
        page.title = .label.raw
        let build = unwrap .open
        build(page)
    }
}

// The rows of one page of an option sheet, in display order.
struct Page
{
    public
    {
        // Title of the page, written in its header.
        //
        // A page opened from a link takes the wording of that link. The first page has no header
        // when the sheet is anchored to its button, and is titled [[Gui.Strings.optionSheet_Title]]
        // elsewhere unless its builder names it.
        title: String

        readonly rows: Array'Row     // Rows added by the builder, in display order.
    }
}

impl Page
{
    // Adds a row naming a setting and its current value, which opens the page `build` fills.
    //
    // The opened page is titled `label`. Its builder runs each time the page is shown, so it can
    // describe choices that depend on the moment, such as the tracks of the file being played.
    mtd addLink(label: string, value: string, build: Builder, icon: Icon = {}, disabled = false)
    {
        with var row: Row
        {
            .kind = .Link
            .label.set(label)
            .value.set(value)
            .icon     = icon
            .disabled = disabled
            .open     = build
        }

        .rows.add(#move row)
    }

    // Adds one value of a setting, checked when it is the value in force.
    //
    // `choose` applies the value. `detail` is written on a second line under the wording, such as
    // the channels and rate of a sound track. `icon` is written after the wording, for a value a
    // glyph already names elsewhere in the interface.
    mtd addChoice(label: string, checked: bool, choose: func||(), detail: string? = null, icon: Icon = {}, disabled = false)
    {
        with var row: Row
        {
            .kind = .Choice
            .label.set(label)
            .detail.set(detail orelse "")
            .icon     = icon
            .checked  = checked
            .disabled = disabled
            .choose   = choose
        }

        .rows.add(#move row)
    }

    // Adds a setting that is on or off; `toggle` receives the state the reader asked for.
    mtd addToggle(label: string, on: bool, toggle: func||(bool), disabled = false)
    {
        with var row: Row
        {
            .kind = .Toggle
            .label.set(label)
            .checked  = on
            .disabled = disabled
            .toggle   = toggle
        }

        .rows.add(#move row)
    }

    // Adds a value stepped down or up in place, showing `value`.
    //
    // `step` receives `-1` or `1` for one step, and `-10` or `10` when Shift is held. The sheet
    // does not clamp anything: the callback owns the range, and `canDecrease` and `canIncrease`
    // say whether a step is still possible in each direction.
    mtd addStepper(label: string, value: string, step: func||(s32), canDecrease = true, canIncrease = true)
    {
        with var row: Row
        {
            .kind = .Stepper
            .label.set(label)
            .value.set(value)
            .canDecrease = canDecrease
            .canIncrease = canIncrease
            .step        = step
        }

        .rows.add(#move row)
    }

    // Adds a command run at once, such as resetting a setting to its default.
    //
    // An action that opens something else — a dialog, another window — passes `closesSheet`: the
    // sheet closes first, and `run` runs once it has left the screen.
    mtd addAction(label: string, run: func||(), disabled = false, closesSheet = false)
    {
        with var row: Row
        {
            .kind = .Action
            .label.set(label)
            .disabled    = disabled
            .closesSheet = closesSheet
            .run         = run
        }

        .rows.add(#move row)
    }

    // Adds a row bound to the command `id` of `target`, described and run by the command system.
    //
    // The row takes its wording and its state from what `target` computes for the command, the way a
    // menu entry made with [[Gui.MenuCtrl.addItem]] does: a command of an exclusive group is a
    // choice, a checkable one a switch, any other an action. Activating the row sends the command to
    // `target` at once. A hidden command adds nothing. Like a menu entry, the row borrows `id`.
    mtd addCommand(id: WndId, target: *Wnd)
    {
        let state = target.sendComputeCommandStateEvent(id)
        if state.updatedFields.has(.Hidden) and state.hidden do
            return

        let label    = commandLabel(&state)
        let disabled = state.updatedFields.has(.Disabled) and state.disabled
        let checked  = state.updatedFields.has(.Checked) and state.checked
        if state.updatedFields.has(.RenderingHint) and state.renderingHint.has(.ExclusiveGroup) do
            .addChoice(label, checked, func|target, id|() { target.sendCommandEvent(id) }, disabled: disabled)
        elif state.updatedFields.has(.Checked) do
            .addToggle(label, checked, func|target, id|(_) { target.sendCommandEvent(id) }, disabled: disabled)
        else do
            .addAction(label, func|target, id|() { target.sendCommandEvent(id) }, disabled: disabled)
    }

    // Adds a link worded `label` to a page holding the commands `ids` of `target`.
    //
    // The link shows the wording of the command that is checked, which is how an exclusive group of
    // commands names its choice in force. The page borrows `ids`: give it storage that outlives the
    // sheet, such as a constant array.
    mtd addCommandLink(label: string, ids: const [..] WndId, target: *Wnd, icon: Icon = {})
    {
        var value: String
        for id in ids
        {
            let state = target.sendComputeCommandStateEvent(id)
            if state.updatedFields.has(.Checked) and state.checked
            {
                value = commandLabel(&state)
                break
            }
        }

        .addLink(label,
                 value,
                 func|ids, target|(page)
                 {
                     for id in ids do
                         page.addCommand(id, target)
                 },
                 icon)
    }

    // Adds the title of the group of rows that follows.
    mtd addHeading(label: string)
    {
        with var row: Row
        {
            .kind = .Heading
            .label.set(label)
        }

        .rows.add(#move row)
    }

    // Reports whether the page holds choices and nothing else but their headings.
    //
    // That is the only page a choice may leave on its own: anywhere else the reader came to
    // adjust several things in turn.
    mtd const isChoiceList()->bool
    {
        var hasChoice = false
        for row in .rows
        {
            switch row.kind
            {
            case .Choice:  hasChoice = true
            case .Heading: break
            default:       return false
            }
        }

        return hasChoice
    }
}

// Returns the wording a command state gives its command, preferring its long form like a menu does.
private func commandLabel(state: const *CommandStateEvent)->string
{
    if state.updatedFields.has(.LongName) do
        return state.longName
    return state.name
}

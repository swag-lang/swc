#global public
#global namespace Viewer

using Core, Gui

// Width reserved for a page counter, independent of its current number of digits.
const PageReadoutWidth = 96.0

// Returns the width of the previous, current/total and next group.
func pageControlWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + PageReadoutWidth

// Formats a zero-based page index and its total; an empty document reads 0 / 0.
func pageText(index, count: u64)->String => Format.toString("% / %", index < count ? index + 1 : count, count)

// Returns the page direction requested by Ctrl Page Up/Down, or zero for another key.
func pageKeyDirection(key: const *KeyEvent)->s32
{
    if key.kind != .Pressed or key.modifiers != .Control do
        return 0
    switch key.key
    {
    case .PageUp:   return -1
    case .PageDown: return 1
    default:        return 0
    }
}

// Creates one page arrow; a negative direction means previous and a positive one means next.
func createPageStep(parent: *Wnd, direction: s32)->*IconButton
{
    with let result = createActionButton(parent, direction < 0 ? .ChevronLeft : .ChevronRight)
    {
        .dockStyle = .Left
        .toolTip   = direction < 0 ? appStrings().ui_PreviousPage : appStrings().ui_NextPage
    }

    return result
}

// Kind of destination named by a paginated reader.
enum PageUnit { Page, Slide, Chapter, Sheet, Frame }

private func pageCommand(unit: PageUnit)->string
{
    switch unit
    {
    case .Slide:   return appStrings().ui_GoToSlide
    case .Chapter: return appStrings().ui_GoToChapter
    case .Sheet:   return appStrings().ui_GoToSheet
    case .Frame:   return appStrings().ui_GoToFrame
    default:       return appStrings().ui_GoToPage
    }
}

// Returns the zero-based destination of a one-based address, or U64.Max for an invalid address.
func numberedPage(text: string, count: u64)->u64
{
    let typed = Latin1.trim(text)
    for character in typed where not Latin1.isDigit(character) do
        return Swag.U64.Max
    let number = catch StrConv.parseU64(typed) { return Swag.U64.Max }
    if number.eat != typed.count or number.ovf or not number.value or number.value > count do
        return Swag.U64.Max
    return number.value - 1
}

// The same arrows and focusable counter navigate every paginated reader.
// PDF can also resolve authored labels, such as the Roman numerals in a preface.
struct PageSteps
{
    late
    {
        previousButton: *IconButton
        nextButton:     *IconButton
        counter:        *IconButton
        private turnPage:   func||(s32)
        private selectPage: func||(u64)
    }

    unit: PageUnit
    ordinal, totalSteps: u64
    labelAt: (func||(u64)->string)?
    resolveLabel: (func||(string)->u64)?
}

impl PageSteps
{
    private mtd step(parent: *Wnd, direction: s32)->*IconButton
    {
        let button = createPageStep(parent, direction)
        button.sigPressed += func|steps = me, direction|(_) { steps.turnPage(direction) }
        return button
    }

    // Creates previous, the direct address, and next in reading and keyboard order.
    mtd create(parent: *Wnd, id: WndId, unit: PageUnit, turn: func||(s32), select: func||(u64))->*IconButton
    {
        .unit           = unit
        .turnPage       = turn
        .selectPage     = select
        .previousButton = .step(parent, -1)
        let height      = themeActionButtonSize(parent.themeMetrics())
        with .counter = IconButton.create(parent, {}, {0, 0, PageReadoutWidth, height}, id, .CenterContent)
        {
            .dockStyle = .Left
            .toolTip   = pageCommand(unit)
            .setForm(.Rectangle)
            .style.setFont(parent.theme().createDefaultFontFs(12), .Regular)
            .sigPressed += func|steps = me|(_) { steps.promptGoToPage() }
        }
        .nextButton = .step(parent, 1)
        return .counter
    }

    // Keeps the counter and the address dialog on the same range. Readers may supply a labelled readout.
    mtd setPageRange(index, count: u64)
    {
        .ordinal    = index
        .totalSteps = count
        .counter.toolTip = pageCommand(.unit)
        .counter.setText(index < count ? pageText(index, count) : "")
    }

    // Resolves a page number or a reader-specific label.
    mtd typedPageIndex(text: string)->u64
    {
        let index = numberedPage(text, .totalSteps)
        if index < .totalSteps or not .resolveLabel do
            return index
        let typed = Latin1.trim(text)
        for character in typed where not Latin1.isDigit(character) do
            return .resolveLabel(typed)
        return Swag.U64.Max
    }

    // Selects the typed destination if it is in range.
    mtd goToTypedPage(text: string)->bool
    {
        let index = .typedPageIndex(text)
        if index >= .totalSteps do
            return false
        .selectPage(index)
        return true
    }

    // Creates the same validated address sheet for mouse, keyboard and lens activation.
    mtd createPageDialog()->*EditDlg
    {
        var options: EditDlgOptions
        options.title = pageCommand(.unit)
        let label = .labelAt and .ordinal < .totalSteps ? .labelAt(.ordinal) : ""
        let initial = label.count ? String.from(label) : Format.toString("%", .ordinal + 1)
        let help = label.count ? Format.toString(appStrings().ui_PageNumberOrLabel, .totalSteps, label) :
                                 Format.toString(appStrings().ui_PageNumberRange, .totalSteps)
        options.text = initial
        options.message = help
        let dialog = EditDlg.createSingleLine(unwrap .counter.surface, options)
        dialog.edit!.setValidator(func|steps = me|(field)->EditBoxCheckResult
        {
            return steps.typedPageIndex(field.text()) < steps.totalSteps ? .Valid : .InvalidVisible
        })
        dialog.validateResult = func|steps = me, dialog|(_, result)->bool
        {
            return result != Dialog.BtnOk or steps.goToTypedPage(dialog.text())
        }
        return dialog
    }

    // Presents the address sheet only while the reader has a destination.
    mtd promptGoToPage()
    {
        if .counter.surface and .totalSteps do
            discard .createPageDialog().doModal()
    }

    // Publishes direct navigation with the same wording as the counter.
    mtd addPageJump(entries: *LensEntries, id: string)
    {
        entries.add(pageCommand(.unit), .GoTo, func|steps = me|() { steps.promptGoToPage() },
                    disabled: .totalSteps <= 1, bindId: id)
    }

    // Shows or hides the three controls together. Returns whether their layout changed.
    mtd showSteps(visible: bool)->bool
    {
        if .counter.isLocallyVisible() == visible and .previousButton.isLocallyVisible() == visible and .nextButton.isLocallyVisible() == visible do
            return false
        .previousButton.show(visible)
        .counter.show(visible)
        .nextButton.show(visible)
        return true
    }

    // Enables the available directions and removes the group when there is nowhere to go.
    mtd updateSteps(index, count: u64)->bool
    {
        .setPageRange(index, count)
        .previousButton.enable(index < count and index > 0)
        .nextButton.enable(index < count and index + 1 < count)
        return .showSteps(count > 1)
    }
}

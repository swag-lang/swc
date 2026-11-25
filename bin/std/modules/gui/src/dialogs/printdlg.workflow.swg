#global internal
#global namespace PrintDlg

using Core, Pixel, Gui.Print

private const BackButton:   WndId = "gui.print.settings"
private const WorkFinished: WndId = "gui.print.finished"
private const PreviewDpi          = 96.0'f32
private const PreviewHeight       = 336.0'f32
private const Papers              = [Paper.A4, Paper.Letter, Paper.Legal]
private const Placements          = [Placement.Fit, Placement.Center, Placement.Actual]

private struct PreparedPreview
{
    layout: Layout
    image:  Image
}

private struct PreviewPages
{
    page: s64
    last: s64

    late
    {
        layout:   *Layout
        view:     *ImageView
        count:    *Label
        previous: *IconButton
        next:     *IconButton
    }
}

impl PreviewPages
{
    mtd showPage(requested: s64)
    {
        let target = Math.clamp(requested, 0, .last)
        if target == .page do
            return
        .page = target
        .previous.enable(target > 0)
        .next.enable(target < .last)
        .count.setText(Format.toString(strings().print_PreviewPage, target + 1, .layout.pageCount))
        catch .view.setImage(.layout.render(cast(u64, target), PreviewDpi))
        {
            .view.clear()
            reportError(unwrap .view.surface, Swag.err)
        }
    }
}

func createWorkDialog(from: *Surface, title: string)->*Dialog
{
    let dlg      = Dialog.create(from, title: title)
    let progress = ProgressBar.create(dlg.createContentView(), flags: .Indeterminate)
    progress.dockStyle = .Top
    dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel, true)
    dlg.fitHeightToContent(progress.measure({}).preferred.y)
    dlg.surface!.center(from)
    return dlg
}

internal func(T) runWork(from: *Surface, title: string, work: func||()->T fail)->T fail
{
    var task: Swag.Task'T
    task.submit(work)
    if not task.isDone()
    {
        let dlg    = createWorkDialog(from, title)
        let cancel = unwrap dlg.cancelButton()

        // Only the worker may close the box while it owns document or spooler state.
        dlg.validateResult = func|&task, cancel|(_, result)
        {
            if result == WorkFinished do
                return true
            task.cancel()
            cancel.enable(false)
            return false
        }

        if dlg.runModal(func|&task, dlg|(_)
        {
            if task.isDone() do
                dlg.closeWithResult(WorkFinished)
        }) != WorkFinished
        {
            task.cancel()
            task.wait()
            fail PrintError{.Cancelled}
        }
    }

    // A worker may finish an uninterruptible operation after the user asks to stop.
    if task.isCancelled() and not task.hasFailed() do
        fail PrintError{.Cancelled}
    return try task.take()
}

internal func reportError(from: *Surface, error: any?)
{
    let tr      = strings()
    var message = tr.print_Failed
    if error is PrintError as failure
    {
        switch failure.kind
        {
        case .InvalidPage:        message = tr.print_InvalidPage
        case .InvalidRange:       message = tr.print_InvalidRange
        case .UnsupportedPaper:   message = tr.print_UnsupportedPaper
        case .PrinterUnavailable: message = tr.print_PrinterUnavailable
        case .PrinterFailed:      message = tr.print_PrinterFailed
        case .Cancelled:          return
        }
    }

    MessageDlg.error(from, message, error)
}

internal func show(from: *Surface, document: *Document, sourcePath: string)
{
    let devices = #move catch runWork(from, strings().print_FindingPrinters, func()->Array'Printer fail
    {
        return printers()
    })
    {
        reportError(from, Swag.err)
        return
    }

    showDocument(from, document, sourcePath, devices.toSlice())
}

internal func showDocument(from: *Surface, document: *Document, sourcePath: string, devices: const [..] Printer)
{
    var destination = 0'u32
    for &device, i in devices where device.isDefault
    {
        destination = cast(u32, i) + 1
        break
    }

    var options: JobOptions
    while settings(from, document.kind, devices, &destination, &options)
    {
        var printer: const *Printer?
        if destination do
            printer = &devices[destination - 1]

        if not runJob(from, document, sourcePath, printer, &options) do
            return
    }
}

// Returns true when the workflow should go back to the settings.
private func runJob(from: *Surface, document: *Document, sourcePath: string, printer: const *Printer?, options: *JobOptions)->bool
{
    let localSheet = pdfSheet(options.setup)
    var sheet      = localSheet
    var pageRange: String
    while true
    {
        var prepared = #move catch runWork(from, strings().print_Preparing, func|document, sheet, setup = options.setup|()->PreparedPreview fail
        {
            var result: PreparedPreview
            result.layout = #move try prepare(document, sheet, setup)
            result.image  = #move try result.layout.render(0, PreviewDpi)
            return #move result
        })
        {
            if Swag.err is PrintError as failure where failure.kind == .Cancelled do
                return false
            reportError(from, Swag.err)
            return true
        }

        let answer = preview(from, &prepared, options, &pageRange, printer != null, sheet != localSheet)
        if answer != Dialog.BtnOk do
            return answer == BackButton

        let plan = &prepared.layout
        let job  = options[]
        if let device = printer
        {
            let submission = catch runWork(from, strings().print_Sending, func|device, plan, job|()->Submission fail
            {
                return try printNative(unwrap device, plan, job)
            })
            {
                reportError(from, Swag.err)
                return false
            }

            if submission.submitted do
                return false
            sheet = submission.sheet
            continue
        }

        let target = choosePdf(from, document.name, sourcePath)
        if target.isEmpty() do
            return true
        let fileName = target.toString()
        discard catch runWork(from, strings().print_SavingPdf, func|plan, job, fileName|()->bool fail
        {
            try savePdf(plan, job, fileName)
            return true
        })
        {
            reportError(from, Swag.err)
        }

        return false
    }
}

private func settings(from: *Surface, kind: ContentKind, devices: const [..] Printer, destination: *u32, options: *JobOptions)->bool
{
    let tr  = strings()
    let dlg = FormDlg.create(from, {title: tr.print_Title, confirmButtonText: tr.print_Preview})
    let destinations = dlg.form.addChoiceField(tr.print_Destination)
    destinations.addItem(tr.print_SavePdf)
    for &device in devices do
        destinations.addItem(device.name)
    destinations.setSelectedIndex(destination[], notify: false)

    let paper = dlg.form.addChoiceField(tr.print_Paper)
    paper.addItem(tr.print_A4)
    paper.addItem(tr.print_Letter)
    paper.addItem(tr.print_Legal)
    paper.setSelectedIndex(cast(u32, options.setup.paper), notify: false)

    let orientation = dlg.form.addRowChoice()
    orientation.toolTip = tr.print_Orientation
    orientation.updateFlags(.Segmented)
    orientation.addItem(tr.print_Portrait)
    orientation.addItem(tr.print_Landscape)
    orientation.setSelectedIndex(options.setup.landscape ? 1 : 0, notify: false)

    // The trailing choice is measured at its natural width, so each segment needs its own share.
    let face = unwrap orientation.font().regular
    let pad  = 2 * orientation.themeMetrics().comboBox_Padding
    var widths: Array'f32
    widths.add(Math.ceil(Painter.measureString(tr.print_Portrait, face).width + pad))
    widths.add(Math.ceil(Painter.measureString(tr.print_Landscape, face).width + pad))
    orientation.setSegmentWidths(widths)

    let margin = dlg.form.addTextField(tr.print_Margins, Format.toString("%", cast(u32, Math.round(options.setup.margin * MillimetersPerInch / PointsPerInch))))
    margin.setUnsignedIntegerRange(0, 75)
    margin.setUnit("mm")

    var placement: *ComboBox?
    if kind != .Text
    {
        let scale = dlg.form.addChoiceField(tr.print_Placement)
        scale.updateFlags(.Segmented)
        scale.addItem(tr.print_Fit)
        scale.addItem(tr.print_Center)
        scale.addItem(tr.print_Actual)
        scale.setSelectedIndex(cast(u32, options.setup.placement), notify: false)
        placement = scale
    }

    var copies: *EditBox?
    if devices.count
    {
        let field = dlg.form.addTextField(tr.print_Copies, Format.toString("%", options.copies))
        field.setUnsignedIntegerRange(1, 999)
        field.enable(destination[] != 0)
        destinations.sigChanged += func|field|(_, index) { field.enable(index != 0) }
        copies = field
    }

    dlg.validateResult = func|destinations, paper, orientation, margin, placement, copies, destination, options|(_, id)
    {
        if id != Dialog.BtnOk do
            return true
        if not margin.isValid() or (destinations.selectedIndex and copies and not copies.isValid()) do
            return false
        destination[]           = destinations.selectedIndex
        options.setup.paper     = Papers[paper.selectedIndex]
        options.setup.landscape = orientation.selectedIndex != 0
        options.setup.margin    = cast(f32, expect StrConv.toNum'u32(margin.text())) * PointsPerInch / MillimetersPerInch
        if placement do
            options.setup.placement = Placements[placement.selectedIndex]
        options.copies = destination[] and copies ? expect StrConv.toNum'u32(copies.text()) : 1
        return true
    }

    return dlg.doModal() == Dialog.BtnOk
}

internal func parseRange(value: string, pageCount: u64)->{first: u64, end: u64} fail
{
    if not value.count do
        return {0, pageCount}

    let parts = Tokenize.split(value, '-'u8, removeEmpty: false)
    if not parts.count or parts.count > 2 do
        fail PrintError{.InvalidRange}

    let first = catch StrConv.toNum'u64(Latin1.trim(parts[0])) orelse 0
    let last  = parts.count == 2 ? catch StrConv.toNum'u64(Latin1.trim(parts[1])) orelse 0 : first
    if not first or first > last or last > pageCount do
        fail PrintError{.InvalidRange}
    return {first - 1, last}
}

private func preview(from: *Surface, prepared: *PreparedPreview, options: *JobOptions, pageRange: *String, isPrinter, adjusted: bool)->WndId
{
    let tr       = strings()
    let layout   = &prepared.layout
    let dlg      = FormDlg.create(from, {title: tr.print_Preview, confirmButtonText: isPrinter ? tr.print_Print : tr.print_SavePdf})
    let settings = IconButton.createQuiet(dlg, BackButton, menu: false)
    settings.setQuietText(tr.print_Settings)
    settings.sigPressed += func|dlg|(_) { dlg.closeWithResult(BackButton) }
    dlg.setLeadingControl(settings)

    if adjusted
    {
        let notice = Label.create(dlg.form, tr.print_AdjustedPreview, flags: .SecondaryText | .WordWrap | .AutoHeight)
        notice.setTextAlignment(.Left, .Top)
        dlg.form.addField("", notice)
    }

    let view  = ImageView.create(dlg.form, {0, 0, 0, PreviewHeight})
    let inset = dlg.themeMetrics().dialog_BtnPadding * 2
    view.padding = {inset, inset, inset, inset}
    view.setImage(prepared.image)
    dlg.form.addField("", view)
    var range: *EditBox?
    var pages: PreviewPages
    if layout.pageCount > 1
    {
        addPageNavigation(dlg, view, layout, &pages)
        range = dlg.form.addTextField(tr.print_Range, pageRange[], placeholder: tr.print_AllPages, help: tr.print_RangeHelp)
    }

    dlg.validateResult = func|dlg, layout, options, range, pageRange|(_, id)
    {
        if id != Dialog.BtnOk do
            return true
        let owner = unwrap dlg.surface
        let value = range ? range.text() : ""
        let pages = catch parseRange(value, layout.pageCount)
        {
            reportError(owner, Swag.err)
            range?.setFocus()
            return false
        }

        let clips = catch layout.clips(pages.first, pages.end)
        {
            reportError(owner, Swag.err)
            return false
        }

        if clips and MessageDlg.confirm(owner, strings().print_Clipping) != Dialog.BtnYes do
            return false
        options.first = pages.first
        options.end   = pages.end
        pageRange[]   = value
        return true
    }

    return dlg.doModal()
}

private func addPageNavigation(dlg: *FormDlg, view: *ImageView, layout: *Layout, pages: *PreviewPages)
{
    let tr      = strings()
    let metrics = dlg.themeMetrics()
    let theme   = dlg.theme()
    let nav     = StackLayoutCtrl.create(dlg.form, .Center)
    nav.spacing     = metrics.dialog_BtnPadding
    nav.focusPolicy = .Tab
    nav.wndFlags    |= .FocusRing

    let size     = Math.Rectangle{0, 0, metrics.control_DialogHeight, metrics.control_DialogHeight}
    let previous = IconButton.create(nav, theme.icon(.ChevronLeft, metrics.chevron_Size), size, "gui.print.preview.previous", .CenterContent)
    let count    = Label.create(nav, Format.toString(tr.print_PreviewPage, layout.pageCount, layout.pageCount), id: "gui.print.preview.count", flags: .SecondaryText)
    let next     = IconButton.create(nav, theme.icon(.ChevronRight, metrics.chevron_Size), size, "gui.print.preview.next", .CenterContent)
    previous.setForm(.RoundedRectangle)
    next.setForm(.RoundedRectangle)
    previous.focusPolicy = .None
    next.focusPolicy     = .None
    previous.toolTip     = tr.print_PreviousPage
    next.toolTip         = tr.print_NextPage
    previous.enable(false)
    count.setTextAlignment(.Center, .Center)

    // Keep the arrows in place as the counter grows from one digit to several.
    count.preferredSize.x = count.measure({}).preferred.x
    count.setText(Format.toString(tr.print_PreviewPage, 1, layout.pageCount))

    pages[] = {last: cast(s64, layout.pageCount) - 1, layout: layout, view: view, count: count, previous: previous, next: next}
    previous.sigPressed += func|pages|(_)
    {
        pages.showPage(pages.page - 1)
    }

    next.sigPressed += func|pages|(_)
    {
        pages.showPage(pages.page + 1)
    }

    nav.hookOnEvent = func|pages|(_, evt)
    {
        let key = catch cast(*KeyEvent?, evt) orelse null
        if not key or key.kind != .Pressed or key.modifiers != .None do
            return false

        switch key.key
        {
        case .Left, .Down: pages.showPage(pages.page - 1)
        case .Right, .Up:  pages.showPage(pages.page + 1)
        case .PageDown:    pages.showPage(pages.page - 10)
        case .PageUp:      pages.showPage(pages.page + 10)
        case .Home:        pages.showPage(0)
        case .End:         pages.showPage(pages.last)
        default:           return false
        }

        key.accepted = true
        return true
    }

    view.hookOnEvent = nav.hookOnEvent
    dlg.form.addField("", nav)
}

private func choosePdf(from: *Surface, name, sourcePath: string)->String
{
    let tr       = strings()
    let stem     = Path.fileNameWithoutExtension(name) orelse name
    let proposed = Format.toString("%.pdf", stem.count ? stem : tr.print_Title)
    var options  = FileDlgOptions{title: tr.print_SavePdf, mode: .CreateFile, initialName: proposed}
    options.filters.add({name: "PDF", extensions: ".pdf"})
    let picker = FileDlg.create(from, options)
    if picker.doModal() != Dialog.BtnOk do
        return {}
    let target = picker.selectedPath()
    if sourcePath.count and Path.equals(target, sourcePath)
    {
        MessageDlg.error(from, tr.print_SameFile)
        return {}
    }

    return target
}

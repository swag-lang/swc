#global internal
#global namespace PrintDlg

using Core, Pixel, Gui.Print

private const BackButton:   WndId = "gui.print.settings"
const PreviewButton:        WndId = "gui.print.preview"
private const WorkFinished: WndId = "gui.print.finished"
private const ProgressDelayMs     = 160'u64
private const PreviewDpi          = 96.0'f32
private const PreviewHeight       = 336.0'f32
private const Papers              = [Paper.A4, Paper.Letter, Paper.Legal]
private const Placements          = [Placement.Fit, Placement.Center, Placement.Actual]

private struct PrintSettings
{
    destination: u32
    options:     JobOptions
    pageRange:   String
}

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
        let owner  = unwrap .view.surface
        let layout = .layout
        let image  = #move catch runWork(owner, strings().print_Preparing, func|layout, target|()->Image fail
        {
            return try layout.render(cast(u64, target), PreviewDpi)
        })
        {
            reportError(owner, Swag.err)
            return
        }

        .view.setImage(image)
        .page = target
        .previous.enable(target > 0)
        .next.enable(target < .last)
        .count.setText(Format.toString(strings().print_PreviewPage, target + 1, .layout.pageCount))
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
        let deadline = Time.monotonicMilliseconds() + ProgressDelayMs
        let poll: FrameCallback = func|&task, from, deadline|(app)
        {
            if not app.surfaces.contains(from) or from.wnd.isPendingDestroy do
                app.exitModal()
            elif task.isDone() or Time.monotonicMilliseconds() >= deadline do
                app.exitModal(WorkFinished)
            elif not app.renderer.needsNativeWindow() do
                Threading.Thread.sleep(1'ms)
        }

        let result = from.app.runModalLoop(null, poll, from, dim: false)
        if result != WorkFinished do
            fail PrintError{.Cancelled}
    }

    if not task.isDone()
    {
        let dlg = createWorkDialog(from, title)
        if task.isDone()
        {
            dlg.surface!.destroy()
            return try task.take()
        }

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
    var selected: PrintSettings
    for &device, i in devices where device.isDefault
    {
        selected.destination = cast(u32, i) + 1
        break
    }

    while true
    {
        let action = settings(from, document.kind, devices, &selected)
        if action != Dialog.BtnOk and action != PreviewButton do
            return
        var printer: const *Printer?
        if selected.destination do
            printer = &devices[selected.destination - 1]

        if not runJob(from, document, sourcePath, printer, &selected, action == PreviewButton) do
            return
    }
}

// Returns true when the workflow should go back to the settings.
private func runJob(from: *Surface, document: *Document, sourcePath: string, printer: const *Printer?, selected: *PrintSettings, showPreview: bool)->bool
{
    let options    = &selected.options
    let localSheet = pdfSheet(options.setup)
    var sheet      = localSheet

    // A printer with a smaller imageable area can paginate text into more pages.
    // Resolve an explicit range against that paper before rejecting it.
    if not showPreview and printer and document.kind == .Text and not selected.pageRange.isEmpty()
    {
        sheet = catch runWork(from, strings().print_Preparing, func|printer, setup = options.setup|()->Sheet fail
        {
            return try printerSheet(unwrap printer, setup)
        })
        {
            reportError(from, Swag.err)
            return false
        }
    }

    while true
    {
        var prepared = #move catch runWork(from, strings().print_Preparing, func|document, sheet, setup = options.setup, showPreview|()->PreparedPreview fail
        {
            var result: PreparedPreview
            result.layout = #move try prepare(document, sheet, setup)
            if showPreview do
                result.image = #move try result.layout.render(0, PreviewDpi)
            return #move result
        })
        {
            if Swag.err is PrintError as failure where failure.kind == .Cancelled do
                return false
            reportError(from, Swag.err)
            return true
        }

        let plan = &prepared.layout
        if showPreview
        {
            let answer = preview(from, &prepared, options, &selected.pageRange, printer != null, sheet != localSheet)
            if answer != Dialog.BtnOk do
                return answer == BackButton
        }
        elif not selectPages(from, plan, options, selected.pageRange)
        {
            return true
        }

        if let device = printer
        {
            let job        = options[]
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

        return not exportPdf(from, plan, options, sourcePath)
    }
}

private func settings(from: *Surface, kind: ContentKind, devices: const [..] Printer, selected: *PrintSettings)->WndId
{
    let tr      = strings()
    let options = &selected.options
    let dlg     = FormDlg.create(from, {title: tr.print_Title, confirmButtonText: selected.destination ? tr.print_Print : tr.print_SavePdf, showCancelButton: false})
    let primary = dlg.buttons[0]
    dlg.addButton(tr.print_Preview, PreviewButton)
    dlg.addButton(tr.dlg_Cancel, Dialog.BtnCancel)

    let destinations = dlg.form.addChoiceField(tr.print_Destination)
    destinations.addItem(tr.print_SavePdf)
    for &device in devices do
        destinations.addItem(device.name)
    destinations.setSelectedIndex(selected.destination, notify: false)
    destinations.sigChanged += func|dlg, primary|(_, index)
    {
        let tr = strings()
        primary.setText(index ? tr.print_Print : tr.print_SavePdf)
        primary.fitWidthToLabel(dlg.themeMetrics().btnPush_Width)
        dlg.buttonBar.computeLayout()
    }

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

    var range: *EditBox?
    if kind != .Image do
        range = dlg.form.addTextField(tr.print_Range, selected.pageRange, placeholder: tr.print_AllPages, help: tr.print_RangeHelp)

    var copies: *EditBox?
    if devices.count
    {
        let field = dlg.form.addTextField(tr.print_Copies, Format.toString("%", options.copies))
        field.setUnsignedIntegerRange(1, 999)
        field.enable(selected.destination != 0)
        destinations.sigChanged += func|field|(_, index) { field.enable(index != 0) }
        copies = field
    }

    dlg.validateResult = func|destinations, paper, orientation, margin, placement, copies, range, selected|(_, id)
    {
        if id != Dialog.BtnOk and id != PreviewButton do
            return true
        if not margin.isValid() or (destinations.selectedIndex and copies and not copies.isValid()) do
            return false
        let options = &selected.options
        selected.destination    = destinations.selectedIndex
        options.setup.paper     = Papers[paper.selectedIndex]
        options.setup.landscape = orientation.selectedIndex != 0
        options.setup.margin    = cast(f32, expect StrConv.toNum'u32(margin.text())) * PointsPerInch / MillimetersPerInch
        if placement do
            options.setup.placement = Placements[placement.selectedIndex]
        options.copies     = selected.destination and copies ? expect StrConv.toNum'u32(copies.text()) : 1
        selected.pageRange = range ? range.text() : ""
        return true
    }

    return dlg.doModal()
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

private func selectPages(owner: *Surface, layout: const *Layout, options: *JobOptions, value: string)->bool
{
    let pages = catch parseRange(value, layout.pageCount)
    {
        reportError(owner, Swag.err)
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
    return true
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
        if id != Dialog.BtnOk and id != BackButton do
            return true
        if range do
            pageRange[] = range.text()
        if id == BackButton do
            return true
        if not selectPages(unwrap dlg.surface, layout, options, pageRange[])
        {
            range?.setFocus()
            return false
        }

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

private func exportPdf(from: *Surface, layout: const *Layout, job: const *JobOptions, sourcePath: string)->bool
{
    let tr       = strings()
    let name     = layout.document.name.toString()
    let stem     = Path.fileNameWithoutExtension(name) orelse name
    var proposed = Format.toString("%.pdf", stem.count ? stem : tr.print_Title)
    if sourcePath.count and Path.equals(proposed, Path.fileName(sourcePath) orelse "") do
        proposed = Format.toString("% (2).pdf", stem)
    var folder = Env.getSpecialDirectory(.UserDocuments)
    if not Directory.exists(folder) do
        folder = Path.directoryName(folder) orelse ""
    while true
    {
        var options = FileDlgOptions{title: tr.print_SavePdf, mode: .CreateFile, initialFolder: folder, initialName: proposed}
        options.filters.add({name: "PDF", extensions: ".pdf"})
        let picker = FileDlg.create(from, options)
        if picker.doModal() != Dialog.BtnOk do
            return false

        let target = picker.selectedPath()
        folder = Path.directoryName(target) orelse ""
        if sourcePath.count and Path.equals(target, sourcePath)
        {
            MessageDlg.error(from, tr.print_SameFile)
            continue
        }

        let fileName = target.toString()
        let output   = job[]
        discard catch runWork(from, tr.print_SavingPdf, func|layout, output, fileName|()->bool fail
        {
            try savePdf(layout, output, fileName)
            return true
        })
        {
            if Swag.err is PrintError as error where error.kind == .Cancelled do
                return false
            MessageDlg.error(from, tr.print_PdfSaveFailed, Swag.err)
            proposed = Path.fileName(target) orelse ""
            continue
        }

        return true
    }
}

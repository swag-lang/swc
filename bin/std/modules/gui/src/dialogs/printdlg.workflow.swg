#global internal
#global namespace PrintDlg

using Core, Pixel, Gui.Print

private const BackButton:   WndId = "gui.print.settings"
private const WorkFinished: WndId = "gui.print.finished"
private const PreviewDpi          = 96.0'f32
private const Papers              = [Paper.A4, Paper.Letter, Paper.Legal]
private const Placements          = [Placement.Fit, Placement.Center, Placement.Actual]

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

        var layout = #move catch runWork(from, strings().print_Preparing, func|document, printer, setup = options.setup|()->Layout fail
        {
            let sheet = printer ? try printerSheet(printer, setup) : pdfSheet(setup)
            return try prepare(document, sheet, setup)
        })
        {
            if Swag.err is PrintError as failure
            {
                if failure.kind == .Cancelled do
                    return
            }

            reportError(from, Swag.err)
            continue
        }

        let answer = preview(from, &layout, &options, printer != null)
        if answer == BackButton do
            continue
        if answer != Dialog.BtnOk do
            return

        let plan = &layout
        if let device = printer
        {
            discard catch runWork(from, strings().print_Sending, func|device, plan, options|()->bool fail
            {
                try printNative(unwrap device, plan, options)
                return true
            })
            {
                reportError(from, Swag.err)
            }
        }
        else
        {
            let target = choosePdf(from, document.name, sourcePath)
            if target.isEmpty() do
                continue
            let fileName = target.toString()
            discard catch runWork(from, strings().print_SavingPdf, func|plan, options, fileName|()->bool fail
            {
                try savePdf(plan, options, fileName)
                return true
            })
            {
                reportError(from, Swag.err)
            }
        }

        return
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

    let orientation = dlg.form.addChoiceField(tr.print_Orientation)
    orientation.addItem(tr.print_Portrait)
    orientation.addItem(tr.print_Landscape)
    orientation.setSelectedIndex(options.setup.landscape ? 1 : 0, notify: false)

    let margin = dlg.form.addTextField(tr.print_Margins, Format.toString("%", cast(u32, Math.round(options.setup.margin * MillimetersPerInch / PointsPerInch))))
    margin.setUnsignedIntegerRange(0, 75)
    margin.setUnit("mm")

    var placement: *ComboBox?
    if kind != .Text
    {
        let scale = dlg.form.addChoiceField(tr.print_Placement)
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

private func preview(from: *Surface, layout: *Layout, options: *JobOptions, isPrinter: bool)->WndId
{
    let tr    = strings()
    let image = #move catch runWork(from, tr.print_Preparing, func|layout|()->Image fail
    {
        return try layout.render(0, PreviewDpi)
    })
    {
        reportError(from, Swag.err)
        return ""
    }

    let dlg = FormDlg.create(from, {title: tr.print_Preview, confirmButtonText: isPrinter ? tr.print_Print : tr.print_SavePdf, showCancelButton: false})
    dlg.addButton(tr.print_Settings, BackButton)
    dlg.addButton(tr.dlg_Cancel, Dialog.BtnCancel)
    let view = ImageView.create(dlg.form, {0, 0, 0, 272})
    view.setImage(image)
    dlg.form.addField("", view)
    var range: *EditBox?
    if layout.pageCount > 1
    {
        let navigation = Stepper.create(dlg.form)
        navigation.setRange(1, cast(s64, layout.pageCount))
        navigation.sigChanged += func|layout, view, dlg|(wnd)
        {
            let page = cast(u64, cast(*Stepper, wnd).value) - 1
            catch view.setImage(layout.render(page, PreviewDpi))
            {
                view.clear()
                reportError(unwrap dlg.surface, Swag.err)
            }
        }

        dlg.form.addField(Format.toString(tr.print_PreviewPage, layout.pageCount), navigation)
        range = dlg.form.addTextField(tr.print_Range, placeholder: tr.print_AllPages, help: tr.print_RangeHelp)
    }

    dlg.validateResult = func|dlg, layout, options, range|(_, id)
    {
        if id != Dialog.BtnOk do
            return true
        let owner = unwrap dlg.surface
        let pages = catch parseRange(range ? range.text() : "", layout.pageCount)
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
        return true
    }

    return dlg.doModal()
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

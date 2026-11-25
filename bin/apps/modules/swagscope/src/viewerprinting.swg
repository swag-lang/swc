#global internal

using Core, Gui, Pixel

impl ViewerWindow
{
    mtd printView()->*Wnd?
    {
        if .isExploring() or .currentFile.isEmpty() or .activeChoiceIndex >= .instances.count do
            return null
        let session = &.instances[.activeChoiceIndex]
        let view    = session.view
        if not view or
           view != .currentView or
           not view.isVisible() or
           view.isPendingDestroy or
           not session.failureReason.isEmpty() do
            return null
        return view
    }

    mtd printCurrentView()
    {
        let view  = .printView()
        let owner = .surface
        if not view or not owner do
            return

        let path = String.from(.currentFile)
        if view is Viewers.PdfDocument.Panel
        {
            PrintDlg.printPdf(owner, path)
            return
        }

        if view is Viewers.PlainText.Panel as text
        {
            PrintDlg.printText(owner, path, text.encoding, cast(u32, text.tabWidth))
            return
        }

        if view is Viewers.Code.Panel as code
        {
            PrintDlg.printText(owner, path, code.encoding, cast(u32, code.tabWidth))
            return
        }

        let name = Path.fileName(path) orelse path.toString()
        if view is Viewers.Picture.Panel as picture
        {
            let display = picture.imageView
            if let pixels = display.picture()
            {
                var image = pixels[]
                if display.isMirrored do
                    image.mirror()
                switch display.rotationQuarterTurns
                {
                case 1: image.rotate(.Clockwise90)
                case 2: image.rotate(.HalfTurn)
                case 3: image.rotate(.Clockwise270)
                }

                PrintDlg.printImage(owner, image, name)
                return
            }
        }

        let image = #move catch renderViewerForPrint(view, owner)
        {
            MessageDlg.error(owner, Gui.strings().print_InvalidPage, Swag.err)
            return
        }

        PrintDlg.printImage(owner, image, name, 96 * view.deviceScale())
    }
}

// Records only the document subtree so a lens, sidebar or adjacent pane cannot cover the output.
func renderViewerForPrint(view: *Wnd, surface: *Surface)->Image fail
{
    let scale  = view.deviceScale()
    let rect   = view.position
    let width  = cast(s32, Math.ceil(rect.width * scale))
    let height = cast(s32, Math.ceil(rect.height * scale))
    if width <= 0 or height <= 0 do
        fail Errors.BadParameterError{}

    let renderer = surface.app.renderer
    renderer.begin(surface.renderingContext())
    defer
    {
        if renderer is RenderOgl as ogl do
            ogl.finishFrameWithoutPresent()
        else do
            renderer.end()
    }

    var target = renderer.createRenderTarget(width, height)
    if not target.colorBuffer.isValid() do
        fail RenderResourceError{"The renderer could not allocate the viewer print target."}
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    var paint   = PaintContext{painter: &painter, renderer}
    painter.setContentScale(scale)
    painter.begin()
    painter.bindRenderTarget(&target, false)
    painter.setColorMaskFull()
    painter.clear(view.themeColors().view_Bk)
    painter.setColorMaskColor()
    painter.pushClippingRect({0, 0, rect.width, rect.height})
    painter.translateTransform(-rect.x, -rect.y)
    view.paint(&paint)
    painter.popClippingRect()
    painter.unbindRenderTarget()
    painter.end()
    try painter.render()

    let image = #move renderer.readRenderTarget(&target, 0, 0, width, height)
    if not image.isValid() do
        fail Errors.InvalidFormatError{}
    return #move image
}

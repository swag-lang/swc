#global internal

using Core, Pixel, Gui

private const ImageGlyphSize = 18.0
private const ImageCommandWidth = 316.0
private const GifCommandWidth = 544.0
private const SvgRasterLimit = 2048.0

internal func loadViewerImage(fileName: string)->Image fail
{
    if Path.lowercaseExtension(fileName) != ".svg" do
        return try Image.load(fileName)

    let source  = try File.readAllText(fileName)
    let drawing = try Svg.Drawing.parse(source.toString())
    let largest = Math.max(drawing.width, drawing.height)
    let scale   = largest > SvgRasterLimit ? SvgRasterLimit / largest : 1
    let width   = cast(s32) Math.max(Math.round(drawing.width * scale), 1)
    let height  = cast(s32) Math.max(Math.round(drawing.height * scale), 1)
    return drawing.rasterize(width, height, 1)
}

internal struct ImageViewer
{
    using wnd: Wnd
    details:   String

    #[Swag.Late]
    {
        commands:   *ViewerCommandBar
        imageView:  *ImageView
        zoomLabel:  *Label
        playButton: *IconButton
        timeline:   *Slider
        frameLabel: *Label
    }
}

internal impl ImageViewer
{
    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %", cast(s32) Math.round(.imageView.effectiveZoom() * 100), "%"))
    }

    mtd refreshFrame()
    {
        let movie = &.imageView.movie
        if movie.frameCount <= 1 do
            return
        .timeline.setValueWithoutGesture(cast(f32) movie.frameIndex)
        .frameLabel.setText(Format.toString("% / %", movie.frameIndex + 1, movie.frameCount))
        .playButton.setIcon(.theme().icon(movie.isPaused ? .Play : .Pause, ImageGlyphSize))
    }

    mtd showPlayback()
    {
        .commands.resize(GifCommandWidth, 36)
        .playButton.show()
        .timeline.show()
        .frameLabel.show()
        .timeline.setBounds(0, cast(f32) .imageView.movie.frameCount - 1, 1)
        .refreshFrame()
    }
}

private impl IWnd for ImageViewer
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Add, .OemPlus:
            .imageView.zoomIn()

        case .Subtract, .OemMinus:
            .imageView.zoomOut()

        case .D0 where evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F:
            .imageView.zoomToFit()

        case .R:
            .imageView.rotateClockwise()

        case .Space where .imageView.movie.frameCount > 1:
            .imageView.setPaused(!.imageView.movie.isPaused)
            .refreshFrame()

        default:
            evt.accepted = false
        }
    }
}

private impl ImageViewer
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*ImageViewer fail
    {
        let result = Wnd.create'ImageViewer(contentParent, "sFileScope.image")
        result.backgroundStyle = .View

        result.commands = ViewerCommandBar.create(commandParent, ImageCommandWidth)

        with let zoomOut = IconButton.create(result.commands, result.theme().icon(.ZoomOut, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = imageStrings().ui_TipZoomOut
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomOut()
            }
        }

        with let zoomIn = IconButton.create(result.commands, result.theme().icon(.ZoomIn, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.z   = 8
            .toolTip    = imageStrings().ui_TipZoomIn
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomIn()
            }
        }

        with let fit = IconButton.create(result.commands, result.commands.icon(.FitView, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = imageStrings().ui_TipFit
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomToFit()
            }
        }

        with let actual = IconButton.create(result.commands, result.commands.icon(.ActualSize, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = imageStrings().ui_TipActual
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.actualSize()
            }
        }

        with let rotate = IconButton.create(result.commands, result.theme().icon(.Redo, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = imageStrings().ui_TipRotate
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.rotateClockwise()
            }
        }

        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Pause, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .margin.x  = 10
            .toolTip   = imageStrings().ui_TipPlay
            .hide()
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.setPaused(!view.imageView.movie.isPaused)
                view.refreshFrame()
            }
        }

        with result.timeline = Slider.create(result.commands, {0, 0, 128, 36})
        {
            .dockStyle = .Left
            .margin    = {6, 1, 6, 1}
            .hide()
            .sigChanged += func|view = result|(slider)
            {
                view.imageView.setFrameIndex(cast(s32) Math.round(slider.value()))
            }
        }

        with result.frameLabel = Label.create(result.commands, "", {0, 0, 58, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Center, .Center)
            .hide()
        }

        with result.zoomLabel = Label.create(result.commands, "100%", {0, 0, 70, 36}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .setTextAlignment(.Right, .Center)
        }

        result.imageView                = ImageView.create(result)
        result.imageView.dockStyle      = .Center
        result.imageView.sigZoomChanged += func|view = result|(imageView)
        {
            discard imageView
            view.refreshZoom()
        }
        result.imageView.sigFrameChanged += func|view = result|(imageView)
        {
            discard imageView
            view.refreshFrame()
        }

        var decoded: bool
        defer if !decoded
        {
            result.commands.destroy()
            result.destroy()
        }

        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        if extension == ".gif"
        {
            try result.imageView.loadGif(fileName)
            let frame = &result.imageView.movie.frame
            result.details = Format.toString(imageStrings().ui_DetailsMovie, frame.width, frame.height, frameCountText(result.imageView.movie.frameCount))
            if result.imageView.movie.frameCount > 1 do
                result.showPlayback()
        }
        else
        {
            let image = try loadViewerImage(fileName)
            result.details = Format.toString(imageStrings().ui_DetailsStill, image.width, image.height, image.bitsPerPixel)
            result.imageView.setImage(image)
        }

        decoded = true
        result.refreshZoom()
        result.applyLayout()
        result.setInitialFocus(result.imageView)
        return result
    }
}

private func loadImageViewer(contentParent, commandParent: *Wnd, fileName: string)->#null *ImageViewer fail => try ImageViewer.create(contentParent, commandParent, fileName)

// Creates the integrated image view.
func createImageViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    let view = catch loadImageViewer(request.contentParent, request.commandParent, request.fileName) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return
    }

    result.view     = view
    result.commands = view!.commands
    result.details  = view!.details
}

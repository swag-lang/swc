#global public

using Core, Pixel, Gui

private const ImageGlyphSize = 18.0
private const ImageCommandWidth = 362.0
private const GifCommandWidth = 590.0
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

internal struct ImagePluginView
{
    using wnd: Wnd
    details:   String

    #[Swag.Late]
    {
        commands:   *Wnd
        imageView:  *ImageView
        zoomLabel:  *Label
        playButton: *IconButton
        timeline:   *Slider
        frameLabel: *Label
    }
}

internal impl ImagePluginView
{
    // Places the decoder's exact explanation immediately under the stable summary. The detail is
    // the actionable part of the failure, so it uses the theme's critical text color.
    mtd showDecodeError(summary: string, error: #null any)
    {
        .imageView.hide()

        with let stack = StackLayoutCtrl.create(me, .VerticalCenter)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .spacing   = 8

            with let message = Label.create(stack, summary, flags: .WordWrap | .AutoHeight | .SecondaryText)
            {
                .setTextAlignment(.Center, .Center)
            }

            with let detail = Label.create(stack, Errors.message(error), flags: .WordWrap | .AutoHeight)
            {
                .setTextAlignment(.Center, .Center)
                .setTextColor(.themeColors().embInfo_CriticalText)
            }
        }
    }

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

private impl IWnd for ImagePluginView
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

private impl ImagePluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*ImagePluginView
    {
        let result = Wnd.create'ImagePluginView(contentParent, "sFileScope.image")
        result.backgroundStyle = .View

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, ImageCommandWidth, 36})
        {
            .backgroundStyle = .Window
        }

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

        with let fit = PushButton.create(result.commands, imageStrings().ui_Fit, {0, 0, 48, 36})
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

        with let actual = PushButton.create(result.commands, "100%", {0, 0, 58, 36})
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

        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        if extension == ".gif"
        {
            discard catch result.imageView.loadGif(fileName) as loadError
            if loadError != null
            {
                result.showDecodeError(imageStrings().ui_ErrGif, loadError)
            }
            else
            {
                let frame = &result.imageView.movie.frame
                result.details = Format.toString(imageStrings().ui_DetailsMovie, frame.width, frame.height, frameCountText(result.imageView.movie.frameCount))
                if result.imageView.movie.frameCount > 1 do
                    result.showPlayback()
            }
        }
        else
        {
            let image = catch loadViewerImage(fileName) as loadError
            if loadError == null
            {
                result.details = Format.toString(imageStrings().ui_DetailsStill, image.width, image.height, image.bitsPerPixel)
                result.imageView.setImage(image)
            }
            else
            {
                result.showDecodeError(imageStrings().ui_ErrImage, loadError)
            }
        }

        result.refreshZoom()
        result.applyLayout()
        result.setInitialFocus(result.imageView)
        return result
    }
}

// Creates the image view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    let view = ImagePluginView.create(request.contentParent, request.commandParent, request.fileName)
    result.view     = view
    result.commands = view.commands
    result.details  = view.details
    return true
}

#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 2'u32
private const ImageGlyphSize         = 18.0
private const ImageCommandWidth      = 350.0
private const GifCommandWidth        = 570.0

private struct ImagePluginView
{
    using wnd: Wnd

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

private impl ImagePluginView
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
        .commands.resize(GifCommandWidth, 32)
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
        case .Add, .OemPlus: .imageView.zoomIn()
        case .Subtract, .OemMinus: .imageView.zoomOut()
        case .D0 where evt.modifiers.has(.Control): .imageView.actualSize()
        case .F: .imageView.zoomToFit()
        case .R: .imageView.rotateClockwise()
        case .Space where .imageView.movie.frameCount > 1:
            .imageView.setPaused(!.imageView.movie.isPaused)
            .refreshFrame()
        default: evt.accepted = false
        }
    }
}

private impl ImagePluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*ImagePluginView
    {
        let result = Wnd.create'ImagePluginView(contentParent, "sViewer.image")
        result.backgroundStyle = .View

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, ImageCommandWidth, 32})
        {
            .backgroundStyle = .Window
        }

        with let zoomOut = IconButton.create(result.commands, result.theme().icon(.ZoomOut, ImageGlyphSize), {0, 0, 34, 32})
        {
            .dockStyle = .Left
            .toolTip   = "Zoom out"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomOut()
            }
        }

        with let zoomIn = IconButton.create(result.commands, result.theme().icon(.ZoomIn, ImageGlyphSize), {0, 0, 34, 32})
        {
            .dockStyle = .Left
            .margin.z  = 4
            .toolTip   = "Zoom in"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomIn()
            }
        }

        with let fit = PushButton.create(result.commands, "Fit", {0, 0, 48, 32})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = "Fit image"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomToFit()
            }
        }

        with let actual = PushButton.create(result.commands, "100%", {0, 0, 58, 32})
        {
            .dockStyle = .Left
            .margin.x  = 4
            .toolTip   = "Actual size"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.actualSize()
            }
        }

        with let rotate = IconButton.create(result.commands, result.theme().icon(.Redo, ImageGlyphSize), {0, 0, 34, 32})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = "Rotate clockwise"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.rotateClockwise()
            }
        }

        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Pause, ImageGlyphSize), {0, 0, 34, 32})
        {
            .dockStyle = .Left
            .margin.x  = 10
            .toolTip   = "Play or pause"
            .hide()
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.setPaused(!view.imageView.movie.isPaused)
                view.refreshFrame()
            }
        }

        with result.timeline = Slider.create(result.commands, {0, 0, 128, 32})
        {
            .dockStyle = .Left
            .margin    = {6, 1, 6, 1}
            .hide()
            .sigChanged += func|view = result|(slider)
            {
                view.imageView.setFrameIndex(cast(s32) Math.round(slider.value()))
            }
        }

        with result.frameLabel = Label.create(result.commands, "", {0, 0, 58, 32}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Center, .Center)
            .hide()
        }

        with result.zoomLabel = Label.create(result.commands, "100%", {0, 0, 70, 32}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .setTextAlignment(.Right, .Center)
        }

        result.imageView           = ImageView.create(result)
        result.imageView.dockStyle = .Center
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
                result.imageView.hide()
                let label = Label.create(result, "This GIF could not be decoded.", {}, null, .WordWrap | .SecondaryText)
                label.dockStyle = .Center
                label.setTextAlignment(.Center, .Center)
            }
            elif result.imageView.movie.frameCount > 1 do
                result.showPlayback()
        }
        else
        {
            let image = catch Image.load(fileName) as loadError
            if loadError == null do
                result.imageView.setImage(image)
            else
            {
                result.imageView.hide()
                let label = Label.create(result, "This image could not be decoded.", {}, null, .WordWrap | .SecondaryText)
                label.dockStyle = .Center
                label.setTextAlignment(.Center, .Center)
            }
        }

        result.refreshZoom()
        result.applyLayout()
        result.setInitialFocus(result.imageView)
        return result
    }
}

// Creates the image view exported through the sViewer plugin ABI.
func sViewerPluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view  = ImagePluginView.create(contentParent, commandParent, fileName)
    commands[] = view.commands
    return view
}

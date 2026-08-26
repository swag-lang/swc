#global internal

using Core, Pixel, Gui

private const MidiCommandWidth = 432.0
private const MidiGlyphSize = 18.0

internal struct MidiViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:   *ViewerCommandBar
        trackCombo: *ComboBox
        zoomOutButton: *IconButton
        zoomInButton:  *IconButton
        fitButton:     *IconButton
        zoomLabel:  *Label
        roll:       *MidiRollView
    }

    details: String
}

private impl MidiViewer
{
    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %", cast(u32) Math.round(.roll.zoom * 100), "%"))
    }

    mtd fillTracks()
    {
        let selected = .trackCombo.selectedIndex
        .trackCombo.clear()
        .trackCombo.addItem(midiStrings().ui_AllTracks)
        for track in .roll.document.tracks
        {
            let label = Format.toString(midiStrings().ui_TrackChoice, track.name, track.noteCount)
            .trackCombo.addItem(label.toString())
        }
        .trackCombo.setSelectedIndex(selected == Swag.U32.Max ? 0 : selected, notify: false)
    }

    mtd retranslate()
    {
        .fillTracks()
        .trackCombo.toolTip    = midiStrings().ui_AllTracks
        .zoomOutButton.toolTip = midiStrings().ui_ZoomOut
        .zoomInButton.toolTip  = midiStrings().ui_ZoomIn
        .fitButton.toolTip     = midiStrings().ui_Fit
        .roll.invalidate()
    }
}

private impl IWnd for MidiViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

internal impl MidiViewer
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*MidiViewer fail
    {
        registerMidiStrings(contentParent.app())
        let document = try loadMidiDocument(fileName)
        let result   = Wnd.create'MidiViewer(contentParent, "sFileScope.midi")
        result.backgroundStyle = .View

        result.commands = ViewerCommandBar.create(commandParent, MidiCommandWidth)
        with result.trackCombo = ComboBox.create(result.commands, {0, 0, 224, 36})
        {
            .dockStyle = .Left
            .toolTip   = midiStrings().ui_AllTracks
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                view.roll.setTrack(index ? index - 1 : Swag.U32.Max)
            }
        }

        with result.zoomOutButton = IconButton.create(result.commands, result.theme().icon(.ZoomOut, MidiGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = midiStrings().ui_ZoomOut
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.roll.zoomOut()
                view.refreshZoom()
            }
        }

        with result.zoomInButton = IconButton.create(result.commands, result.theme().icon(.ZoomIn, MidiGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = midiStrings().ui_ZoomIn
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.roll.zoomIn()
                view.refreshZoom()
            }
        }

        with result.fitButton = IconButton.create(result.commands, result.theme().icon(.FitView, MidiGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = midiStrings().ui_Fit
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.roll.zoomToFit()
                view.refreshZoom()
            }
        }

        with result.zoomLabel = Label.create(result.commands, "", {0, 0, 76, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Right, .Center)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
        }

        result.roll = MidiRollView.create(result, #move document)
        result.roll.sigZoomChanged += func|view = result|(roll)
        {
            discard roll
            view.refreshZoom()
        }
        result.fillTracks()
        result.trackCombo.setSelectedIndex(0, notify: false)
        result.details = Format.toString(midiStrings().ui_Details,
                                         result.roll.document.format,
                                         result.roll.document.tracks.count,
                                         result.roll.document.notes.count,
                                         mediaDurationText(result.roll.document.durationSeconds))
        result.applyLayout()
        result.roll.refreshLayout()
        result.refreshZoom()
        result.setInitialFocus(result.roll)
        return result
    }
}

private func loadMidiViewer(contentParent, commandParent: *Wnd, fileName: string)->#null *MidiViewer fail => try MidiViewer.create(contentParent, commandParent, fileName)

func createMidiViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerMidiStrings(request.contentParent.app())
    let view = catch loadMidiViewer(request.contentParent, request.commandParent, request.fileName) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return
    }

    result.view     = view
    result.commands = view!.commands
    result.details  = view!.details
}

#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

impl Panel
{
    // Replaces the active sound track without disturbing picture transport state.
    //
    // The new voice is fully positioned and configured before the old one is released, so an
    // unsupported track cannot turn a playing video silent halfway through the operation.
    mtd selectAudioTrack(index: u32) fail
    {
        if index >= .video.audioTrackCount() do
            fail BadParameterError{texts().err_AudioTrack}

        let sound = .video.audioTrack(index)!
        if .voice and index == .audioTrackIndex and .audio == sound do
            return
        let position      = .currentSeconds()
        let wasPlaying    = .playing
        let coversRange   = soundCovers(sound, position)
        let shouldPlay    = wasPlaying and coversRange and not .resumeAudioAfterSeek
        let restoreOld    = wasPlaying and .voice != null and not .audioRangePending and not .resumeAudioAfterSeek
        let newVoice      = try Voice.create(sound)
        let oldVoice      = .voice
        var restoreNeeded = restoreOld
        defer #fail
        {
            newVoice.destroy()
            if restoreNeeded do
                catch oldVoice!.play()
        }

        try newVoice.setVolume(.muted ? 0 : .volume)
        if .playbackRate != 1 do
            catch newVoice.setFrequencyRatio(cast(f32, .playbackRate))
        if coversRange do
            try newVoice.seekSampleFrame(soundSample(sound, position))
        if oldVoice do
            try oldVoice.pause()
        if shouldPlay do
            try newVoice.play()

        restoreNeeded = false
        if oldVoice
        {
            catch oldVoice.stop()
            oldVoice.destroy()
        }

        .audio             = sound
        .voice             = newVoice
        .audioTrackIndex   = index
        .audioRangePending = not coversRange
        .audioClockLast    = -1
        if shouldPlay
        {
            .elapsed = position
            .clock.restart()
        }
        elif .resumeAudioAfterSeek and coversRange
        {
            .resumeAudio()
        }

        .refreshDetails()
    }

    // Offers the available sound tracks without reserving label width in the transport bar.
    mtd showAudioTrackMenu()
    {
        let menu = MenuCtrl.createPopup(.audioButton, owner: me)
        var commands: Array'String
        commands.reserve(.video.audioTrackCount())
        for index in .video.audioTrackCount()
        {
            let sound = .video.audioTrack(index)!
            commands.add(audioTrackCommand(index))
            menu.addRadioItem(audioTrackText(index, sound), commands[index], checked: index == .audioTrackIndex)
        }

        let chosen = menu.doModal(.audioButton, autoDestroy: true)
        if not chosen do
            return

        for index in .video.audioTrackCount() where chosen == commands[index].toString()
        {
            catch .selectAudioTrack(index) as trackError
            if trackError != null do
                .services.failed(me, Errors.message(trackError))
            return
        }
    }

    // Offers the playback rates independently of the shared end-of-file mode.
    mtd showPlaybackSpeedMenu()
    {
        let menu = MenuCtrl.createPopup(.speedButton, owner: me)

        var commands: Array'String
        commands.reserve(PlaybackRates.count)
        for rate, index in PlaybackRates
        {
            commands.add(playbackRateCommand(cast(u32, index)))
            menu.addRadioItem(playbackRateText(rate), commands[index], checked: rate == .playbackRate)
        }

        let chosen = menu.doModal(.speedButton, autoDestroy: true)
        if not chosen do
            return
        for rate, index in PlaybackRates where chosen == commands[index].toString()
        {
            .setPlaybackRate(rate)
            return
        }
    }

    mtd const subtitleTrack()->const *Subtitle.Track?
    {
        switch #complete .subtitleSource
        {
        case .Embedded: return .video.subtitleTrack(.subtitleTrackIndex)
        case .Sidecar:  return .subtitleTrackIndex < .subtitleOverlay.sidecars.count ? .subtitleOverlay.sidecars[.subtitleTrackIndex] : null
        case .Off:      return null
        }
    }

    mtd selectSubtitle(source: SubtitleSource, index: u32 = NoSubtitle)
    {
        .subtitleSource      = source
        .subtitleTrackIndex  = index
        .subtitleLastSeconds = -1
        .subtitleNextChange  = 0
        .refreshSubtitle()
    }

    mtd refreshSubtitle()
    {
        let track = .subtitleTrack()
        if not track
        {
            .subtitleOverlay.setSubtitle("")
            return
        }

        let seconds = .currentSeconds() + g_SubtitleSettings.delay
        if .subtitleLastSeconds >= 0 and seconds >= .subtitleLastSeconds and seconds < .subtitleNextChange do
            return
        var text: String
        .subtitleLastSeconds = seconds
        .subtitleNextChange  = subtitlePresentationAt(track, seconds, &text)
        .subtitleOverlay.setSubtitle(text)
    }

    mtd subtitleSettingsChanged()
    {
        .subtitleLastSeconds = -1
        .subtitleOverlay.applySettings()
        .refreshSubtitle()
        catch g_App.saveState()
    }

    mtd handleSubtitleSetting(command: string)->bool
    {
        switch command
        {
        case "scope.video.subtitle.font.sans":       g_SubtitleSettings.font = .Sans
        case "scope.video.subtitle.font.mono":       g_SubtitleSettings.font = .Monospace
        case "scope.video.subtitle.size.small":      g_SubtitleSettings.size = .Small
        case "scope.video.subtitle.size.normal":     g_SubtitleSettings.size = .Normal
        case "scope.video.subtitle.size.large":      g_SubtitleSettings.size = .Large
        case "scope.video.subtitle.size.veryLarge":  g_SubtitleSettings.size = .VeryLarge
        case "scope.video.subtitle.effect.outline":  g_SubtitleSettings.effect = .Outline
        case "scope.video.subtitle.effect.shadow":   g_SubtitleSettings.effect = .Shadow
        case "scope.video.subtitle.effect.backdrop": g_SubtitleSettings.effect = .Background
        case "scope.video.subtitle.effect.none":     g_SubtitleSettings.effect = .None
        case "scope.video.subtitle.position.bottom": g_SubtitleSettings.position = .Bottom
        case "scope.video.subtitle.position.center": g_SubtitleSettings.position = .Center
        case "scope.video.subtitle.position.top":    g_SubtitleSettings.position = .Top
        case "scope.video.subtitle.color.white":     g_SubtitleSettings.color = .White
        case "scope.video.subtitle.color.yellow":    g_SubtitleSettings.color = .Yellow
        case "scope.video.subtitle.delay.minus1":    g_SubtitleSettings.delay -= 1
        case "scope.video.subtitle.delay.minus01":   g_SubtitleSettings.delay -= 0.1
        case "scope.video.subtitle.delay.reset":     g_SubtitleSettings.delay = 0
        case "scope.video.subtitle.delay.plus01":    g_SubtitleSettings.delay += 0.1
        case "scope.video.subtitle.delay.plus1":     g_SubtitleSettings.delay += 1
        default: return false
        }

        g_SubtitleSettings.delay = Math.clamp(g_SubtitleSettings.delay, -60, 60)
        .subtitleSettingsChanged()
        return true
    }

    // Offers embedded and VLC-style sidecar tracks together with persistent render controls.
    mtd showSubtitleMenu()
    {
        let strings = texts()
        let menu    = MenuCtrl.createPopup(.subtitleButton, owner: me)
        menu.setSubmenuDirection(.Left)
        menu.addRadioItem(strings.ui_SubtitleOff, "scope.video.subtitle.off", checked: .subtitleSource == .Off)

        var embeddedCommands: Array'String
        var sidecarCommands:  Array'String
        let embeddedCount = .video.subtitleTrackCount()
        if embeddedCount or not .subtitleOverlay.sidecars.isEmpty() do
            menu.addSeparator()
        for index in embeddedCount
        {
            let track = .video.subtitleTrack(index)!
            embeddedCommands.add(subtitleTrackCommand(false, index))
            menu.addRadioItem(subtitleTrackText(index, track, false), embeddedCommands[index], checked: .subtitleSource == .Embedded and .subtitleTrackIndex == index)
        }

        for track, index in .subtitleOverlay.sidecars
        {
            sidecarCommands.add(subtitleTrackCommand(true, cast(u32, index)))
            menu.addRadioItem(subtitleTrackText(cast(u32, index), track, true), sidecarCommands[index], checked: .subtitleSource == .Sidecar and .subtitleTrackIndex == index)
        }

        menu.addSeparator()
        with let fontMenu = MenuCtrl.createPopup(menu, owner: me)
        {
            .addRadioItem(strings.ui_SubtitleFontSans, "scope.video.subtitle.font.sans", checked: g_SubtitleSettings.font == .Sans)
            .addRadioItem(strings.ui_SubtitleFontMono, "scope.video.subtitle.font.mono", checked: g_SubtitleSettings.font == .Monospace)
        }

        menu.addPopup(strings.ui_SubtitleFont, fontMenu)

        with let sizeMenu = MenuCtrl.createPopup(menu, owner: me)
        {
            .addRadioItem(strings.ui_SubtitleSizeSmall, "scope.video.subtitle.size.small", checked: g_SubtitleSettings.size == .Small)
            .addRadioItem(strings.ui_SubtitleSizeNormal, "scope.video.subtitle.size.normal", checked: g_SubtitleSettings.size == .Normal)
            .addRadioItem(strings.ui_SubtitleSizeLarge, "scope.video.subtitle.size.large", checked: g_SubtitleSettings.size == .Large)
            .addRadioItem(strings.ui_SubtitleSizeVeryLarge, "scope.video.subtitle.size.veryLarge", checked: g_SubtitleSettings.size == .VeryLarge)
        }

        menu.addPopup(strings.ui_SubtitleSize, sizeMenu)

        with let effectMenu = MenuCtrl.createPopup(menu, owner: me)
        {
            .addRadioItem(strings.ui_SubtitleEffectOutline, "scope.video.subtitle.effect.outline", checked: g_SubtitleSettings.effect == .Outline)
            .addRadioItem(strings.ui_SubtitleEffectShadow, "scope.video.subtitle.effect.shadow", checked: g_SubtitleSettings.effect == .Shadow)
            .addRadioItem(strings.ui_SubtitleEffectBackdrop, "scope.video.subtitle.effect.backdrop", checked: g_SubtitleSettings.effect == .Background)
            .addRadioItem(strings.ui_SubtitleEffectNone, "scope.video.subtitle.effect.none", checked: g_SubtitleSettings.effect == .None)
        }

        menu.addPopup(strings.ui_SubtitleEffect, effectMenu)

        with let positionMenu = MenuCtrl.createPopup(menu, owner: me)
        {
            .addRadioItem(strings.ui_SubtitlePositionBottom, "scope.video.subtitle.position.bottom", checked: g_SubtitleSettings.position == .Bottom)
            .addRadioItem(strings.ui_SubtitlePositionCenter, "scope.video.subtitle.position.center", checked: g_SubtitleSettings.position == .Center)
            .addRadioItem(strings.ui_SubtitlePositionTop, "scope.video.subtitle.position.top", checked: g_SubtitleSettings.position == .Top)
        }

        menu.addPopup(strings.ui_SubtitlePosition, positionMenu)

        with let colorMenu = MenuCtrl.createPopup(menu, owner: me)
        {
            .addRadioItem(strings.ui_SubtitleColorWhite, "scope.video.subtitle.color.white", checked: g_SubtitleSettings.color == .White)
            .addRadioItem(strings.ui_SubtitleColorYellow, "scope.video.subtitle.color.yellow", checked: g_SubtitleSettings.color == .Yellow)
        }

        menu.addPopup(strings.ui_SubtitleColor, colorMenu)

        with let delayMenu = MenuCtrl.createPopup(menu, owner: me)
        {
            .addItem("-1.0 s", "scope.video.subtitle.delay.minus1")
            .addItem("-0.1 s", "scope.video.subtitle.delay.minus01")
            .addItem(strings.ui_SubtitleDelayReset, "scope.video.subtitle.delay.reset", rightName: Format.toString("%{f1} s", g_SubtitleSettings.delay))
            .addItem("+0.1 s", "scope.video.subtitle.delay.plus01")
            .addItem("+1.0 s", "scope.video.subtitle.delay.plus1")
        }

        menu.addPopup(strings.ui_SubtitleDelay, delayMenu)

        let chosen = menu.doModal(.subtitleButton, autoDestroy: true)
        if not chosen do
            return
        if chosen == "scope.video.subtitle.off"
        {
            .selectSubtitle(.Off)
            return
        }

        if .handleSubtitleSetting(chosen) do
            return
        for index in embeddedCount where chosen == embeddedCommands[index].toString()
        {
            .selectSubtitle(.Embedded, index)
            return
        }

        for index in .subtitleOverlay.sidecars.count where chosen == sidecarCommands[index].toString()
        {
            .selectSubtitle(.Sidecar, cast(u32, index))
            return
        }
    }
}

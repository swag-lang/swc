#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

// How far subtitles may be shifted either way, in seconds.
const MaxSubtitleDelay = 60.0

impl Panel
{
    // The old selection remains active until the worker has decoded a complete replacement.
    mtd loadSubtitle(fileName: string)
    {
        if .subtitleLoad.started
        {
            .pendingSubtitle = fileName
            return
        }

        .subtitleLoad.start(fileName, &LoadedSubtitle.load, me)
    }

    mtd finishSubtitleLoad()
    {
        if not .subtitleLoad.isDone() do
            return
        var loaded: LoadedSubtitle
        let failure = .subtitleLoad.finish(&loaded)
        if not failure.isEmpty()
        {
            if not .subtitleToast do
                .subtitleToast = Toast.create(me)
            .subtitleToast.show(texts().ui_SubtitleLoadFailed, failure, .Failure)
            return
        }

        if .manualSubtitleIndex < .subtitleOverlay.sidecars.count
        {
            Subtitle.Track.destroy(.subtitleOverlay.sidecars[.manualSubtitleIndex])
            .subtitleOverlay.sidecars[.manualSubtitleIndex] = unwrap loaded.track
        }
        else
        {
            .manualSubtitleIndex = cast(u32, .subtitleOverlay.sidecars.count)
            .subtitleOverlay.sidecars.add(unwrap loaded.track)
        }

        loaded.track   = null
        .subtitleReady = true
        .selectSubtitle(.Sidecar, .manualSubtitleIndex)
        .refreshInformation()
        .notePlaybackGesture()
    }

    mtd promptSubtitle()
    {
        if not .surface or not .hasFrame do
            return
        .pointerMoved()
        with var options: FileDlgOptions
        {
            .title = texts().cmd_LoadSubtitles
            .filters.add({texts().ui_OptionSubtitles, ".srt;.vtt;.ass;.ssa;.lrc;.sub"})
        }

        let dialog = FileDlg.create(.surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            .loadSubtitle(dialog.selectedPath())
    }

    // Capture the relative origin before opening the modal: playback may continue behind it.
    mtd createTimeDialog()->*EditDlg
    {
        let origin   = .currentSeconds()
        let duration = .video.durationInSeconds()
        let initial  = Viewer.timeText(origin)
        with var options: EditDlgOptions
        {
            .title   = texts().cmd_GoToTime
            .message = texts().ui_TimeHelp
            .text    = initial
            .confirmButtonText = texts().ui_Go
        }

        let dialog = EditDlg.createSingleLine(unwrap .surface, options)
        let check  = func|origin, duration, dialog|(edit: *EditBox)->EditBoxCheckResult
        {
            let valid = parseTimeAddress(edit.text(), origin, duration) >= 0
            dialog.setMessage(valid ? texts().ui_TimeHelp : texts().ui_TimeError)
            return valid ? .Valid : .InvalidVisible
        }

        dialog.edit!.setValidator(check)
        dialog.validateResult = func|view = me, dialog, origin, duration|(_, result)->bool
        {
            if result != Dialog.BtnOk do
                return true
            let target = parseTimeAddress(dialog.text(), origin, duration)
            if target < 0
            {
                discard dialog.edit!.revalidate()
                return false
            }

            view.jumpTo(target)
            view.notePlaybackGesture()
            return true
        }

        return dialog
    }

    mtd promptGoToTime()
    {
        if not .surface or not .hasFrame do
            return
        .pointerMoved()
        discard .createTimeDialog().doModal()
    }

    mtd showPlaybackHelp()
    {
        .pointerMoved()
        g_PlaybackHintUses = 0
        .refreshHelp()
        catch g_App.saveState()
    }

    mtd notePlaybackGesture()
    {
        if g_PlaybackHintUses >= 3 do
            return
        g_PlaybackHintUses += 1
        .refreshHelp()
        catch g_App.saveState()
    }

    mtd refreshHelp()
    {
        if .thumbnail or not .veilsShown or g_PlaybackHintUses >= 3
        {
            .helpLine?.hide()
            return
        }

        if not .helpLine
        {
            .helpLine = HintLine.create(me)
            .helpLine.setGrounded(true)
        }

        .helpLine.clearHints()
        .helpLine.addHint(Input.formatKeyShortcut(.None, .Space), texts().hint_Pause)
        .helpLine.addHint(texts().hint_Arrows, texts().hint_Seek)
        .helpLine.addHint(Input.formatKeyShortcut(.Control, .Space), appStrings().ui_HintLens)
        .helpLine.show()
    }

    // Replaces the active sound track without disturbing picture transport state.
    //
    // The new voice is fully positioned and configured before the old one is released, so an
    // unsupported track cannot turn a playing video silent halfway through the operation.
    mtd selectAudioTrack(index: u32) fail
    {
        if index >= .video.audioTrackCount() do
            fail BadParameterError{texts().err_AudioTrack}

        let sound = unwrap .video.audioTrack(index)
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
        .refreshControls()
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
        .refreshControls()
    }

    // Shows the subtitle for the current position shifted by the user's delay, recomputing it only
    // when the position leaves the span over which the text stays the same.
    mtd refreshSubtitle()
    {
        let track = .subtitleTrack()
        if not track
        {
            .subtitleOverlay.setSubtitle("")
            return
        }

        let seconds = .currentSeconds() + .subtitleDelay
        if .subtitleLastSeconds >= 0 and
           seconds >= .subtitleLastSeconds and
           seconds < .subtitleNextChange do
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

    // Opens playback options above their button: play mode and speed.
    mtd showOptions()
    {
        .pointerMoved()
        .showChoices(.optionsButton, func|view = me|(page) { view.describeOptions(page) })
    }

    // Opens the sound and subtitle choices above their button.
    mtd showTracks()
    {
        .pointerMoved()
        .showChoices(.tracksButton, func|view = me|(page) { view.describeTracks(page) })
    }

    // Describes the playback options: one row per setting, with the value in force.
    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings  = texts()
        let theme    = .theme()
        let iconSize = themeRowIconSize(.themeMetrics())

        .services.playback.addOptionRows(page, me)
        page.addLink(strings.ui_OptionSpeed, playbackRateText(.playbackRate), func|view = me|(speeds) { view.describeSpeeds(speeds) }, theme.icon(.PlaybackSpeed, iconSize))
        page.addAction(strings.cmd_GoToTime, func|view = me|() { view.promptGoToTime() }, disabled: not .hasFrame, closesSheet: true, icon: theme.icon(.GoTo, iconSize))
        page.addAction(strings.cmd_UndoSeek, func|view = me|() { view.undoSeek() }, disabled: .previousSeek < 0, icon: theme.icon(.ChevronLeft, iconSize))
        page.addAction(strings.cmd_PlaybackHelp, func|view = me|() { view.showPlaybackHelp() }, closesSheet: true, icon: theme.icon(.Information, iconSize))
    }

    // Describes the available sound track and subtitle choices.
    mtd describeTracks(page: *OptionSheet.Page)
    {
        let strings  = texts()
        let theme    = .theme()
        let iconSize = themeRowIconSize(.themeMetrics())

        let audioCount = .video.audioTrackCount()
        if audioCount and .audio
        {
            let current = audioTrackName(.audioTrackIndex, .audio)
            page.addLink(strings.ui_OptionAudio, current, func|view = me|(tracks) { view.describeAudioTracks(tracks) }, theme.icon(.AudioTracks, iconSize), disabled: audioCount < 2)
        }

        page.addLink(strings.ui_OptionSubtitles, .subtitleText(), func|view = me|(subtitles) { view.describeSubtitles(subtitles) }, theme.icon(.Wrap, iconSize))
    }

    mtd describeSpeeds(page: *OptionSheet.Page)
    {
        for rate in PlaybackRates do
            page.addChoice(playbackRateText(rate), rate == .playbackRate, func|view = me, rate|() { view.setPlaybackRate(rate) })
    }

    mtd describeAudioTracks(page: *OptionSheet.Page)
    {
        for index in .video.audioTrackCount()
        {
            let sound = unwrap .video.audioTrack(index)
            page.addChoice(audioTrackTitle(index, sound),
                           index == .audioTrackIndex,
                           func|view = me, index|()
                           {
                               catch view.selectAudioTrack(index) { view.services.failed(view, Viewer.failureText(Swag.err)) }
                           },
                           detail: audioDetailsText(sound),
                           note: audioTrackLanguage(sound))
        }
    }

    // Names the subtitles in force, as the first page of the options shows them.
    mtd subtitleText()->String
    {
        let track = .subtitleTrack()
        if not track do
            return String.from(texts().ui_SubtitleOff)
        return subtitleTrackName(.subtitleTrackIndex, track)
    }

    // Describes the subtitles: the tracks to choose from, then how they are drawn and when.
    mtd describeSubtitles(page: *OptionSheet.Page)
    {
        let strings = texts()
        page.addAction(strings.cmd_LoadSubtitles, func|view = me|() { view.promptSubtitle() }, disabled: .subtitleLoad.started, closesSheet: true, icon: .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics())))
        page.addHeading(strings.ui_SubtitleTrack)
        page.addChoice(strings.ui_SubtitleOff, .subtitleSource == .Off, func|view = me|() { view.selectSubtitle(.Off) })
        for index in .video.subtitleTrackCount()
        {
            let track = unwrap .video.subtitleTrack(index)
            let on    = .subtitleSource == .Embedded and .subtitleTrackIndex == index
            page.addChoice(subtitleTrackTitle(index, track),
                           on,
                           func|view = me, index|() { view.selectSubtitle(.Embedded, index) },
                           detail: strings.ui_SubtitleEmbedded,
                           note: subtitleTrackLanguage(track))
        }

        for track, index in .subtitleOverlay.sidecars
        {
            let on = .subtitleSource == .Sidecar and .subtitleTrackIndex == index
            page.addChoice(subtitleTrackTitle(cast(u32, index), track),
                           on,
                           func|view = me, index|()
                           {
                               view.selectSubtitle(.Sidecar, cast(u32, index))
                           },
                           detail: strings.ui_SubtitleSidecar,
                           note: subtitleTrackLanguage(track))
        }

        // Positive values present cues earlier; the wording makes the direction explicit.
        page.addStepper(strings.ui_SubtitleDelay,
                        Format.toString("%{f2} s", .subtitleDelay),
                        func|view = me|(step)
                        {
                            view.subtitleDelay       = Math.clamp(view.subtitleDelay + step * 0.05, -MaxSubtitleDelay, MaxSubtitleDelay)
                            view.subtitleLastSeconds = -1
                            view.refreshSubtitle()
                        },
                        canDecrease: .subtitleDelay > -MaxSubtitleDelay,
                        canIncrease: .subtitleDelay < MaxSubtitleDelay)
        if .subtitleDelay != 0 do
            page.addAction(strings.ui_SubtitleDelayReset, func|view = me|() { view.subtitleDelay = 0; view.subtitleLastSeconds = -1; view.refreshSubtitle() }, icon: .theme().icon(.Update, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_SubtitleAppearance, "", func|view = me|(appearance) { view.describeSubtitleAppearance(appearance) }, .theme().icon(.Appearance, themeRowIconSize(.themeMetrics())))
    }

    // Shared appearance stays one page away so attachment and timing fit a short window.
    mtd describeSubtitleAppearance(page: *OptionSheet.Page)
    {
        let strings = texts()
        let style   = &g_SubtitleSettings
        page.addLink(strings.ui_SubtitleFont,
                     subtitleFontText(style.font),
                     func|view = me|(fonts)
                     {
                         for font in [SubtitleFont.Sans, .Monospace] do
                             fonts.addChoice(subtitleFontText(font), g_SubtitleSettings.font == font, func|view, font|() { g_SubtitleSettings.font = font; view.subtitleSettingsChanged() })
                     },
                     icon: .theme().icon(.Edit, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_SubtitleSize,
                     subtitleSizeText(style.size),
                     func|view = me|(sizes)
                     {
                         for size in [SubtitleSize.Small, .Normal, .Large, .VeryLarge] do
                             sizes.addChoice(subtitleSizeText(size), g_SubtitleSettings.size == size, func|view, size|() { g_SubtitleSettings.size = size; view.subtitleSettingsChanged() })
                     },
                     icon: .theme().icon(.ZoomIn, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_SubtitleEffect,
                     subtitleEffectText(style.effect),
                     func|view = me|(effects)
                     {
                         for effect in [SubtitleEffect.Outline, .Shadow, .Background, .None] do
                             effects.addChoice(subtitleEffectText(effect), g_SubtitleSettings.effect == effect, func|view, effect|() { g_SubtitleSettings.effect = effect; view.subtitleSettingsChanged() })
                     },
                     icon: .theme().icon(.Appearance, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_SubtitlePosition,
                     subtitlePositionText(style.position),
                     func|view = me|(positions)
                     {
                         for position in [SubtitlePosition.Bottom, .Center, .Top] do
                             positions.addChoice(subtitlePositionText(position), g_SubtitleSettings.position == position, func|view, position|() { g_SubtitleSettings.position = position; view.subtitleSettingsChanged() })
                     },
                     icon: .theme().icon(.GoTo, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_SubtitleColor,
                     subtitleColorText(style.color),
                     func|view = me|(colors)
                     {
                         for color in [SubtitleColor.White, .Yellow] do
                             colors.addChoice(subtitleColorText(color), g_SubtitleSettings.color == color, func|view, color|() { g_SubtitleSettings.color = color; view.subtitleSettingsChanged() })
                     },
                     icon: .theme().icon(.Picker, themeRowIconSize(.themeMetrics())))
    }
}

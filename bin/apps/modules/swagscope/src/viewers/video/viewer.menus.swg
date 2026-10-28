#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

// How far subtitles may be shifted either way, in seconds.
const MaxSubtitleDelay = 60.0

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
        .refreshChips()
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
        .refreshChips()
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

        let seconds = .currentSeconds() + g_SubtitleSettings.delay
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

    // Opens the options of the film above the chip of the speed: play mode, speed, sound track and
    // subtitles. The veils come with it, since the sheet stands on one.
    mtd showOptions()
    {
        .pointerMoved(true)
        .showChoices(.speedChip, func|view = me|(page) { view.describeOptions(page) })
    }

    // Describes the first page of the options: one row per setting, with the value in force.
    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings  = texts()
        let theme    = .theme()
        let iconSize = themeRowIconSize(.themeMetrics())

        .services.playback.addOptionRows(page, me)
        page.addLink(strings.ui_OptionSpeed, playbackRateText(.playbackRate), func|view = me|(speeds) { view.describeSpeeds(speeds) }, theme.icon(.PlaybackSpeed, iconSize))

        // A film with one sound track names it, so the reader knows what plays, but offers no choice.
        let audioCount = .video.audioTrackCount()
        if audioCount and .audio
        {
            let current = RichString.plainText(audioTrackName(.audioTrackIndex, .audio))
            page.addLink(strings.ui_OptionAudio, current, func|view = me|(tracks) { view.describeAudioTracks(tracks) }, theme.icon(.AudioTracks, iconSize), disabled: audioCount < 2)
        }

        page.addLink(strings.ui_OptionSubtitles, .subtitleText(), func|view = me|(subtitles) { view.describeSubtitles(subtitles) }, theme.icon(.Wrap, iconSize), disabled: not .subtitleReady)
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
            page.addChoice(audioTrackName(index, sound),
                           index == .audioTrackIndex,
                           func|view = me, index|()
                           {
                               catch view.selectAudioTrack(index) { view.services.failed(view, Viewer.failureText(Swag.err)) }
                           },
                           detail: audioDetailsText(sound))
        }
    }

    // Names the subtitles in force, as the first page of the options shows them.
    mtd subtitleText()->String
    {
        let track = .subtitleTrack()
        if not track do
            return String.from(texts().ui_SubtitleOff)
        return RichString.plainText(subtitleTrackName(.subtitleTrackIndex, track))
    }

    // Describes the subtitles: the tracks to choose from, then how they are drawn and when.
    mtd describeSubtitles(page: *OptionSheet.Page)
    {
        let strings = texts()
        page.addHeading(strings.ui_SubtitleTrack)
        page.addChoice(strings.ui_SubtitleOff, .subtitleSource == .Off, func|view = me|() { view.selectSubtitle(.Off) })
        for index in .video.subtitleTrackCount()
        {
            let track = unwrap .video.subtitleTrack(index)
            let on    = .subtitleSource == .Embedded and .subtitleTrackIndex == index
            page.addChoice(subtitleTrackName(index, track), on, func|view = me, index|() { view.selectSubtitle(.Embedded, index) }, detail: strings.ui_SubtitleEmbedded)
        }

        for track, index in .subtitleOverlay.sidecars
        {
            let on = .subtitleSource == .Sidecar and .subtitleTrackIndex == index
            page.addChoice(subtitleTrackName(cast(u32, index), track),
                           on,
                           func|view = me, index|()
                           {
                               view.selectSubtitle(.Sidecar, cast(u32, index))
                           },
                           detail: strings.ui_SubtitleSidecar)
        }

        // The appearance is shared by every film and saved with the window, so each choice is
        // written into the shared settings and drawn again at once.
        page.addHeading(strings.ui_SubtitleAppearance)
        let style = &g_SubtitleSettings
        page.addLink(strings.ui_SubtitleFont, subtitleFontText(style.font), func|view = me|(fonts)
        {
            for font in [SubtitleFont.Sans, .Monospace] do
                fonts.addChoice(subtitleFontText(font), g_SubtitleSettings.font == font, func|view, font|() { g_SubtitleSettings.font = font; view.subtitleSettingsChanged() })
        })

        page.addLink(strings.ui_SubtitleSize, subtitleSizeText(style.size), func|view = me|(sizes)
        {
            for size in [SubtitleSize.Small, .Normal, .Large, .VeryLarge] do
                sizes.addChoice(subtitleSizeText(size), g_SubtitleSettings.size == size, func|view, size|() { g_SubtitleSettings.size = size; view.subtitleSettingsChanged() })
        })

        page.addLink(strings.ui_SubtitleEffect, subtitleEffectText(style.effect), func|view = me|(effects)
        {
            for effect in [SubtitleEffect.Outline, .Shadow, .Background, .None] do
                effects.addChoice(subtitleEffectText(effect), g_SubtitleSettings.effect == effect, func|view, effect|() { g_SubtitleSettings.effect = effect; view.subtitleSettingsChanged() })
        })

        page.addLink(strings.ui_SubtitlePosition, subtitlePositionText(style.position), func|view = me|(positions)
        {
            for position in [SubtitlePosition.Bottom, .Center, .Top] do
                positions.addChoice(subtitlePositionText(position), g_SubtitleSettings.position == position, func|view, position|() { g_SubtitleSettings.position = position; view.subtitleSettingsChanged() })
        })

        page.addLink(strings.ui_SubtitleColor, subtitleColorText(style.color), func|view = me|(colors)
        {
            for color in [SubtitleColor.White, .Yellow] do
                colors.addChoice(subtitleColorText(color), g_SubtitleSettings.color == color, func|view, color|() { g_SubtitleSettings.color = color; view.subtitleSettingsChanged() })
        })

        // A step is a tenth of a second, a second with Shift, within a minute either way.
        page.addStepper(strings.ui_SubtitleDelay,
                        Format.toString("%{f1} s", style.delay),
                        func|view = me|(step)
                        {
                            g_SubtitleSettings.delay = Math.clamp(g_SubtitleSettings.delay + step * 0.1, -MaxSubtitleDelay, MaxSubtitleDelay)
                            view.subtitleSettingsChanged()
                        },
                        canDecrease: style.delay > -MaxSubtitleDelay,
                        canIncrease: style.delay < MaxSubtitleDelay)
        if style.delay != 0 do
            page.addAction(strings.ui_SubtitleDelayReset, func|view = me|() { g_SubtitleSettings.delay = 0; view.subtitleSettingsChanged() })
    }
}

#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

impl Panel
{
    // Sizes the run-ahead queue from the picture size.
    //
    // The queue has to cover the longest gap the decoder can leave, which is one key picture,
    // and every slot costs a whole frame of memory. Bounding it by bytes rather than by count
    // gives a small stream a deep queue and a 4K stream one that still covers that gap.
    mtd prepareSlots()
    {
        // A planar picture costs half of what the packed one would, so the same budget buys twice
        // the run-ahead on exactly the streams whose key pictures are the most expensive.
        .slotCount = prefetchSlotCount(.video.width(), .video.height(), .planar)
        .slots.resize(.slotCount)
        .freeSlots.clear()
        for index in .slotCount do
            .freeSlots.add(cast(u32, index))
    }

    // Aims the producer at `index`, dropping everything it had already decoded past it.
    //
    // A reposition that is still waiting for its own picture is not repeated: a starved queue
    // asks for the same sync frame on every tick, and restarting the decoder each time would
    // never let it fill.
    //
    // `notifyLoading` lets a loop wrap keep the last picture on screen without the wait overlay:
    // the reposition resolves within one decode, which is not worth announcing as loading.
    mtd repositionTo(index: u64, notifyLoading = true)
    {
        var notify: bool
        {
            Sync.scopedLock(&.queueLock)
            if .anchorPending and .produceFrom == index and not .hasFailure do
                return

            notify = notifyLoading and .hasFrame and not .awaitingFrame
            for slot in .ready do
                .freeSlots.add(slot)
            .ready.clear()
            .nextDecode    = index
            .produceFrom   = index
            .generation    += 1
            .hasFailure    = false
            .awaitingFrame = true
            .anchorPending = true
        }

        if notify do
            .services.loadingChanged(me)
    }

    // Gives up every picture between here and `index`, and moves playback there.
    //
    // Skipping is a decision that what lies between is not going to be shown; the sound that
    // goes with it cannot be played either, so the position moves with the picture. Leaving the
    // clock where it stood would present the picture that comes back only once the clock
    // reached it, which is a frozen picture for as long as the skip was worth - and a skip is
    // worth a whole group of pictures on a stream that marks one every ten seconds.
    mtd skipTo(index: u64)
    {
        if .playing and .voice
        {
            catch .voice.pause()
            .resumeAudioAfterSeek = true
        }

        .elapsed = .frameSeconds(index)
        .clock.reset()
        .audioClockLast = -1
        if .voice and .audio do
            .audioRangePending = not soundCovers(.audio, .elapsed)

        .repositionTo(index)
        .decodeWake.signal()
    }

    // Decodes one picture into a slot, propagating any failure to the producer.
    //
    // A codec that reconstructs planes hands them over as they are; one that does not produces the
    // packed picture itself. Only the queue knows which of the two a slot holds.
    private mtd decodeIntoSlot(slot: u32, index: u64) fail
    {
        if .planar
        {
            try .video.decodeFramePlanesInto(&.slots[cast(u64, slot)].planes, index)
            return
        }

        try .video.decodeFrameInto(&.slots[cast(u64, slot)].image, index)
    }

    // Decodes one queued picture, and reports whether the producer can immediately do more.
    mtd produceOne()->bool
    {
        var slot       = 0'u32
        var index      = 0'u64
        var generation = 0'u32
        {
            Sync.scopedLock(&.queueLock)
            if .hasFailure or .freeSlots.isEmpty() do
                return false
            let count = .video.frameCount()
            if count and .nextDecode >= count do
                return false

            // A paused viewer wants the picture it is parked on and nothing more.
            if not .playing and (not .ready.isEmpty() or .inFlight != 0 or .nextDecode != .produceFrom) do
                return false

            slot        = .freeSlots.popBack()
            index       = .nextDecode
            generation  = .generation
            .nextDecode += 1
            .inFlight   += 1
        }

        catch .decodeIntoSlot(slot, index) as decodeError

        Sync.scopedLock(&.queueLock)
        .inFlight -= 1
        if generation != .generation
        {
            .freeSlots.add(slot)
            return true
        }

        if decodeError != null
        {
            .failureText = Viewer.failureText(decodeError)
            .hasFailure  = true
            .freeSlots.add(slot)
            return false
        }

        .slots[cast(u64, slot)].index = index
        .ready.add(slot)
        return true
    }

    // Publishes the queued picture the clock is on, and reports whether one reached the screen.
    //
    // Every decoded picture is presented while playback keeps up: the decoder is asked only for
    // the pictures playback intends to show, so a queued one is never obsolete, and presenting
    // them in order is what keeps motion smooth when the clock has run ahead.
    //
    // Past that, one picture per call is a ceiling, and the caller is the event loop of the
    // application: one turn of that loop presents the window, which costs tens of milliseconds
    // whenever the compositor is busy. A stream asking for more pictures than the loop turns
    // would then fall behind by the difference for as long as it plays — silently, since the
    // queue stays full and nothing looks starved. `catchUpTo` names the last picture the clock
    // has reached: everything before it is released unshown, so the picture stays on the clock
    // and the loss is bounded to pictures whose time has already gone.
    mtd publishHead(catchUpTo: u64 = 0, catchUp = false)->bool
    {
        var chosen = NoSlot
        var failure: String
        {
            Sync.scopedLock(&.queueLock)
            if not .ready.isEmpty()
            {
                while catchUp and .ready.count > 1 and .slots[cast(u64, .ready[1])].index <= catchUpTo
                {
                    .freeSlots.add(.ready[0])
                    .ready.removeAtOrdered(0)
                }

                chosen = .ready[0]
                .ready.removeAtOrdered(0)
            }
            elif .hasFailure
            {
                failure     = .failureText
                .hasFailure = false
            }
        }

        if not failure.isEmpty()
        {
            .resumeAudioAfterSeek = false
            if .voice
            {
                .elapsed = .audio!.timelineStartSeconds() + .voice.playbackPositionSeconds()
                catch .voice.pause()
            }

            .playing       = false
            .awaitingFrame = false
            .clock.reset()
            .services.failed(me, failure)
            return false
        }

        if chosen == NoSlot do
            return false

        let notifyLoading = .awaitingFrame
        .frameIndex    = .slots[cast(u64, chosen)].index
        .hasFrame      = true
        .awaitingFrame = false
        catch .finishMetadata() as metadataError
        if metadataError != null
        {
            .services.failed(me, Viewer.failureText(metadataError))
            return false
        }

        if .autoPlayPending
        {
            .autoPlayPending      = false
            .playing              = true
            .resumeAudioAfterSeek = .voice != null
        }

        if .anchorPending
        {
            // A jump moved the producer, so the silent clock follows the picture that came back
            // rather than the position it asked for. Sound is the master clock when there is
            // one, and its timeline is never moved to conceal video decode latency.
            .anchorPending = false
            if .playing
            {
                .elapsed = .frameSeconds(.frameIndex)
                if not .voice do
                    .clock.restart()
            }
        }

        if .planar
        {
            let picture = .slots[cast(u64, chosen)].planes.view()
            .imageView.updateVideoFrame(&picture)
        }
        else
        {
            .imageView.exchangeImage(&.slots[cast(u64, chosen)].image)
        }

        {
            Sync.scopedLock(&.queueLock)
            .freeSlots.add(chosen)
        }

        .decodeWake.signal()
        .refreshTransport()
        if notifyLoading do
            .services.loadingChanged(me)

        // A transport seek holds the audio clock until its target picture is on screen. This
        // avoids showing the previous picture while sound has already jumped to the new time.
        if .resumeAudioAfterSeek do
            .resumeAudio()
        return true
    }

    // Positions playback on one picture and asks the producer for it.
    mtd showFrame(index: u64)->bool
    {
        let count = .video.frameCount()
        if count and index >= count do
            return false
        if .hasFrame and not .awaitingFrame and index == .frameIndex do
            return true
        .repositionTo(index)
        .decodeWake.signal()
        discard .publishHead()
        return true
    }

    // Moves playback to frame `index`, clamped to the last frame. While playing, the sound pauses
    // and resumes only once the requested picture is shown, so both restart together.
    mtd seekFrame(index: u64)
    {
        let count = .video.frameCount()
        if not count and .video.durationInSeconds() <= 0 do
            return
        let target      = count ? Math.min(index, count - 1) : index
        let resumeAudio = .playing and .voice != null
        .resumeAudioAfterSeek = resumeAudio
        if resumeAudio do
            catch .voice!.pause()
        if .playing do
            .clock.reset()
        .elapsed = .frameSeconds(target)

        if .voice and .audio
        {
            let coversRange = soundCovers(.audio, .elapsed)
            .audioRangePending = not coversRange

            // A paused transport has no later resume point at which to position the sound.
            // Playing seeks wait for the requested picture and are handled by `resumeAudio`.
            if coversRange and not resumeAudio
            {
                let sample = soundSample(.audio, .elapsed)
                catch .voice.seekSampleFrame(sample) as seekError
                if seekError != null
                {
                    .playing = false
                    .audioRangePending = false
                    catch .voice.pause()
                    .services.failed(me, Viewer.failureText(seekError))
                    return
                }
            }
        }

        if not .showFrame(target) do
            return
        .refreshTransport()
        if .resumeAudioAfterSeek and .frameIndex == target do
            .resumeAudio()

        .audioClockLast = -1
    }

    // Wraps playback to the first picture without the pause a cold user seek shows.
    //
    // A replay is not a reader's seek: the sound restarts at its first sample right away instead
    // of waiting for the picture queue to rebuffer, and the last picture keeps the screen,
    // without the wait overlay, for exactly the decode of the first one.
    mtd restartForLoop()
    {
        .elapsed              = 0
        .resumeAudioAfterSeek = false
        .audioClockLast       = -1
        .clock.restart()

        if .voice and .audio
        {
            .audioRangePending = not soundCovers(.audio, 0)
            if not .audioRangePending
            {
                catch .voice.seekSampleFrame(soundSample(.audio, 0)) as seekError
                if seekError != null
                {
                    .playing = false
                    catch .voice.pause()
                    .refreshTransport()
                    .services.failed(me, Viewer.failureText(seekError))
                    return
                }

                catch .voice.play()
            }
        }

        .repositionTo(0, notifyLoading: false)
        .decodeWake.signal()
    }

    // Pauses or resumes playback; resuming at the last frame restarts from the beginning.
    mtd togglePlayback()
    {
        if not .hasFrame do
            return
        if .playing
        {
            .resumeAudioAfterSeek = false
            .elapsed = .currentSeconds()
            if .voice do
                catch .voice.pause()
            .clock.reset()
            .playing = false
        }
        else
        {
            let count = .video.frameCount()
            if count and .frameIndex + 1 >= count
            {
                .elapsed = 0
                discard .showFrame(0)
                if .voice do
                    catch .voice.seekSampleFrame(0)
            }

            .audioClockLast = -1
            .clock.restart()
            .playing = true
            .resumeAudio()
            if not .playing do
                return
            .decodeWake.signal()
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if not .hasFrame do
            return
        .playing              = false
        .resumeAudioAfterSeek = false
        .audioRangePending    = false
        .elapsed              = 0
        .clock.reset()
        if .voice do
            catch .voice.stop()
        discard .showFrame(0)
        .refreshTransport()
    }

    // Returns the picture the playback clock is currently on.
    mtd clockFrame()->u64 => .video.frameAtTime(.currentSeconds())

    // Advances presentation by at most one picture, and decides when to give up and skip.
    //
    // Presentation follows the run-ahead queue: a picture is shown once the clock reaches it,
    // and every decoded picture is shown. Only a starved queue means the decoder is not
    // keeping up, and only a queue starved for whole seconds is worth answering with a jump to
    // the next sync frame — the one target that costs a single decoded picture rather than the
    // decode of everything in between.
    mtd updatePlayback()
    {
        if not .openFinished
        {
            catch .completeOpen() as openError
            if openError != null do
                .services.failed(me, Viewer.failureText(openError))
            return
        }

        if not .video.isOpen() do
            return

        catch .finishMetadata() as metadataError
        if metadataError != null
        {
            .services.failed(me, Viewer.failureText(metadataError))
            return
        }

        if not .playing
        {
            discard .publishHead()
            return
        }

        // A jump left the sound waiting on the queue rather than on the first picture; see
        // `RebufferPictures`. Until it fills, the clock stands where the jump put it.
        if .resumeAudioAfterSeek and .voice and .hasFrame
        {
            let count = .video.frameCount()
            var depth = 0'u64
            var more: bool
            {
                Sync.scopedLock(&.queueLock)
                depth = .ready.count
                more  = not .hasFailure and (not count or .nextDecode < count)
            }

            // The end of the stream is the one place where the queue never reaches the mark.
            if depth < rebufferPictureCount(.slotCount) and more do
                return
            .resumeAudio()
        }

        .followAudioClock()
        if .audioRangePending and .audio and soundCovers(.audio, .currentSeconds()) do
            .resumeAudio()

        var head  = 0'u64
        var empty = true
        {
            Sync.scopedLock(&.queueLock)
            if not .ready.isEmpty()
            {
                head  = .slots[cast(u64, .ready[0])].index
                empty = false
            }
        }

        let clock = .clockFrame()
        if not empty
        {
            // While playback keeps up the clock only gates when the next picture is due; past
            // that it also decides how many of the queued ones are already too late to show.
            if .anchorPending or head <= clock do
                discard .publishHead(clock, not .anchorPending)
            return
        }

        // The movie has been played through: the window's play mode says what follows. Parked
        // on its last picture, the transport keeps that picture on screen until the reader acts
        // or, when another file is on its way, until the host can show that one.
        let count = .video.frameCount()
        if count and clock >= count and .frameIndex + 1 >= count
        {
            let continuation = .services.finished(me)
            if continuation == .Replay
            {
                .restartForLoop()
                return
            }

            .playing              = false
            .resumeAudioAfterSeek = false
            .audioRangePending    = false
            .elapsed              = .video.durationInSeconds()
            .clock.reset()
            if .voice do
                catch .voice.pause()
            .refreshTransport()
            return
        }

        // A jump already asked for has not produced its picture yet. Waiting for it is not
        // falling behind, and asking for another one would restart the whole decoder over and
        // over while its pipeline fills.
        if .anchorPending do
            return

        // The queue is empty: the decoder is behind. Past the resync bound, skip to the next
        // sync frame instead of walking pictures the viewer will never catch up with.
        let rate      = .video.frameRate()
        let resyncLag = cast(u64, (rate.framesPerSecond() * ResyncSeconds))
        if clock < .frameIndex + resyncLag do
            return

        let sync = .video.syncFrameAt(clock)
        let cap  = cast(u64, (rate.framesPerSecond() * ResyncMaxJumpSeconds))
        if (count and sync >= count) or sync - clock > cap do
            return

        .skipTo(sync)
    }
}

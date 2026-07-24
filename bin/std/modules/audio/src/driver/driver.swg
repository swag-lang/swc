using Core

enum UpdateCommand
{
    Register
    Destroy
    UpdateBuffers
}

// The sound driver
struct Driver
{
    using native: DriverNative

    updateTh:            Threading.Thread
    wakeupUpdate:        Sync.Event
    mutexVoicesToUpdate: Sync.Mutex
    voicesToUpdate:      Array'{ voice: *Voice, command: UpdateCommand }

    mutexRecycleVoices:   Sync.Mutex
    activeVoices:         Array'(*Voice)
    pendingRecycleVoices: Array'(*Voice)
    toRecycleVoices:      Array'(*Voice)

    mutexBuses: Sync.Mutex
    buses:      Array'(*Bus)

    driverIsClosing: bool
}

internal func updateThreadProc(th: Threading.Thread)
{
    let driver = &g_Driver
    while !th.requestEnd
    {
        // Wait for an update to be requested
        driver.wakeupUpdate.wait()
        if th.requestEnd do
            break

        // All pending recycles to actual recycle list
        driver.mutexRecycleVoices.lock()
        for voice in driver.pendingRecycleVoices do
            driver.toRecycleVoices.add(voice)
        driver.mutexRecycleVoices.unlock()
        driver.pendingRecycleVoices.clear()

        // Make a copy of the list of voices to update, to reduce contention.
        // The #move resets the array, so re-pin its allocator right away: the next
        // add can come from any thread (main, update, xaudio2 callback), and letting
        // it cache that thread's context allocator would make the buffer bounce
        // between different heaps (allocated on one, freed on another).
        driver.mutexVoicesToUpdate.lock()
        let copyVoices = #move driver.voicesToUpdate
        driver.voicesToUpdate.clear()
        driver.voicesToUpdate.allocator = copyVoices.allocator
        driver.mutexVoicesToUpdate.unlock()

        // Update
        for cmd in copyVoices
        {
            let voice = cmd.voice
            if th.requestEnd do
                break

            switch cmd.command
            {
            case Register:
                voice.idxInList = cast() driver.activeVoices.count
                driver.activeVoices.add(voice)

            case Destroy:
                voice.setState(.PendingDestroy)
                catch voice.stopNative()
                voice.destroyNative()

                let idx = voice.idxInList
                driver.activeVoices.removeAt(idx)
                if idx != driver.activeVoices.count do
                    driver.activeVoices[idx].idxInList = idx
                driver.pendingRecycleVoices.add(voice)

            case UpdateBuffers:

                // Update buffer of voice, and stop it if nothing has been updated (end reached)
                if catch voice.updateNative() == false
                {
                    voice.closeBuffer()
                    voice.resetState(.Playing)
                }

                // If the voice is no more playing, register it for destruction if necessary
                if !voice.isPlaying() and voice.playFlags.has(.DestroyOnStop) do
                    voice.destroy()
            }
        }
    }
}

impl Driver
{
    mtd create(kind: DriverKind = .Default) throw
    {
        .driverIsClosing = false

        // Pin the shared command list to the creating context's allocator: its
        // buffer is reallocated and freed from several threads (main, update
        // thread, xaudio2 callbacks), and every one of them must use the same heap.
        .voicesToUpdate.allocator = @getcontext().allocator

        .createNative(kind)

        .wakeupUpdate.init()
        .updateTh.init(&updateThreadProc)
        .updateTh.start()
    }

    mtd destroy()
    {
        .driverIsClosing = true

        // Halt the backend's audio processing thread first: from here on no mixer
        // pass reads submitted buffers and no voice callback can fire, so the
        // voices below can be destroyed and freed safely.
        ////////////////
        .stopEngineNative()

        // Force update thread to end
        ////////////////
        .updateTh.safeForceEnd()
        .wakeupUpdate.signal()
        .updateTh.wait()
        .wakeupUpdate.release()

        // Be sure no update can come during the closing.
        // If there's a Register update, then register the voice to be destroyed, as it's not
        // yet registered in the active list
        ////////////////
        .mutexVoicesToUpdate.lock()
        for cmd in .voicesToUpdate
        {
            if cmd.command == .Register do
                .toRecycleVoices.add(cmd.voice)
        }

        .voicesToUpdate.clear()
        .mutexVoicesToUpdate.unlock()

        // Destroy voices lists
        ////////////////
        .toRecycleVoices.add(.pendingRecycleVoices.toSlice())
        .pendingRecycleVoices.clear()

        for voice in .toRecycleVoices do
            Memory.delete(voice)
        .toRecycleVoices.clear()

        for voice in .activeVoices
        {
            catch voice.stopNative()
            voice.destroyNative()
            Memory.delete(voice)
        }

        .activeVoices.clear()

        // Destroy buses
        ////////////////
        for bus in .buses do
            catch bus.destroy()
        .buses.clear()

        // Then destroy native driver
        ////////////////
        .destroyNative()
    }

    mtd updateVoice(voice: *Voice, cmd: UpdateCommand)
    {
        // The no-sound driver has no real-time buffer feeding: its playback is advanced
        // deterministically by explicit updateNoSound() calls (used by tests). Letting the
        // background thread feed its buffers would consume the whole stream instantly and
        // race those checks (e.g. flip isPlaying to false right after play()). Registration
        // and destruction still go through the thread.
        if .kind == .NoSound and cmd == .UpdateBuffers do
            return

        .mutexVoicesToUpdate.lock()
        defer .mutexVoicesToUpdate.unlock()
        if .driverIsClosing do
            return
        .voicesToUpdate.add({voice, cmd})
        .wakeupUpdate.signal()
    }

    mtd createVoice()->*Voice
    {
        var back: #null *Voice
        .mutexRecycleVoices.lock()
        if !.toRecycleVoices.isEmpty() do
            back = .toRecycleVoices.popBack()
        .mutexRecycleVoices.unlock()
        if back do
            back.recycle()
        return back orelse Memory.new'Voice()
    }

    mtd setOutputVolume(volume: f32) throw => .native.setOutputVolumeNative(volume)

    mtd getOutputVolume()->f32 => .native.getOutputVolumeNative()
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

struct AudioTeardownAllocator
{
    late upstream: IAllocator
    nativeParent, nativeChild, nativeVoice: *void?
    parentFreed, childFreed, voiceFreed, parentBeforeChild: bool
}

var g_AudioTeardownAllocator: AudioTeardownAllocator

func verifyDriverCreateRetry(failure: DriverCreateFailure) fail
{
    g_DriverCreateFailure = failure
    var outcome: Swag.Error
    catch g_Driver.create(.NoSound) as outcome
    g_DriverCreateFailure = .None

    Swag.require(outcome.value() is Errors.BadParameterError)
    Swag.require(not g_Driver.isCreated)
    Swag.require(g_Driver.kind == .Default)
    Swag.require(not g_Driver.wakeupUpdate.isValid())
    Swag.require(not g_Driver.updateTh.isValid())

    discard expect createNoSoundEngine()
    destroyEngine()
}

struct AudioDestroyRequestProbe
{
    voice:   *Voice
    ready:   u32
    start:   u32
    winners: u32
    done:    u32
}

func requestVoiceDestroyOnce(thread: const *Threading.Thread)
{
    let probe = cast(*AudioDestroyRequestProbe, unwrap thread.userParam)
    for iteration in 128
    {
        let round = cast(u32, iteration + 1)
        Atomic.add(&probe.ready, 1)
        while Atomic.get(&probe.start) != round do
            Threading.Thread.yield()
        if probe.voice.markPendingDestroy() do
            Atomic.add(&probe.winners, 1)
        Atomic.add(&probe.done, 1)
    }
}

impl IAllocator for AudioTeardownAllocator
{
    mtd impl alloc(request: *AllocatorRequest)   => .upstream.alloc(request)
    mtd impl realloc(request: *AllocatorRequest) => .upstream.realloc(request)

    mtd impl free(request: *AllocatorRequest)
    {
        if request.address == .nativeChild do
            .childFreed = true
        if request.address == .nativeParent
        {
            .parentBeforeChild = not .childFreed
            .parentFreed       = true
        }

        if request.address == .nativeVoice do
            .voiceFreed = true
        .upstream.free(request)
    }
}

// Failed engine initialization releases native resources and leaves the driver reusable.
#test
{
    expect verifyDriverCreateRetry(.AfterEventInit)
    expect verifyDriverCreateRetry(.AfterThreadInit)
}

// Parents outlive their children, including after removing an unrelated bus.
#test
{
    for removeUnrelated in [false, true]
    {
        discard expect createNoSoundEngine()
        g_AudioTeardownAllocator = {upstream: g_Driver.allocationAllocator}
        let allocator = &g_AudioTeardownAllocator
        g_Driver.allocationAllocator = allocator
        let unrelated = expect Bus.create(2)
        let parent    = expect Bus.create(2)
        let child     = expect Bus.create(1, parent)
        allocator.nativeParent = parent.handle
        allocator.nativeChild  = child.handle
        if removeUnrelated do
            unrelated.destroy()
        destroyEngine()
        Swag.require(allocator.childFreed and allocator.parentFreed)
        Swag.require(not allocator.parentBeforeChild, "audio parent was released before its child")
    }
}

// A registration queued just before shutdown still owns a live native voice.
#test
{
    discard expect createNoSoundEngine()
    g_AudioTeardownAllocator = {upstream: g_Driver.allocationAllocator}
    let allocator = &g_AudioTeardownAllocator
    g_Driver.allocationAllocator = allocator

    // End processing without reaping the thread handle; destroyEngine owns that join.
    g_Driver.updateTh.safeForceEnd()
    g_Driver.wakeupUpdate.signal()
    while not g_Driver.updateTh.isDone() do
        Threading.Thread.yield()
    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice = expect Voice.create(&file)
    allocator.nativeVoice = voice.handle
    Swag.require(g_Driver.activeVoices.isEmpty())
    destroyEngine()
    Swag.require(allocator.voiceFreed, "shutdown leaked an unregistered native voice")
}

// Destruction waits for an in-flight transport operation before releasing voice resources.
#test
{
    if Swag.jit() do
        return
    discard expect createNoSoundEngine()
    defer destroyEngine()

    var file = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice = expect Voice.create(&file)
    var recycledWhileLocked = false
    scope {
        voice.dataMutex.lock()
        defer voice.dataMutex.unlock()
        voice.destroy()

        // Wait until the update thread has taken the queued registration and destroy commands.
        var commandsPending = true
        var attempt = 0
        while attempt < 1000
        {
            attempt += 1
            g_Driver.mutexVoicesToUpdate.lock()
            commandsPending = not g_Driver.voicesToUpdate.isEmpty()
            g_Driver.mutexVoicesToUpdate.unlock()
            if not commandsPending do
                break
            Threading.Thread.sleep(1'ms)
        }
        Swag.require(not commandsPending, "audio update thread did not take the destroy command")

        // Keep waking the worker so a completed destroy reaches the visible recycler list.
        attempt = 0
        while attempt < 1000
        {
            attempt += 1
            g_Driver.wakeupUpdate.signal()
            Threading.Thread.sleep(1'ms)
            g_Driver.mutexRecycleVoices.lock()
            for recycledVoice in g_Driver.toRecycleVoices do
                if recycledVoice == voice do
                    recycledWhileLocked = true
            g_Driver.mutexRecycleVoices.unlock()
            if recycledWhileLocked do
                break
        }
    }
    Swag.require(not recycledWhileLocked, "voice was recycled while its data mutex was held")

    var recycledAfterUnlock = false
    var attempt = 0
    while attempt < 1000
    {
        attempt += 1
        g_Driver.wakeupUpdate.signal()
        Threading.Thread.sleep(1'ms)
        g_Driver.mutexRecycleVoices.lock()
        for recycledVoice in g_Driver.toRecycleVoices do
            if recycledVoice == voice do
                recycledAfterUnlock = true
        g_Driver.mutexRecycleVoices.unlock()
        if recycledAfterUnlock do
            break
    }
    Swag.require(recycledAfterUnlock, "voice was not recycled after releasing its data mutex")

// Repeated destroy requests queue one destruction for a voice.
#test
{
    discard expect createNoSoundEngine()
    defer destroyEngine()

    // Keep the update queue stable while exercising repeated destroy requests.
    g_Driver.updateTh.safeForceEnd()
    g_Driver.wakeupUpdate.signal()
    while not g_Driver.updateTh.isDone() do
        Threading.Thread.yield()

    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice = expect Voice.create(&file)
    voice.destroy()
    voice.destroy()

    var destroyCommands = 0
    for command in g_Driver.voicesToUpdate do
        if command.command == .Destroy do
            destroyCommands += 1
    Swag.require(destroyCommands == 1)
}

// Concurrent destroy requests atomically elect one caller to enqueue cleanup.
#test
{
    var voice:   Voice
    var probe:   AudioDestroyRequestProbe = {voice: &voice}
    var threads: [8] Threading.Thread

    for &thread in threads
    {
        discard expect thread.init(&requestVoiceDestroyOnce, &probe)
        discard expect thread.start()
    }

    for iteration in 128
    {
        let round        = cast(u32, iteration + 1)
        let expectedDone = cast(u32, threads.count) * round
        while Atomic.get(&probe.ready) != expectedDone do
            Threading.Thread.yield()
        Atomic.set(&probe.start, round)
        while Atomic.get(&probe.done) != expectedDone do
            Threading.Thread.yield()
        Swag.require(Atomic.get(&probe.winners) == round)
        voice.resetState(.PendingDestroy)
    }

    for &thread in threads do
        thread.wait()

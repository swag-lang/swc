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
}

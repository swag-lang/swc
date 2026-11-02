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
        Swag.assert(allocator.childFreed and allocator.parentFreed)
        Swag.assert(not allocator.parentBeforeChild, "audio parent was released before its child")
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
    Swag.assert(g_Driver.activeVoices.isEmpty())
    destroyEngine()
    Swag.assert(allocator.voiceFreed, "shutdown leaked an unregistered native voice")
}

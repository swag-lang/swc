#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Win32

// A window that accepts a drop starts OLE, and OLE joins the thread to the apartment-threaded
// model. The engine then asks for the multi-threaded one and is refused with RPC_E_CHANGED_MODE.
// Reading that as a failure is what left every windowed program silent, so the apartment the
// thread is already in has to be accepted — while the reference count stays with whoever opened it.
#test
{
    @assert(comApartmentIsUsable(S_OK))
    @assert(comApartmentIsUsable(S_FALSE))
    @assert(comApartmentIsUsable(RPC_E_CHANGED_MODE))
    @assert(!comApartmentIsUsable(E_INVALIDARG))
    @assert(!comApartmentIsUsable(E_OUTOFMEMORY))

    @assert(comOwnsInitialization(S_OK))
    @assert(comOwnsInitialization(S_FALSE))
    @assert(!comOwnsInitialization(RPC_E_CHANGED_MODE))
}

// XAudio2 rejects a source buffer when any unused playback or loop field contains garbage.
#test
{
    let sample  = 0x7F'u8
    let context = cast(#null *void) &sample
    let buffer  = makeXAudio2Buffer(&sample, 1, context)

    @assert(buffer.flags == 0)
    @assert(buffer.audioBytes == 1)
    @assert(buffer.pAudioData == &sample)
    @assert(buffer.playBegin == 0)
    @assert(buffer.playLength == 0)
    @assert(buffer.loopBegin == 0)
    @assert(buffer.loopLength == 0)
    @assert(buffer.loopCount == 0)
    @assert(buffer.pContext == context)
}

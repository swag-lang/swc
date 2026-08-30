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
    Swag.assert(comApartmentIsUsable(S_OK))
    Swag.assert(comApartmentIsUsable(S_FALSE))
    Swag.assert(comApartmentIsUsable(RPC_E_CHANGED_MODE))
    Swag.assert(!comApartmentIsUsable(E_INVALIDARG))
    Swag.assert(!comApartmentIsUsable(E_OUTOFMEMORY))

    Swag.assert(comOwnsInitialization(S_OK))
    Swag.assert(comOwnsInitialization(S_FALSE))
    Swag.assert(!comOwnsInitialization(RPC_E_CHANGED_MODE))
}

// XAudio2 rejects a source buffer when any unused playback or loop field contains garbage.
#test
{
    let sample  = 0x7F'u8
    let context = cast(#null *void) &sample
    let buffer  = makeXAudio2Buffer(&sample, 1, context)

    Swag.assert(buffer.flags == 0)
    Swag.assert(buffer.audioBytes == 1)
    Swag.assert(buffer.pAudioData == &sample)
    Swag.assert(buffer.playBegin == 0)
    Swag.assert(buffer.playLength == 0)
    Swag.assert(buffer.loopBegin == 0)
    Swag.assert(buffer.loopLength == 0)
    Swag.assert(buffer.loopCount == 0)
    Swag.assert(buffer.pContext == context)
}

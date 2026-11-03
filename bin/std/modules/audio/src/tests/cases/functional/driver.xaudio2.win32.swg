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
    Swag.require(comApartmentIsUsable(S_OK))
    Swag.require(comApartmentIsUsable(S_FALSE))
    Swag.require(comApartmentIsUsable(RPC_E_CHANGED_MODE))
    Swag.require(not comApartmentIsUsable(E_INVALIDARG))
    Swag.require(not comApartmentIsUsable(E_OUTOFMEMORY))

    Swag.require(comOwnsInitialization(S_OK))
    Swag.require(comOwnsInitialization(S_FALSE))
    Swag.require(not comOwnsInitialization(RPC_E_CHANGED_MODE))
}

// XAudio2 rejects a source buffer when any unused playback or loop field contains garbage.
#test
{
    var sample  = 0x7F'u8
    let context = cast(*void?, &sample)
    let buffer  = makeXAudio2Buffer(&sample, 1, context)

    Swag.require(buffer.flags == 0)
    Swag.require(buffer.audioBytes == 1)
    Swag.require(buffer.pAudioData == &sample)
    Swag.require(buffer.playBegin == 0)
    Swag.require(buffer.playLength == 0)
    Swag.require(buffer.loopBegin == 0)
    Swag.require(buffer.loopLength == 0)
    Swag.require(buffer.loopCount == 0)
    Swag.require(buffer.pContext == context)
}

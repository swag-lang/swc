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

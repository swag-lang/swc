#global export
#foreignlib("ole32")
using Swag

#[Foreign("ole32")]
{
    func CoInitializeEx(pvReserved: #null *void, dwCoInit: DWORD)->HRESULT;
    func CoUninitialize();
}

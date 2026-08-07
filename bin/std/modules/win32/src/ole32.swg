#global export

#foreignlib("ole32")
using Swag

alias CLIPFORMAT = WORD

const E_NOTIMPL                    = cast #bit (HRESULT) 0x80004001
const E_NOINTERFACE                = cast #bit (HRESULT) 0x80004002
const E_POINTER                    = cast #bit (HRESULT) 0x80004003
const E_FAIL                       = cast #bit (HRESULT) 0x80004005
const E_INVALIDARG                 = cast #bit (HRESULT) 0x80070057
const E_OUTOFMEMORY                = cast #bit (HRESULT) 0x8007000E
const DV_E_FORMATETC               = cast #bit (HRESULT) 0x80040064
const DV_E_TYMED                   = cast #bit (HRESULT) 0x80040069
const DV_E_DVASPECT                = cast #bit (HRESULT) 0x8004006B
const DRAGDROP_S_DROP              = 0x00040100's32
const DRAGDROP_S_CANCEL            = 0x00040101's32
const DRAGDROP_S_USEDEFAULTCURSORS = 0x00040102's32

const COINIT_APARTMENTTHREADED = 0x2'u32
const COINIT_MULTITHREADED     = 0x0'u32
const COINIT_DISABLE_OLE1DDE   = 0x4'u32

const DROPEFFECT_NONE   = 0x00000000'u32
const DROPEFFECT_COPY   = 0x00000001'u32
const DROPEFFECT_MOVE   = 0x00000002'u32
const DROPEFFECT_LINK   = 0x00000004'u32
const DROPEFFECT_SCROLL = 0x80000000'u32

const TYMED_HGLOBAL  = 1'u32
const TYMED_FILE     = 2'u32
const TYMED_ISTREAM  = 4'u32
const TYMED_ISTORAGE = 8'u32
const TYMED_GDI      = 16'u32
const TYMED_MFPICT   = 32'u32
const TYMED_ENHMF    = 64'u32
const TYMED_NULL     = 0'u32

const DVASPECT_CONTENT   = 1'u32
const DVASPECT_THUMBNAIL = 2'u32
const DVASPECT_ICON      = 4'u32
const DVASPECT_DOCPRINT  = 8'u32

const MK_LBUTTON = 0x0001'u32
const MK_RBUTTON = 0x0002'u32
const MK_SHIFT   = 0x0004'u32
const MK_CONTROL = 0x0008'u32
const MK_MBUTTON = 0x0010'u32
const MK_ALT     = 0x0020'u32

const IID_IUnknown       = GUID{0x00000000, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IDataObject    = GUID{0x0000010E, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IDropSource    = GUID{0x00000121, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IDropTarget    = GUID{0x00000122, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IEnumFORMATETC = GUID{0x00000103, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}

struct POINTL
{
    x: LONG
    y: LONG
}

struct DVTARGETDEVICE
{
    tdSize:             DWORD
    tdDriverNameOffset: WORD
    tdDeviceNameOffset: WORD
    tdPortNameOffset:   WORD
    tdExtDevmodeOffset: WORD
    tdData:             [1] BYTE
}

struct FORMATETC
{
    cfFormat: CLIPFORMAT
    ptd:      #null *DVTARGETDEVICE
    dwAspect: DWORD
    lindex:   LONG
    tymed:    DWORD
}

// The medium union is spelled as its widest member; every handle-shaped case aliases it.
struct STGMEDIUM
{
    tymed:          DWORD
    hGlobal:        HANDLE
    pUnkForRelease: #null *void
}

#assert(#sizeof(FORMATETC) == 32)
#assert(#sizeof(STGMEDIUM) == 24)
#assert(#sizeof(POINTL) == 8)

struct IUnknown
{
    lpVtbl: *IUnknownVtbl
}

struct IUnknownVtbl
{
    QueryInterface: func(*IUnknown, const *GUID, *LPVOID)->HRESULT
    AddRef:         func(*IUnknown)->ULONG
    Release:        func(*IUnknown)->ULONG
}

struct IDataObject
{
    lpVtbl: *IDataObjectVtbl
}

struct IDataObjectVtbl
{
    QueryInterface:        func(*IDataObject, const *GUID, *LPVOID)->HRESULT
    AddRef:                func(*IDataObject)->ULONG
    Release:               func(*IDataObject)->ULONG
    GetData:               func(*IDataObject, const *FORMATETC, *STGMEDIUM)->HRESULT
    GetDataHere:           func(*IDataObject, const *FORMATETC, *STGMEDIUM)->HRESULT
    QueryGetData:          func(*IDataObject, const *FORMATETC)->HRESULT
    GetCanonicalFormatEtc: func(*IDataObject, const *FORMATETC, *FORMATETC)->HRESULT
    SetData:               func(*IDataObject, const *FORMATETC, *STGMEDIUM, BOOL)->HRESULT
    EnumFormatEtc:         func(*IDataObject, DWORD, *LPVOID)->HRESULT
    DAdvise:               func(*IDataObject, const *FORMATETC, DWORD, #null *void, *DWORD)->HRESULT
    DUnadvise:             func(*IDataObject, DWORD)->HRESULT
    EnumDAdvise:           func(*IDataObject, *LPVOID)->HRESULT
}

struct IDropTarget
{
    lpVtbl: *IDropTargetVtbl
}

struct IDropTargetVtbl
{
    QueryInterface: func(*IDropTarget, const *GUID, *LPVOID)->HRESULT
    AddRef:         func(*IDropTarget)->ULONG
    Release:        func(*IDropTarget)->ULONG
    DragEnter:      func(*IDropTarget, #null *IDataObject, DWORD, POINTL, *DWORD)->HRESULT
    DragOver:       func(*IDropTarget, DWORD, POINTL, *DWORD)->HRESULT
    DragLeave:      func(*IDropTarget)->HRESULT
    Drop:           func(*IDropTarget, #null *IDataObject, DWORD, POINTL, *DWORD)->HRESULT
}

struct IDropSource
{
    lpVtbl: *IDropSourceVtbl
}

struct IDropSourceVtbl
{
    QueryInterface:    func(*IDropSource, const *GUID, *LPVOID)->HRESULT
    AddRef:            func(*IDropSource)->ULONG
    Release:           func(*IDropSource)->ULONG
    QueryContinueDrag: func(*IDropSource, BOOL, DWORD)->HRESULT
    GiveFeedback:      func(*IDropSource, DWORD)->HRESULT
}

struct IEnumFORMATETC
{
    lpVtbl: *IEnumFORMATETCVtbl
}

struct IEnumFORMATETCVtbl
{
    QueryInterface: func(*IEnumFORMATETC, const *GUID, *LPVOID)->HRESULT
    AddRef:         func(*IEnumFORMATETC)->ULONG
    Release:        func(*IEnumFORMATETC)->ULONG
    Next:           func(*IEnumFORMATETC, ULONG, *FORMATETC, #null *ULONG)->HRESULT
    Skip:           func(*IEnumFORMATETC, ULONG)->HRESULT
    Reset:          func(*IEnumFORMATETC)->HRESULT
    Clone:          func(*IEnumFORMATETC, *LPVOID)->HRESULT
}

#[Foreign("ole32")]
{
    func CoInitializeEx(pvReserved: #null *void, dwCoInit: DWORD)->HRESULT
    func CoUninitialize()
    func CoTaskMemAlloc(cb: SIZE_T)->#null [*] void
    func CoTaskMemFree(pv: #null *void)
    func OleInitialize(pvReserved: #null *void)->HRESULT
    func OleUninitialize()
    func RegisterDragDrop(hwnd: HWND, pDropTarget: *IDropTarget)->HRESULT
    func RevokeDragDrop(hwnd: HWND)->HRESULT
    func ReleaseStgMedium(pmedium: *STGMEDIUM)
    func DoDragDrop(pDataObj: *IDataObject, pDropSource: *IDropSource, dwOKEffects: DWORD, pdwEffect: *DWORD)->HRESULT
}

// Reports whether two interface identifiers name the same interface.
func isEqualGuid(a, b: GUID)->bool
{
    let tailA = dref cast(const *u64) &a.Data4[0]
    let tailB = dref cast(const *u64) &b.Data4[0]
    return a.Data1 == b.Data1 and
           a.Data2 == b.Data2 and
           a.Data3 == b.Data3 and
           tailA == tailB
}

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
const DATA_S_SAMEFORMATETC         = 0x00040130's32
const OLE_E_ADVISENOTSUPPORTED     = cast #bit (HRESULT) 0x80040003

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

const CLSCTX_INPROC_SERVER  = 0x1'u32
const CLSCTX_INPROC_HANDLER = 0x2'u32
const CLSCTX_LOCAL_SERVER   = 0x4'u32

const STREAM_SEEK_SET = 0'u32
const STREAM_SEEK_CUR = 1'u32
const STREAM_SEEK_END = 2'u32

const STGTY_STORAGE   = 1'u32
const STGTY_STREAM    = 2'u32
const STGTY_LOCKBYTES = 3'u32
const STGTY_PROPERTY  = 4'u32

const STATFLAG_DEFAULT = 0'u32
const STATFLAG_NONAME  = 1'u32

const IID_IUnknown       = GUID{0x00000000, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IStream        = GUID{0x0000000C, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IDataObject    = GUID{0x0000010E, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IDropSource    = GUID{0x00000121, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IDropTarget    = GUID{0x00000122, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}
const IID_IEnumFORMATETC = GUID{0x00000103, 0x0000, 0x0000, [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]}

struct POINTL
{
    public
    {
        x: LONG
        y: LONG
    }
}

struct DVTARGETDEVICE
{
    public
    {
        tdSize:             DWORD
        tdDriverNameOffset: WORD
        tdDeviceNameOffset: WORD
        tdPortNameOffset:   WORD
        tdExtDevmodeOffset: WORD
        tdData:             [1] BYTE
    }
}

struct FORMATETC
{
    public
    {
        cfFormat: CLIPFORMAT
        ptd:      #null *DVTARGETDEVICE
        dwAspect: DWORD
        lindex:   LONG
        tymed:    DWORD
    }
}

// Every case of the medium union is one pointer wide; the two the drag and clipboard paths use
// are named, and any other case reads through `hGlobal`.
struct STGMEDIUM
{
    public
    {
        tymed:                DWORD
        using DUMMYUNIONNAME: union
        {
            hGlobal: HANDLE             // Memory block, for `TYMED_HGLOBAL`.
            pstm:    #null *IStream     // Stream, for `TYMED_ISTREAM`.
        }
        pUnkForRelease: #null *void
    }
}

struct STATSTG
{
    public
    {
        pwcsName:          #null LPWSTR
        type:              DWORD
        cbSize:            ULARGE_INTEGER
        mtime:             FILETIME
        ctime:             FILETIME
        atime:             FILETIME
        grfMode:           DWORD
        grfLocksSupported: DWORD
        clsid:             GUID
        grfStateBits:      DWORD
        reserved:          DWORD
    }
}

#assert(#sizeof(FORMATETC) == 32)
#assert(#sizeof(STGMEDIUM) == 24)
#assert(#sizeof(POINTL) == 8)
#assert(#sizeof(STATSTG) == 80)

struct IUnknown
{
    public lpVtbl: *IUnknownVtbl
}

struct IUnknownVtbl
{
    public
    {
        QueryInterface: func(*IUnknown, const *GUID, *LPVOID)->HRESULT
        AddRef:         func(*IUnknown)->ULONG
        Release:        func(*IUnknown)->ULONG
    }
}

struct IDataObject
{
    public lpVtbl: *IDataObjectVtbl
}

struct IDataObjectVtbl
{
    public
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
}

struct IStream
{
    public lpVtbl: *IStreamVtbl
}

// The two `ISequentialStream` methods are spelled inline, because the vtable of a derived
// interface is the base one followed by its own entries and nothing here needs the base name.
struct IStreamVtbl
{
    public
    {
        QueryInterface: func(*IStream, const *GUID, *LPVOID)->HRESULT
        AddRef:         func(*IStream)->ULONG
        Release:        func(*IStream)->ULONG
        Read:           func(*IStream, LPVOID, ULONG, #null *ULONG)->HRESULT
        Write:          func(*IStream, LPCVOID, ULONG, #null *ULONG)->HRESULT
        Seek:           func(*IStream, LARGE_INTEGER, DWORD, #null *ULARGE_INTEGER)->HRESULT
        SetSize:        func(*IStream, ULARGE_INTEGER)->HRESULT
        CopyTo:         func(*IStream, *IStream, ULARGE_INTEGER, #null *ULARGE_INTEGER, #null *ULARGE_INTEGER)->HRESULT
        Commit:         func(*IStream, DWORD)->HRESULT
        Revert:         func(*IStream)->HRESULT
        LockRegion:     func(*IStream, ULARGE_INTEGER, ULARGE_INTEGER, DWORD)->HRESULT
        UnlockRegion:   func(*IStream, ULARGE_INTEGER, ULARGE_INTEGER, DWORD)->HRESULT
        Stat:           func(*IStream, *STATSTG, DWORD)->HRESULT
        Clone:          func(*IStream, *LPVOID)->HRESULT
    }
}

struct IDropTarget
{
    public lpVtbl: *IDropTargetVtbl
}

struct IDropTargetVtbl
{
    public
    {
        QueryInterface: func(*IDropTarget, const *GUID, *LPVOID)->HRESULT
        AddRef:         func(*IDropTarget)->ULONG
        Release:        func(*IDropTarget)->ULONG
        DragEnter:      func(*IDropTarget, #null *IDataObject, DWORD, POINTL, *DWORD)->HRESULT
        DragOver:       func(*IDropTarget, DWORD, POINTL, *DWORD)->HRESULT
        DragLeave:      func(*IDropTarget)->HRESULT
        Drop:           func(*IDropTarget, #null *IDataObject, DWORD, POINTL, *DWORD)->HRESULT
    }
}

struct IDropSource
{
    public lpVtbl: *IDropSourceVtbl
}

struct IDropSourceVtbl
{
    public
    {
        QueryInterface:    func(*IDropSource, const *GUID, *LPVOID)->HRESULT
        AddRef:            func(*IDropSource)->ULONG
        Release:           func(*IDropSource)->ULONG
        QueryContinueDrag: func(*IDropSource, BOOL, DWORD)->HRESULT
        GiveFeedback:      func(*IDropSource, DWORD)->HRESULT
    }
}

struct IEnumFORMATETC
{
    public lpVtbl: *IEnumFORMATETCVtbl
}

struct IEnumFORMATETCVtbl
{
    public
    {
        QueryInterface: func(*IEnumFORMATETC, const *GUID, *LPVOID)->HRESULT
        AddRef:         func(*IEnumFORMATETC)->ULONG
        Release:        func(*IEnumFORMATETC)->ULONG
        Next:           func(*IEnumFORMATETC, ULONG, *FORMATETC, #null *ULONG)->HRESULT
        Skip:           func(*IEnumFORMATETC, ULONG)->HRESULT
        Reset:          func(*IEnumFORMATETC)->HRESULT
        Clone:          func(*IEnumFORMATETC, *LPVOID)->HRESULT
    }
}

#[Foreign("ole32")]
{
    func CoInitializeEx(pvReserved: #null *void, dwCoInit: DWORD)->HRESULT
    func CoUninitialize()
    func CoCreateInstance(rclsid: const *GUID, pUnkOuter: #null *void, dwClsContext: DWORD, riid: const *GUID, ppv: *LPVOID)->HRESULT
    func CreateStreamOnHGlobal(hGlobal: HGLOBAL, fDeleteOnRelease: BOOL, ppstm: *LPVOID)->HRESULT
    func GetHGlobalFromStream(pstm: *IStream, phglobal: *HGLOBAL)->HRESULT
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

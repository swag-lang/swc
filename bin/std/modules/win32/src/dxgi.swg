#global export

using Swag

// DXGI 1.2 declarations from dxgi.h and dxgi1_2.h.
const DXGI_FORMAT_B8G8R8A8_UNORM   = 87'u32
const DXGI_ERROR_NOT_FOUND         = cast #bit (HRESULT, 0x887A_0002)
const DXGI_ERROR_WAS_STILL_DRAWING = cast #bit (HRESULT, 0x887A_000A)
const DXGI_ERROR_ACCESS_LOST       = cast #bit (HRESULT, 0x887A_0026)
const DXGI_ERROR_WAIT_TIMEOUT      = cast #bit (HRESULT, 0x887A_0027)

const IID_IDXGIDevice  = GUID{0x54EC77FA, 0x1377, 0x44E6,
                             [0x8C, 0x32, 0x88, 0xFD, 0x5F, 0x44, 0xC8, 0x4C]}
const IID_IDXGIOutput1 = GUID{0x00CDDEA8, 0x939B, 0x4B83,
                             [0xA3, 0x40, 0xA6, 0x85, 0x22, 0x66, 0x66, 0xCC]}

struct DXGI_OUTPUT_DESC
{
    public
    {
        DeviceName:         [32] WCHAR
        DesktopCoordinates: RECT
        AttachedToDesktop:  BOOL
        Rotation:           u32
        Monitor:            HANDLE
    }
}

struct DXGI_OUTDUPL_POINTER_POSITION
{
    public
    {
        Position: POINT
        Visible:  BOOL
    }
}

struct DXGI_OUTDUPL_FRAME_INFO
{
    public
    {
        LastPresentTime:           LARGE_INTEGER
        LastMouseUpdateTime:       LARGE_INTEGER
        AccumulatedFrames:         u32
        RectsCoalesced:            BOOL
        ProtectedContentMaskedOut: BOOL
        PointerPosition:          DXGI_OUTDUPL_POINTER_POSITION
        TotalMetadataBufferSize:  u32
        PointerShapeBufferSize:   u32
    }
}

struct DXGI_OUTDUPL_MOVE_RECT
{
    public
    {
        SourcePoint:     POINT
        DestinationRect: RECT
    }
}

struct IDXGIDevice { public lpVtbl: *IDXGIDeviceVtbl }
struct IDXGIAdapter { public lpVtbl: *IDXGIAdapterVtbl }
struct IDXGIOutput { public lpVtbl: *IDXGIOutputVtbl }
struct IDXGIOutput1 { public lpVtbl: *IDXGIOutput1Vtbl }
struct IDXGIOutputDuplication { public lpVtbl: *IDXGIOutputDuplicationVtbl }
struct IDXGIResource { public lpVtbl: *IUnknownVtbl }

#[Swag.CallingConvention(.C)]
struct IDXGIDeviceVtbl
{
    public
    {
        inherited:  [7] *void
        GetAdapter: func(*IDXGIDevice, **IDXGIAdapter?)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IDXGIAdapterVtbl
{
    public
    {
        inherited:   [7] *void
        EnumOutputs: func(*IDXGIAdapter, u32, **IDXGIOutput?)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IDXGIOutputVtbl
{
    public
    {
        inherited: [7] *void
        GetDesc:   func(*IDXGIOutput, *DXGI_OUTPUT_DESC)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IDXGIOutput1Vtbl
{
    public
    {
        inherited:       [22] *void
        DuplicateOutput: func(*IDXGIOutput1, *IUnknown, **IDXGIOutputDuplication?)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IDXGIOutputDuplicationVtbl
{
    public
    {
        inherited:        [8] *void
        AcquireNextFrame: func(*IDXGIOutputDuplication, u32, *DXGI_OUTDUPL_FRAME_INFO,
                               **IDXGIResource?)->HRESULT
        GetFrameDirtyRects: func(*IDXGIOutputDuplication, u32, *RECT, *u32)->HRESULT
        GetFrameMoveRects:  func(*IDXGIOutputDuplication, u32, *DXGI_OUTDUPL_MOVE_RECT,
                                 *u32)->HRESULT
        other:            [3] *void
        ReleaseFrame:     func(*IDXGIOutputDuplication)->HRESULT
    }
}

#assert(#sizeof(DXGI_OUTPUT_DESC) == 96)
#assert(#sizeof(DXGI_OUTDUPL_FRAME_INFO) == 48)
#assert(#sizeof(DXGI_OUTDUPL_MOVE_RECT) == 24)
#assert(#offsetof(IDXGIDeviceVtbl.GetAdapter) == 7 * #sizeof(*void))
#assert(#offsetof(IDXGIAdapterVtbl.EnumOutputs) == 7 * #sizeof(*void))
#assert(#offsetof(IDXGIOutput1Vtbl.DuplicateOutput) == 22 * #sizeof(*void))
#assert(#offsetof(IDXGIOutputDuplicationVtbl.AcquireNextFrame) == 8 * #sizeof(*void))
#assert(#offsetof(IDXGIOutputDuplicationVtbl.GetFrameDirtyRects) == 9 * #sizeof(*void))
#assert(#offsetof(IDXGIOutputDuplicationVtbl.GetFrameMoveRects) == 10 * #sizeof(*void))

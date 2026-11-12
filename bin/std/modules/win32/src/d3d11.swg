#global export
#foreignlib("d3d11")

using Swag

// Direct3D 11 declarations from d3d11.h. Vtable gaps retain the SDK method offsets.
const D3D_DRIVER_TYPE_HARDWARE          = 1'u32
const D3D11_CREATE_DEVICE_BGRA_SUPPORT = 0x20'u32
const D3D11_SDK_VERSION                = 7'u32
const D3D11_USAGE_STAGING              = 3'u32
const D3D11_CPU_ACCESS_READ            = 0x20000'u32
const D3D11_MAP_READ                   = 1'u32
const D3D11_MAP_FLAG_DO_NOT_WAIT      = 0x100000'u32

struct DXGI_SAMPLE_DESC
{
    public
    {
        Count:   u32
        Quality: u32
    }
}

struct D3D11_TEXTURE2D_DESC
{
    public
    {
        Width:          u32
        Height:         u32
        MipLevels:      u32
        ArraySize:      u32
        Format:         u32
        SampleDesc:     DXGI_SAMPLE_DESC
        Usage:          u32
        BindFlags:      u32
        CPUAccessFlags: u32
        MiscFlags:      u32
    }
}

struct D3D11_MAPPED_SUBRESOURCE
{
    public
    {
        pData:      *void?
        RowPitch:   u32
        DepthPitch: u32
    }
}

struct D3D11_BOX
{
    public
    {
        left:   u32
        top:    u32
        front:  u32
        right:  u32
        bottom: u32
        back:   u32
    }
}

struct ID3D11Device { public lpVtbl: *ID3D11DeviceVtbl }
struct ID3D11DeviceContext { public lpVtbl: *ID3D11DeviceContextVtbl }
struct ID3D11Resource { public lpVtbl: *IUnknownVtbl }
struct ID3D11Texture2D { public lpVtbl: *IUnknownVtbl }

const IID_ID3D11Texture2D = GUID{0x6F15AAF2, 0xD208, 0x4E89,
                                [0x9A, 0xB4, 0x48, 0x95, 0x35, 0xD3, 0x4F, 0x9C]}

#[Swag.CallingConvention(.C)]
struct ID3D11DeviceVtbl
{
    public
    {
        inherited:      [5] *void
        CreateTexture2D: func(*ID3D11Device, const *D3D11_TEXTURE2D_DESC,
                              const *void?, **ID3D11Texture2D?)->HRESULT
        beforeContext:  [34] *void
        GetImmediateContext: func(*ID3D11Device, **ID3D11DeviceContext?)
    }
}

#[Swag.CallingConvention(.C)]
struct ID3D11DeviceContextVtbl
{
    public
    {
        beforeMap:             [14] *void
        Map:                   func(*ID3D11DeviceContext, *ID3D11Resource, u32, u32, u32,
                                    *D3D11_MAPPED_SUBRESOURCE)->HRESULT
        Unmap:                 func(*ID3D11DeviceContext, *ID3D11Resource, u32)
        beforeCopy:            [30] *void
        CopySubresourceRegion: func(*ID3D11DeviceContext, *ID3D11Resource, u32, u32, u32, u32,
                                    *ID3D11Resource, u32, const *D3D11_BOX?)
        CopyResource:          func(*ID3D11DeviceContext, *ID3D11Resource, *ID3D11Resource)
        beforeFlush:           [63] *void
        Flush:                 func(*ID3D11DeviceContext)
    }
}

#assert(#sizeof(D3D11_TEXTURE2D_DESC) == 44)
#assert(#sizeof(D3D11_MAPPED_SUBRESOURCE) == 16)
#assert(#offsetof(ID3D11DeviceVtbl.CreateTexture2D) == 5 * #sizeof(*void))
#assert(#offsetof(ID3D11DeviceVtbl.GetImmediateContext) == 40 * #sizeof(*void))
#assert(#offsetof(ID3D11DeviceContextVtbl.Map) == 14 * #sizeof(*void))
#assert(#offsetof(ID3D11DeviceContextVtbl.CopySubresourceRegion) == 46 * #sizeof(*void))
#assert(#offsetof(ID3D11DeviceContextVtbl.Flush) == 111 * #sizeof(*void))

#[Foreign("d3d11", callconv: Swag.CallConv.C)]
{
    func D3D11CreateDevice(pAdapter: *void?, DriverType: u32, Software: HMODULE, Flags: u32,
                           pFeatureLevels: const *u32?, FeatureLevels: u32, SDKVersion: u32,
                           ppDevice: **ID3D11Device?, pFeatureLevel: *u32?,
                           ppImmediateContext: **ID3D11DeviceContext?)->HRESULT
}

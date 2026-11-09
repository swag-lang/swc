#global export

using Swag

// Core Audio capture COM interfaces, following mmdeviceapi.h and audioclient.h in the Windows SDK.
// All vtables use the system COM calling convention (the x64 C ABI on supported Windows builds).

const CLSID_MMDeviceEnumerator = GUID{0xBCDE0395, 0xE52F, 0x467C,
                                      [0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E]}
const IID_IMMDeviceEnumerator = GUID{0xA95664D2, 0x9614, 0x4F35,
                                     [0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6]}
const IID_IMMDevice = GUID{0xD666063F, 0x1587, 0x4E43,
                           [0x81, 0xF1, 0xB9, 0x48, 0xE8, 0x07, 0x36, 0x3F]}
const IID_IMMDeviceCollection = GUID{0x0BD7A1BE, 0x7A1A, 0x44DB,
                                     [0x83, 0x97, 0xCC, 0x53, 0x92, 0x38, 0x7B, 0x5E]}
const IID_IAudioClient = GUID{0x1CB9AD4C, 0xDBFA, 0x4C32,
                              [0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2]}
const IID_IAudioCaptureClient = GUID{0xC8ADBD64, 0xE71E, 0x48A0,
                                     [0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17]}

const EDATAFLOW_RENDER  = 0's32
const EDATAFLOW_CAPTURE = 1's32
const EROLE_CONSOLE     = 0's32
const EROLE_MULTIMEDIA  = 1's32
const EROLE_COMMUNICATIONS = 2's32
const DEVICE_STATE_ACTIVE = 1'u32

const AUDCLNT_SHAREMODE_SHARED = 0's32
const AUDCLNT_STREAMFLAGS_EVENTCALLBACK = 0x0004_0000'u32
const AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY = 1'u32
const AUDCLNT_BUFFERFLAGS_SILENT             = 2'u32
const AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR    = 4'u32
const AUDCLNT_E_DEVICE_INVALIDATED = cast #bit (HRESULT, 0x8889_0004)
const AUDCLNT_E_SERVICE_NOT_RUNNING = cast #bit (HRESULT, 0x8889_0010)
const AUDCLNT_E_RESOURCES_INVALIDATED = cast #bit (HRESULT, 0x8889_0026)
const AUDCLNT_S_BUFFER_EMPTY = 0x0889_0001's32

const WAVE_FORMAT_PCM = 1'u16
const WAVE_FORMAT_IEEE_FLOAT = 3'u16
const WAVE_FORMAT_EXTENSIBLE = 0xFFFE'u16

#[Swag.Pack(1)]
struct WAVEFORMATEX
{
    public
    {
        wFormatTag:      WORD
        nChannels:       WORD
        nSamplesPerSec:  DWORD
        nAvgBytesPerSec: DWORD
        nBlockAlign:     WORD
        wBitsPerSample:  WORD
        cbSize:          WORD
    }
}

#assert(#sizeof(WAVEFORMATEX) == 18)
#assert(#offsetof(WAVEFORMATEX.nSamplesPerSec) == 4)
#assert(#offsetof(WAVEFORMATEX.cbSize) == 16)

struct IMMDeviceCollection { public lpVtbl: *IMMDeviceCollectionVtbl }
struct IMMDeviceEnumerator { public lpVtbl: *IMMDeviceEnumeratorVtbl }
struct IMMDevice { public lpVtbl: *IMMDeviceVtbl }
struct IAudioClient { public lpVtbl: *IAudioClientVtbl }
struct IAudioCaptureClient { public lpVtbl: *IAudioCaptureClientVtbl }

#[Swag.CallingConvention(.C)]
struct IMMDeviceCollectionVtbl
{
    public
    {
        QueryInterface: func(*IMMDeviceCollection, const *GUID, *LPVOID)->HRESULT
        AddRef:         func(*IMMDeviceCollection)->ULONG
        Release:        func(*IMMDeviceCollection)->ULONG
        GetCount:       func(*IMMDeviceCollection, *UINT)->HRESULT
        Item:           func(*IMMDeviceCollection, UINT, **IMMDevice?)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IMMDeviceEnumeratorVtbl
{
    public
    {
        QueryInterface:                         func(*IMMDeviceEnumerator, const *GUID, *LPVOID)->HRESULT
        AddRef:                                 func(*IMMDeviceEnumerator)->ULONG
        Release:                                func(*IMMDeviceEnumerator)->ULONG
        EnumAudioEndpoints:                     func(*IMMDeviceEnumerator, s32, DWORD, **IMMDeviceCollection?)->HRESULT
        GetDefaultAudioEndpoint:                func(*IMMDeviceEnumerator, s32, s32, **IMMDevice?)->HRESULT
        GetDevice:                              func(*IMMDeviceEnumerator, LPCWSTR, **IMMDevice?)->HRESULT
        RegisterEndpointNotificationCallback:   func(*IMMDeviceEnumerator, *void)->HRESULT
        UnregisterEndpointNotificationCallback: func(*IMMDeviceEnumerator, *void)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IMMDeviceVtbl
{
    public
    {
        QueryInterface:    func(*IMMDevice, const *GUID, *LPVOID)->HRESULT
        AddRef:            func(*IMMDevice)->ULONG
        Release:           func(*IMMDevice)->ULONG
        Activate:          func(*IMMDevice, const *GUID, DWORD, *void?, *LPVOID)->HRESULT
        OpenPropertyStore: func(*IMMDevice, DWORD, *LPVOID)->HRESULT
        GetId:             func(*IMMDevice, *LPWSTR)->HRESULT
        GetState:          func(*IMMDevice, *DWORD)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IAudioClientVtbl
{
    public
    {
        QueryInterface:    func(*IAudioClient, const *GUID, *LPVOID)->HRESULT
        AddRef:            func(*IAudioClient)->ULONG
        Release:           func(*IAudioClient)->ULONG
        Initialize:        func(*IAudioClient, s32, DWORD, s64, s64, const *WAVEFORMATEX, const *GUID?)->HRESULT
        GetBufferSize:     func(*IAudioClient, *UINT)->HRESULT
        GetStreamLatency:  func(*IAudioClient, *s64)->HRESULT
        GetCurrentPadding: func(*IAudioClient, *UINT)->HRESULT
        IsFormatSupported: func(*IAudioClient, s32, const *WAVEFORMATEX, *LPVOID)->HRESULT
        GetMixFormat:      func(*IAudioClient, *LPVOID)->HRESULT
        GetDevicePeriod:   func(*IAudioClient, *s64, *s64)->HRESULT
        Start:             func(*IAudioClient)->HRESULT
        Stop:              func(*IAudioClient)->HRESULT
        Reset:             func(*IAudioClient)->HRESULT
        SetEventHandle:    func(*IAudioClient, HANDLE)->HRESULT
        GetService:        func(*IAudioClient, const *GUID, *LPVOID)->HRESULT
    }
}

#[Swag.CallingConvention(.C)]
struct IAudioCaptureClientVtbl
{
    public
    {
        QueryInterface:    func(*IAudioCaptureClient, const *GUID, *LPVOID)->HRESULT
        AddRef:            func(*IAudioCaptureClient)->ULONG
        Release:           func(*IAudioCaptureClient)->ULONG
        GetBuffer:         func(*IAudioCaptureClient, *LPVOID, *UINT, *DWORD, *u64, *u64)->HRESULT
        ReleaseBuffer:     func(*IAudioCaptureClient, UINT)->HRESULT
        GetNextPacketSize: func(*IAudioCaptureClient, *UINT)->HRESULT
    }
}

#assert(#sizeof(IMMDevice) == #sizeof(*void))
#assert(#sizeof(IAudioClient) == #sizeof(*void))
#assert(#sizeof(IAudioCaptureClient) == #sizeof(*void))
#assert(#sizeof(IMMDeviceCollectionVtbl) == 5 * #sizeof(*void))
#assert(#sizeof(IMMDeviceEnumeratorVtbl) == 8 * #sizeof(*void))
#assert(#sizeof(IMMDeviceVtbl) == 7 * #sizeof(*void))
#assert(#sizeof(IAudioClientVtbl) == 15 * #sizeof(*void))
#assert(#sizeof(IAudioCaptureClientVtbl) == 6 * #sizeof(*void))
#assert(#offsetof(IMMDeviceEnumeratorVtbl.GetDefaultAudioEndpoint) == 4 * #sizeof(*void))
#assert(#offsetof(IMMDeviceVtbl.Activate) == 3 * #sizeof(*void))
#assert(#offsetof(IAudioClientVtbl.GetService) == 14 * #sizeof(*void))
#assert(#offsetof(IAudioCaptureClientVtbl.GetBuffer) == 3 * #sizeof(*void))

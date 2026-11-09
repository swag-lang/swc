#global export

using Swag

// The two shared-mode microphone formats the audio capture adapter can copy to PCM16.
enum WasapiCaptureSampleFormat
{
    Pcm16   // Interleaved signed 16-bit integer samples.
    Float32 // Interleaved IEEE 32-bit floating-point samples.
}

// Describes the default input endpoint's shared-mode mix format.
struct WasapiCaptureFormat
{
    public sampleRate: u32                      // Frames per second.
    public channels: u16                       // One or two interleaved channels.
    public sampleFormat: WasapiCaptureSampleFormat // Encoding of each sample.
}

// Borrows one WASAPI capture packet until [[Win32.WasapiCapture.releasePacket]].
struct WasapiCapturePacket
{
    public data: LPVOID       // Borrowed source bytes, possibly null for a silent packet.
    public frames: u32        // Number of frames that must be released.
    public flags: u32         // AUDCLNT_BUFFERFLAGS_* values.
    public devicePosition: u64 // First frame on the device sample clock.
    public timestamp100ns: u64 // First frame on the monotonic QPC clock, in 100 ns units.
}

// Owns a default capture endpoint, shared-mode audio client, and event on one COM thread.
//
// The caller must call `close` on the same thread that opened the device. This low-level wrapper
// returns borrowed source buffers; release each one before requesting another. The packet QPC
// timestamp is expressed by WASAPI in 100-nanosecond units. A device removal returns its native
// HRESULT; a higher-level recorder can mark a gap and reopen the default endpoint.
#[Swag.NoCopy]
struct WasapiCapture
{
    private
    {
        enumerator:    *IMMDeviceEnumerator?
        device:        *IMMDevice?
        client:        *IAudioClient?
        capture:       *IAudioCaptureClient?
        event:         HANDLE
        format:        WasapiCaptureFormat
        ownerThread:   DWORD
        pendingFrames: u32
        ownsApartment: bool
        started:       bool
    }
}

impl WasapiCapture
{
    // Opens and starts the current default microphone in shared, event-driven mode.
    //
    // Accepts mono or stereo PCM16 and float32 mix formats at 44.1 or 48 kHz. The format is
    // rejected explicitly if it cannot feed the software AAC recording path without a converter.
    func openDefault()->WasapiCapture fail
    {
        var result: #returntype
        defer #fail result.close()
        result.ownerThread = GetCurrentThreadId()
        let apartment = CoInitializeEx(null, COINIT_MULTITHREADED)
        if apartment != S_OK and apartment != S_FALSE and apartment != RPC_E_CHANGED_MODE do
            fail SystemError{"cannot initialize microphone COM apartment", errorID: cast(u64, cast #bit (u32, apartment))}
        result.ownsApartment = apartment == S_OK or apartment == S_FALSE

        let clsid = CLSID_MMDeviceEnumerator
        let enumeratorId = IID_IMMDeviceEnumerator
        var raw: LPVOID
        var hr = CoCreateInstance(&clsid, null, CLSCTX_INPROC_SERVER, &enumeratorId, &raw)
        if hr != S_OK do
            fail SystemError{"cannot create microphone device enumerator", errorID: cast(u64, cast #bit (u32, hr))}
        result.enumerator = cast(*IMMDeviceEnumerator, unwrap raw)
        let enumerator = result.enumerator
        hr = enumerator.lpVtbl.GetDefaultAudioEndpoint(enumerator, EDATAFLOW_CAPTURE,
                                                       EROLE_MULTIMEDIA, &result.device)
        if hr != S_OK do
            fail SystemError{"cannot find a default microphone", errorID: cast(u64, cast #bit (u32, hr))}
        let device = unwrap result.device
        let clientId = IID_IAudioClient
        raw = null
        hr = device.lpVtbl.Activate(device, &clientId, CLSCTX_INPROC_SERVER, null, &raw)
        if hr != S_OK do
            fail SystemError{"cannot activate microphone audio client", errorID: cast(u64, cast #bit (u32, hr))}
        result.client = cast(*IAudioClient, unwrap raw)
        let client = result.client
        raw = null
        hr = client.lpVtbl.GetMixFormat(client, &raw)
        if hr != S_OK do
            fail SystemError{"cannot read microphone mix format", errorID: cast(u64, cast #bit (u32, hr))}
        let mixRaw = raw
        defer CoTaskMemFree(mixRaw)
        let mix = cast(*WAVEFORMATEX, unwrap mixRaw)
        result.format = try classifyWasapiCaptureFormat(mix)
        result.event = try CreateEventW(null, 0, 0, null)
        hr = client.lpVtbl.Initialize(client, AUDCLNT_SHAREMODE_SHARED,
                                      AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 0, 0, mix, null)
        if hr != S_OK do
            fail SystemError{"cannot initialize microphone shared stream", errorID: cast(u64, cast #bit (u32, hr))}
        hr = client.lpVtbl.SetEventHandle(client, result.event)
        if hr != S_OK do
            fail SystemError{"cannot attach microphone event", errorID: cast(u64, cast #bit (u32, hr))}
        let captureId = IID_IAudioCaptureClient
        raw = null
        hr = client.lpVtbl.GetService(client, &captureId, &raw)
        if hr != S_OK do
            fail SystemError{"cannot obtain microphone capture service", errorID: cast(u64, cast #bit (u32, hr))}
        result.capture = cast(*IAudioCaptureClient, unwrap raw)
        hr = client.lpVtbl.Start(client)
        if hr != S_OK do
            fail SystemError{"cannot start microphone", errorID: cast(u64, cast #bit (u32, hr))}
        result.started = true
        return result
    }

    // Returns the endpoint's validated sample rate, channel count, and source encoding.
    mtd const mixFormat()->WasapiCaptureFormat => .format

    // Waits up to `timeoutMs` for a capture event; zero only checks the current packet queue.
    mtd wait(timeoutMs: u32)->bool fail
    {
        if GetCurrentThreadId() != .ownerThread do
            fail SystemError{"microphone must be pumped on its opening COM thread"}
        if not timeoutMs do
            return true
        return try WaitForSingleObject(.event, timeoutMs) == WAIT_OBJECT_0
    }

    // Borrows the next available captured packet, if one exists.
    //
    // `data` may be null when `AUDCLNT_BUFFERFLAGS_SILENT` is set. The caller must call
    // `releasePacket` even for that packet. The stream is not safe to pump concurrently.
    mtd nextPacket(packet: *WasapiCapturePacket)->bool fail
    {
        if GetCurrentThreadId() != .ownerThread or .pendingFrames do
            fail SystemError{"release the previous microphone packet on its COM thread"}
        let capture = unwrap .capture
        var available: UINT
        var hr = capture.lpVtbl.GetNextPacketSize(capture, &available)
        if hr != S_OK do
            fail SystemError{"cannot inspect microphone packet", errorID: cast(u64, cast #bit (u32, hr))}
        if not available do
            return false
        var frames: UINT
        var flags: DWORD
        var devicePosition: u64
        var timestamp: u64
        var data: LPVOID
        hr = capture.lpVtbl.GetBuffer(capture, &data, &frames, &flags, &devicePosition, &timestamp)
        if hr != S_OK do
            fail SystemError{"cannot read microphone packet", errorID: cast(u64, cast #bit (u32, hr))}
        if not frames
        {
            discard capture.lpVtbl.ReleaseBuffer(capture, 0)
            return false
        }
        .pendingFrames = frames
        packet[] = WasapiCapturePacket{data, frames, flags, devicePosition, timestamp}
        return true
    }

    // Releases the borrowed capture packet, including a silent or discontinuous one.
    mtd releasePacket() fail
    {
        if GetCurrentThreadId() != .ownerThread or not .pendingFrames do
            fail SystemError{"no microphone packet is borrowed on this COM thread"}
        let capture = unwrap .capture
        let hr = capture.lpVtbl.ReleaseBuffer(capture, .pendingFrames)
        if hr != S_OK do
            fail SystemError{"cannot release microphone packet", errorID: cast(u64, cast #bit (u32, hr))}
        .pendingFrames = 0
    }

    // Stops and releases the endpoint, its event and this wrapper's COM apartment reference.
    mtd close()
    {
        if .capture and .pendingFrames
        {
            let capture = .capture
            discard capture.lpVtbl.ReleaseBuffer(capture, .pendingFrames)
            .pendingFrames = 0
        }
        if .client and .started
        {
            let client = .client
            discard client.lpVtbl.Stop(client)
            .started = false
        }
        if .capture
        {
            let capture = .capture
            discard capture.lpVtbl.Release(capture)
            .capture = null
        }
        if .client
        {
            let client = .client
            discard client.lpVtbl.Release(client)
            .client = null
        }
        if .device
        {
            let device = .device
            discard device.lpVtbl.Release(device)
            .device = null
        }
        if .enumerator
        {
            let enumerator = .enumerator
            discard enumerator.lpVtbl.Release(enumerator)
            .enumerator = null
        }
        if .event
        {
            CloseHandle(.event)
            .event = null
        }
        if .ownsApartment
        {
            CoUninitialize()
            .ownsApartment = false
        }
    }
}

// Converts a QPC counter to WASAPI's shared 100-nanosecond timestamp unit.
func wasapiCaptureNow100ns()->u64 fail
{
    var counter: LARGE_INTEGER
    var frequency: LARGE_INTEGER
    QueryPerformanceCounter(&counter)
    QueryPerformanceFrequency(&frequency)
    if counter < 0 or frequency <= 0 do
        fail SystemError{"cannot read the microphone monotonic clock"}
    let whole = cast(u64, counter) / cast(u64, frequency)
    let fraction = cast(u64, counter) % cast(u64, frequency)
    let fractionalTicks = cast(u64, cast(f64, fraction) * 10_000_000.0 / frequency)
    if whole > (Swag.U64.Max - fractionalTicks) / 10_000_000 do
        fail SystemError{"microphone timestamp overflows 100-nanosecond units"}
    return whole * 10_000_000 + fractionalTicks
}

private func classifyWasapiCaptureFormat(mix: *WAVEFORMATEX)->WasapiCaptureFormat fail
{
    if mix.nChannels < 1 or mix.nChannels > 2 or
       (mix.nSamplesPerSec != 44_100 and mix.nSamplesPerSec != 48_000) do
        fail SystemError{"microphone mix must be mono or stereo at 44.1 or 48 kHz"}
    if mix.nBlockAlign != mix.nChannels * mix.wBitsPerSample / 8 do
        fail SystemError{"invalid microphone mix frame alignment"}
    if mix.wFormatTag == WAVE_FORMAT_PCM and mix.wBitsPerSample == 16 do
        return WasapiCaptureFormat{mix.nSamplesPerSec, mix.nChannels, .Pcm16}
    if mix.wFormatTag == WAVE_FORMAT_IEEE_FLOAT and mix.wBitsPerSample == 32 do
        return WasapiCaptureFormat{mix.nSamplesPerSec, mix.nChannels, .Float32}
    if mix.wFormatTag == WAVE_FORMAT_EXTENSIBLE and mix.cbSize >= 22
    {
        let extended = cast(*WAVEFORMATEXTENSIBLE, cast(*void, mix))
        let isStandardSubtype = extended.SubFormat.Data2 == 0 and extended.SubFormat.Data3 == 0x0010 and
                                extended.SubFormat.Data4[0] == 0x80 and extended.SubFormat.Data4[1] == 0 and
                                extended.SubFormat.Data4[2] == 0 and extended.SubFormat.Data4[3] == 0xAA and
                                extended.SubFormat.Data4[4] == 0 and extended.SubFormat.Data4[5] == 0x38 and
                                extended.SubFormat.Data4[6] == 0x9B and extended.SubFormat.Data4[7] == 0x71
        if not isStandardSubtype do
            fail SystemError{"unsupported microphone extensible sample subtype"}
        if extended.SubFormat.Data1 == 1 and mix.wBitsPerSample == 16 and
           extended.wValidBitsPerSample == 16 do
            return WasapiCaptureFormat{mix.nSamplesPerSec, mix.nChannels, .Pcm16}
        if extended.SubFormat.Data1 == 3 and mix.wBitsPerSample == 32 and
           extended.wValidBitsPerSample == 32 do
            return WasapiCaptureFormat{mix.nSamplesPerSec, mix.nChannels, .Float32}
        fail SystemError{"unsupported microphone extensible sample precision"}
    }
    fail SystemError{"unsupported microphone mix format"}
}

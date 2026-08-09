#global if #os == Swag.TargetOs.Windows

using Swag, Core, Core.Errors, Win32, XAudio2

func hresultErrorId(result: HRESULT)->u64 => cast(u64) cast #bit (u32) result

struct XAudio2DriverNative
{
    xAudio2:        #null *IXAudio2
    masteringVoice: #null *IXAudio2MasteringVoice
    hasInitCOM:     bool
    speakerMask:    u32
    x3DInstance:    X3DAUDIO_HANDLE
}

impl XAudio2DriverNative
{
    // Create the xaudio2 engine
    mtd createXAudio2(initCOM: bool = true) fail
    {
        Debug.assert(!.xAudio2)

        var result: HRESULT
        defer #fail .destroyXAudio2()

        if initCOM
        {
            result = CoInitializeEx(null, 0)

            // COM returns S_FALSE when the apartment was already initialized; it is still a
            // successful initialization and still requires CoUninitialize.
            if result != S_OK and result != S_FALSE do
                fail SystemError{"failed to initialize COM", errorID: hresultErrorId(result)}
            .hasInitCOM = true
        }

        result = XAudio2Create(&.xAudio2, 0)
        if result != S_OK do
            fail SystemError{"cannot create xaudio2 device", errorID: hresultErrorId(result)}
        let safeXAudio2 = .xAudio2!

        let createMasteringVoice = safeXAudio2.vtbl.createMasteringVoice
        result = createMasteringVoice(safeXAudio2, &.masteringVoice)
        if result != S_OK do
            fail SystemError{"cannot create xaudio2 mastering voice", errorID: hresultErrorId(result)}
        let safeMasteringVoice = .masteringVoice!

        var debug: XAUDIO2_DEBUG_CONFIGURATION
        debug.traceMask = XAUDIO2_LOG_ERRORS | XAUDIO2_LOG_WARNINGS

        // debug.breakMask = XAUDIO2_LOG_ERRORS | XAUDIO2_LOG_WARNINGS
        let setDebugConfiguration = safeXAudio2.vtbl.setDebugConfiguration
        setDebugConfiguration(safeXAudio2, &debug, null)

        let getChannelMask = safeMasteringVoice.vtbl.getChannelMask
        result = getChannelMask(safeMasteringVoice, &.speakerMask)
        if result != S_OK do
            fail SystemError{"cannot get xaudio2 channel mask", errorID: hresultErrorId(result)}

        X3DAudioInitialize(.speakerMask, X3DAUDIO_SPEED_OF_SOUND, .x3DInstance)

        // Context for xaudio2 threads
        let cxt = @getcontext()
        g_ThreadCxt = dref cxt
    }

    // Destroys the xaudio2 engine
    // Synchronously stops the xaudio2 processing thread: after this returns, no
    // mixer pass runs and no voice callback can fire.
    mtd stopEngineXAudio2()
    {
        if .xAudio2
        {
            let stopEngine  = .xAudio2.vtbl.stopEngine
            let safeXAudio2 = .xAudio2
            stopEngine(safeXAudio2)
        }
    }

    mtd destroyXAudio2()
    {
        if .masteringVoice
        {
            let safeMasteringVoice = .masteringVoice
            let destroyVoice       = safeMasteringVoice.vtbl.destroyVoice
            destroyVoice(cast(*IXAudio2Voice) safeMasteringVoice)
            .masteringVoice = null
        }

        if .xAudio2
        {
            let safeXAudio2 = .xAudio2
            let release     = safeXAudio2.vtbl.release
            discard release(safeXAudio2)
            .xAudio2 = null
        }

        if .hasInitCOM
        {
            CoUninitialize()
            .hasInitCOM = false
        }
    }
}

impl XAudio2DriverNative
{
    mtd setOutputVolumeXAudio2(volume: f32) fail
    {
        if !.masteringVoice do
            return
        let safeMasteringVoice = .masteringVoice
        let setVolume          = safeMasteringVoice.vtbl.setVolume
        let hr                 = setVolume(cast(*IXAudio2Voice) safeMasteringVoice, volume, 0)
        if hr != S_OK do
            fail SystemError{"setOutputVolume", errorID: hresultErrorId(hr)}
    }

    mtd outputVolumeXAudio2()->f32
    {
        if !.masteringVoice do
            return 0
        var volume: f32
        let safeMasteringVoice = .masteringVoice
        let getVolume          = safeMasteringVoice.vtbl.getVolume
        getVolume(cast(*IXAudio2Voice) safeMasteringVoice, &volume)
        return volume
    }
}

///////////////////////////////////////////////////////////////
// XAUDIO2 CALLBACKS
///////////////////////////////////////////////////////////////

internal
{
    var g_ThreadCxt: Swag.Context
    var g_Cb:        IXAudio2VoiceCallback    = undefined
    var g_Cbi:       IXAudio2VoiceCallbackItf = undefined

    func onVoiceProcessingPassStart(_me: *IXAudio2VoiceCallback, _bytesRequired: UINT32) {}
    func onVoiceProcessingPassEnd(_me: *IXAudio2VoiceCallback) {}
    func onStreamEnd(_me: *IXAudio2VoiceCallback) {}
    func onBufferStart(_me: *IXAudio2VoiceCallback, _pBufferContext: #null *void) {}
    func onLoopEnd(_me: *IXAudio2VoiceCallback, _pBufferContext: #null *void) {}
    func onVoiceError(_me: *IXAudio2VoiceCallback, _pBufferContext: #null *void, _error: HRESULT) {}

    func onBufferEnd(_me: *IXAudio2VoiceCallback, pBufferContext: #null *void)
    {
        let voice = cast(#null *Voice) pBufferContext
        if !voice do
            return
        let safeVoice = voice
        if safeVoice.hasState(.PendingDestroy) do
            return

        // Called by an xaudio2-owned thread, so we must run under a valid Swag
        // context. Testing the context pointer alone is not enough: in native
        // builds @getcontext() never returns null (a fresh foreign thread lazily
        // gets a default context), so check the allocator to detect a context the
        // application never configured.
        let cxt = @getcontext()
        if cxt == null or @dataof(cxt.allocator) == null do
            @setcontext(&g_ThreadCxt)

        g_Driver.updateVoice(safeVoice, .UpdateBuffers)
    }
}

#init
{
    g_Cb.vtbl                        = &g_Cbi
    g_Cbi.onVoiceProcessingPassStart = &onVoiceProcessingPassStart
    g_Cbi.onVoiceProcessingPassEnd   = &onVoiceProcessingPassEnd
    g_Cbi.onStreamEnd                = &onStreamEnd
    g_Cbi.onBufferStart              = &onBufferStart
    g_Cbi.onBufferEnd                = &onBufferEnd
    g_Cbi.onLoopEnd                  = &onLoopEnd
    g_Cbi.onVoiceError               = &onVoiceError
}

///////////////////////////////////////////////////////////////
// VOICE
///////////////////////////////////////////////////////////////

impl Voice
{
    func createXAudio2(voice: *Voice, createFlags = VoiceCreateFlags.Default) fail
    {
        Debug.assert(g_Driver.xAudio2.xAudio2 != null, "driver should be created first")

        let file = voice.file!

        var wfx: WAVEFORMATEXTENSIBLE
        wfx.format.nChannels      = cast(u16) file.channelCount
        wfx.format.nSamplesPerSec = file.sampleRate
        wfx.format.wBitsPerSample = cast(u16) file.bitsPerSample
        wfx.format.wFormatTag     = FORMAT_EXTENSIBLE
        wfx.format.cbSize         = #sizeof(WAVEFORMATEXTENSIBLE) - #sizeof(WAVEFORMATEX)
        wfx.dwChannelMask         = file.waveSpeakerMask

        switch file.encoding
        {
        case .Pcm8, .Pcm16, .Pcm24, .Pcm32:
            Wav.copySubformat(&wfx.subFormat, Wav.SubformatPcm)
            voice.requestedEncoding = file.encoding

        case .Float32:
            Wav.copySubformat(&wfx.subFormat, Wav.SubformatIeeeFloat)
            voice.requestedEncoding = file.encoding

        default:
            Wav.copySubformat(&wfx.subFormat, Wav.SubformatPcm)
            wfx.format.wBitsPerSample = 16
            voice.requestedEncoding   = .Pcm16
        }

        wfx.format.nBlockAlign          = cast(u16) (wfx.format.nChannels * (wfx.format.wBitsPerSample / 8))
        wfx.format.nAvgBytesPerSec      = wfx.format.nBlockAlign * wfx.format.nSamplesPerSec
        wfx.samples.wValidBitsPerSample = wfx.format.wBitsPerSample

        var flags: DWORD
        if !createFlags.has(.PitchControl) do
            flags |= XAUDIO2_VOICE_NOPITCH
        var handle: #null *IXAudio2SourceVoice
        let safeXAudio2       = g_Driver.xAudio2.xAudio2!
        let createSourceVoice = safeXAudio2.vtbl.createSourceVoice
        let hr                = createSourceVoice(safeXAudio2, &handle, cast(const *WAVEFORMATEX) &wfx.format, flags, XAUDIO2_DEFAULT_FREQ_RATIO, &g_Cb, null, null)
        if hr != S_OK do
            fail SystemError{"createSourceVoice", errorID: hresultErrorId(hr)}
        voice.handle = cast(#null *void) handle
    }

    mtd destroyXAudio2()
    {
        if !.handle do
            return
        let safeHandle   = .handle
        let handle       = cast(*IXAudio2SourceVoice) safeHandle
        let destroyVoice = handle.vtbl.destroyVoice
        destroyVoice(cast(*IXAudio2Voice) handle)
        .handle = null
    }

    mtd updateXAudio2()->bool fail
    {
        if !.handle do
            return false

        let safeHandle = .handle
        let handle     = cast(*IXAudio2SourceVoice) safeHandle
        var voiceState: XAUDIO2_VOICE_STATE
        let getState   = handle.vtbl.getState
        getState(handle, &voiceState, 0)
        while voiceState.buffersQueued < NumDecodedBuffers - 1
        {
            let {ptrBuffer, sizeBuffer} = .readBuffer()
            if !sizeBuffer do
                break

            var buffer: XAUDIO2_BUFFER = undefined
            let safePtrBuffer          = ptrBuffer!
            buffer.pAudioData = cast(const *BYTE) safePtrBuffer
            buffer.audioBytes = cast() sizeBuffer
            buffer.pContext   = me
            let submitSourceBuffer = handle.vtbl.submitSourceBuffer
            let hr                 = submitSourceBuffer(handle, &buffer, null)
            if hr != S_OK do
                fail SystemError{"submitSourceBuffer", errorID: hresultErrorId(hr)}
            getState(handle, &voiceState, 0)
        }

        return voiceState.buffersQueued != 0
    }

    mtd playXAudio2(batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let safeHandle = .handle
        let handle     = cast(*IXAudio2SourceVoice) safeHandle
        let start      = handle.vtbl.start
        let hr         = start(handle, 0, batchId)
        if hr != S_OK do
            fail SystemError{"start", errorID: hresultErrorId(hr)}
    }

    mtd stopXAudio2(batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let safeHandle = .handle
        let handle     = cast(*IXAudio2SourceVoice) safeHandle
        let stop       = handle.vtbl.stop
        let hr         = stop(handle, 0, batchId)
        if hr != S_OK do
            fail SystemError{"stop", errorID: hresultErrorId(hr)}
    }

    mtd resetXAudio2() fail
    {
        if !.handle do
            return
        let handle = cast(*IXAudio2SourceVoice) .handle
        let hr     = handle.vtbl.flushSourceBuffers(handle)
        if hr != S_OK do
            fail SystemError{"cannot flush XAudio2 source buffers", errorID: hresultErrorId(hr)}
    }
}

internal impl Voice
{
    // Sets this voice's XAudio2 gain as a linear value from `0` through `1`.
    mtd setVolumeXAudio2(volume: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let safeHandle = .handle
        let handle     = cast(*IXAudio2SourceVoice) safeHandle
        let v          = Math.clamp(volume, 0, 1)
        let setVolume  = handle.vtbl.setVolume
        let hr         = setVolume(cast(*IXAudio2Voice) handle, v, batchId)
        if hr != S_OK do
            fail SystemError{"setVolume", errorID: hresultErrorId(hr)}
    }

    // Returns this voice's current XAudio2 linear gain.
    mtd volumeXAudio2()->f32 fail
    {
        if !.handle do
            return 0
        let safeHandle = .handle
        let handle     = cast(*IXAudio2SourceVoice) safeHandle
        var volume: f32
        let getVolume  = handle.vtbl.getVolume
        getVolume(cast(*IXAudio2Voice) handle, &volume)
        return volume
    }

    // Sets this voice's XAudio2 playback frequency ratio.
    //
    // The voice must have been created with
    // [[Audio.VoiceCreateFlags.PitchControl]]. Prefer
    // [[Audio.Voice.setFrequencyRatio]] in backend-independent code.
    mtd setFrequencyRatioXAudio2(ratio: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let safeHandle        = .handle
        let handle            = cast(*IXAudio2SourceVoice) safeHandle
        let setFrequencyRatio = handle.vtbl.setFrequencyRatio
        let hr                = setFrequencyRatio(handle, ratio, batchId)
        if hr != S_OK do
            fail SystemError{"setFrequencyRatio", errorID: hresultErrorId(hr)}
    }

    // Returns this voice's XAudio2 playback frequency ratio.
    mtd frequencyRatioXAudio2()->f32 fail
    {
        if !.handle do
            return 0
        let handle = cast(*IXAudio2SourceVoice) .handle
        var ratio: f32
        handle.vtbl.getFrequencyRatio(handle, &ratio)
        return ratio
    }

    // Replaces this voice's XAudio2 output buses.
    //
    // An empty slice routes to the mastering voice. Prefer
    // [[Audio.Voice.setRouting]] in backend-independent code.
    mtd setRoutingXAudio2(buses: const [..] *Bus) fail
    {
        const MaxBus = 16
        var sfxSend:      [MaxBus] XAUDIO2_SEND_DESCRIPTOR = undefined
        var sfxSendList:  XAUDIO2_VOICE_SENDS              = undefined
        var pSFXSEndList: #null *XAUDIO2_VOICE_SENDS

        let count = @countof(buses)
        if count > MaxBus do
            fail SystemError{"too many buses", errorID: count}

        if count
        {
            for [i] in count
            {
                let bus           = buses[i]
                let safeBusHandle = bus.handle!
                sfxSend[i].pOutputVoice = cast(*IXAudio2Voice) safeBusHandle
            }

            sfxSendList.sendCount = cast() count
            sfxSendList.pSends    = &sfxSend
            pSFXSEndList          = &sfxSendList
        }

        let safeHandle      = .handle!
        let handle          = cast(*IXAudio2SourceVoice) safeHandle
        let setOutputVoices = handle.vtbl.setOutputVoices
        let hr              = setOutputVoices(cast(*IXAudio2Voice) handle, pSFXSEndList)
        if hr != S_OK do
            fail SystemError{"setOutputVoices", errorID: hresultErrorId(hr)}
    }
}

///////////////////////////////////////////////////////////////
// BUS
///////////////////////////////////////////////////////////////

impl Bus
{
    func createXAudio2(bus: *Bus, numChannels: u32, parent: #null *Bus = null) fail
    {
        var sfxSend:      XAUDIO2_SEND_DESCRIPTOR = undefined
        var sfxSendList:  XAUDIO2_VOICE_SENDS     = undefined
        var pSFXSEndList: #null *XAUDIO2_VOICE_SENDS

        if parent
        {
            if !parent.handle do
                fail BadParameterError{"parent bus invalid"}

            let safeParentHandle = parent.handle
            sfxSend.pOutputVoice  = cast(*IXAudio2Voice) safeParentHandle
            sfxSendList.sendCount = 1
            sfxSendList.pSends    = &sfxSend
            pSFXSEndList          = &sfxSendList
        }

        var handle: #null *IXAudio2SubmixVoice
        let safeXAudio2       = g_Driver.xAudio2.xAudio2!
        let createSubmixVoice = safeXAudio2.vtbl.createSubmixVoice
        let hr                = createSubmixVoice(safeXAudio2, &handle, numChannels, 44100, XAUDIO2_VOICE_USEFILTER, 0, pSFXSEndList, null)
        if hr != S_OK do
            fail SystemError{"createSubmixVoice", errorID: hresultErrorId(hr)}
        bus.handle = cast(#null *void) handle
    }

    mtd destroyXAudio2()
    {
        if !.handle do
            return
        let safeHandle   = .handle
        let handle       = cast(*IXAudio2SubmixVoice) safeHandle
        let destroyVoice = handle.vtbl.destroyVoice
        destroyVoice(cast(*IXAudio2Voice) handle)
        .handle = null
    }
}

internal impl Bus
{
    // Sets this XAudio2 submix gain as a linear value from `0` through `1`.
    mtd setVolumeXAudio2(volume: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let safeHandle = .handle
        let handle     = cast(*IXAudio2SubmixVoice) safeHandle
        let v          = Math.clamp(volume, 0, 1)
        let setVolume  = handle.vtbl.setVolume
        let hr         = setVolume(cast(*IXAudio2Voice) handle, v, batchId)
        if hr != S_OK do
            fail SystemError{"setVolume", errorID: hresultErrorId(hr)}
    }

    // Returns this XAudio2 submix's current linear gain.
    mtd volumeXAudio2()->f32 fail
    {
        if !.handle do
            return 0
        let safeHandle = .handle
        let handle     = cast(*IXAudio2SubmixVoice) safeHandle
        var volume: f32
        let getVolume  = handle.vtbl.getVolume
        getVolume(cast(*IXAudio2Voice) handle, &volume)
        return volume
    }
}

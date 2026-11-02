#global if #os == Swag.TargetOs.Linux

using Swag, Core, Core.Errors

private func checkFAudio(code: u32, operation: string) fail
{
    if code != 0 do
        fail SystemError{operation, errorID: code}
}

struct FAudioDriverNative
{
    mixerMutex:                                Swag.Mutex
    late FAudio_SetEngineProcedureEXT:         FAudio.FAudio_SetEngineProcedureEXT_fn
    library:                                   NativeLibrary
    engine:                                    *void?
    master:                                    *void?
    callbackContext:                           Swag.Context
    callbacks:                                 FAudio.FAudioVoiceCallback
    late FAudioCreate:                         FAudio.FAudioCreate_fn
    late FAudio_Release:                       FAudio.FAudio_Release_fn
    late FAudio_StopEngine:                    FAudio.FAudio_StopEngine_fn
    late FAudio_CreateMasteringVoice:          FAudio.FAudio_CreateMasteringVoice_fn
    late FAudio_CreateSourceVoice:             FAudio.FAudio_CreateSourceVoice_fn
    late FAudio_CreateSubmixVoice:             FAudio.FAudio_CreateSubmixVoice_fn
    late FAudioVoice_DestroyVoice:             FAudio.FAudioVoice_DestroyVoice_fn
    late FAudioVoice_SetVolume:                FAudio.FAudioVoice_SetVolume_fn
    late FAudioVoice_GetVolume:                FAudio.FAudioVoice_GetVolume_fn
    late FAudioVoice_SetOutputVoices:          FAudio.FAudioVoice_SetOutputVoices_fn
    late FAudioSourceVoice_Start:              FAudio.FAudioSourceVoice_Start_fn
    late FAudioSourceVoice_Stop:               FAudio.FAudioSourceVoice_Stop_fn
    late FAudioSourceVoice_FlushSourceBuffers: FAudio.FAudioSourceVoice_FlushSourceBuffers_fn
    late FAudioSourceVoice_SubmitSourceBuffer: FAudio.FAudioSourceVoice_SubmitSourceBuffer_fn
    late FAudioSourceVoice_GetState:           FAudio.FAudioSourceVoice_GetState_fn
    late FAudioSourceVoice_SetFrequencyRatio:  FAudio.FAudioSourceVoice_SetFrequencyRatio_fn
    late FAudioSourceVoice_GetFrequencyRatio:  FAudio.FAudioSourceVoice_GetFrequencyRatio_fn
}

impl FAudioDriverNative
{
    private mtd(T) symbol(name: string)->T fail
    {
        let address = .library.symbol(name)
        if not address do
            fail SystemError{"required FAudio entry point is unavailable"}
        return cast(T, address)
    }

    mtd createFAudio() fail
    {
        .library = try NativeLibrary.load("libFAudio.so.0")
        defer #fail .destroyFAudio()
        .FAudio_SetEngineProcedureEXT         = try .symbol'FAudio.FAudio_SetEngineProcedureEXT_fn("FAudio_SetEngineProcedureEXT")
        .FAudioCreate                         = try .symbol'FAudio.FAudioCreate_fn("FAudioCreate")
        .FAudio_Release                       = try .symbol'FAudio.FAudio_Release_fn("FAudio_Release")
        .FAudio_StopEngine                    = try .symbol'FAudio.FAudio_StopEngine_fn("FAudio_StopEngine")
        .FAudio_CreateMasteringVoice          = try .symbol'FAudio.FAudio_CreateMasteringVoice_fn("FAudio_CreateMasteringVoice")
        .FAudio_CreateSourceVoice             = try .symbol'FAudio.FAudio_CreateSourceVoice_fn("FAudio_CreateSourceVoice")
        .FAudio_CreateSubmixVoice             = try .symbol'FAudio.FAudio_CreateSubmixVoice_fn("FAudio_CreateSubmixVoice")
        .FAudioVoice_DestroyVoice             = try .symbol'FAudio.FAudioVoice_DestroyVoice_fn("FAudioVoice_DestroyVoice")
        .FAudioVoice_SetVolume                = try .symbol'FAudio.FAudioVoice_SetVolume_fn("FAudioVoice_SetVolume")
        .FAudioVoice_GetVolume                = try .symbol'FAudio.FAudioVoice_GetVolume_fn("FAudioVoice_GetVolume")
        .FAudioVoice_SetOutputVoices          = try .symbol'FAudio.FAudioVoice_SetOutputVoices_fn("FAudioVoice_SetOutputVoices")
        .FAudioSourceVoice_Start              = try .symbol'FAudio.FAudioSourceVoice_Start_fn("FAudioSourceVoice_Start")
        .FAudioSourceVoice_Stop               = try .symbol'FAudio.FAudioSourceVoice_Stop_fn("FAudioSourceVoice_Stop")
        .FAudioSourceVoice_FlushSourceBuffers = try .symbol'FAudio.FAudioSourceVoice_FlushSourceBuffers_fn("FAudioSourceVoice_FlushSourceBuffers")
        .FAudioSourceVoice_SubmitSourceBuffer = try .symbol'FAudio.FAudioSourceVoice_SubmitSourceBuffer_fn("FAudioSourceVoice_SubmitSourceBuffer")
        .FAudioSourceVoice_GetState           = try .symbol'FAudio.FAudioSourceVoice_GetState_fn("FAudioSourceVoice_GetState")
        .FAudioSourceVoice_SetFrequencyRatio  = try .symbol'FAudio.FAudioSourceVoice_SetFrequencyRatio_fn("FAudioSourceVoice_SetFrequencyRatio")
        .FAudioSourceVoice_GetFrequencyRatio  = try .symbol'FAudio.FAudioSourceVoice_GetFrequencyRatio_fn("FAudioSourceVoice_GetFrequencyRatio")

        // FAudio calls back on its native mixer thread. Give it separate scratch/error storage.
        .callbackContext = Swag.getContext()[]
        let temporaryCapacity = .callbackContext.tempAllocator.capacity
        let errorCapacity     = .callbackContext.errorAllocator.capacity
        .callbackContext.resetThreadState()
        let allocator = unwrap .callbackContext.allocator
        .callbackContext.tempAllocator.setCapacity(temporaryCapacity, allocator)
        .callbackContext.errorAllocator.setCapacity(errorCapacity, allocator)
        .callbacks.OnBufferEnd                = &onFAudioBufferEnd
        .callbacks.OnBufferStart              = &ignoreFAudioBuffer
        .callbacks.OnLoopEnd                  = &ignoreFAudioBuffer
        .callbacks.OnStreamEnd                = &ignoreFAudioPass
        .callbacks.OnVoiceError               = &ignoreFAudioError
        .callbacks.OnVoiceProcessingPassEnd   = &ignoreFAudioPass
        .callbacks.OnVoiceProcessingPassStart = &ignoreFAudioStart
        try checkFAudio(.FAudioCreate(&.engine, 0, FAudio.FAUDIO_DEFAULT_PROCESSOR), "cannot create FAudio engine")
        .FAudio_SetEngineProcedureEXT(unwrap .engine, &runFAudioMixer, me)
        try checkFAudio(.FAudio_CreateMasteringVoice(.engine, &.master, 0, 0, 0, 0, null),
                        "cannot open FAudio output device")
    }

    mtd stopEngineFAudio()
    {
        if .engine
        {
            // FAudio_StopEngine only changes an activity flag. Serialize that change with
            // the complete mixer procedure so no in-flight callback survives shutdown.
            .mixerMutex.lock()
            .FAudio_StopEngine(.engine)
            .mixerMutex.unlock()
        }
    }

    mtd destroyFAudio()
    {
        .stopEngineFAudio()
        if .master do
            .FAudioVoice_DestroyVoice(.master)
        .master = null
        if .engine do
            discard .FAudio_Release(.engine)
        .engine = null
        .callbackContext.tempAllocator.release()
        .callbackContext.releaseErrorStorage()
        .library.close()
    }

    mtd setOutputVolumeFAudio(volume: f32) fail
    {
        try checkFAudio(.FAudioVoice_SetVolume(unwrap .master, volume, 0), "cannot set FAudio output volume")
    }

    mtd outputVolumeFAudio()->f32
    {
        var volume: f32
        .FAudioVoice_GetVolume(unwrap .master, &volume)
        return volume
    }
}

#[Swag.CallingConvention(.C)]
private func runFAudioMixer(procedure: FAudio.FAudioEngineCallEXT, engine: *FAudio.FAudio, output: *f32, user: *void)
{
    let native  = cast(*FAudioDriverNative, user)
    let context = Swag.getContext()
    if context == null or context.allocator.buffer == null do
        Swag.setContext(&native.callbackContext)
    native.mixerMutex.lock()
    procedure(engine, output)
    native.mixerMutex.unlock()
}

#[Swag.CallingConvention(.C)]
private func ignoreFAudioBuffer(_: *FAudio.FAudioVoiceCallback, _: *void?) {}
#[Swag.CallingConvention(.C)]
private func ignoreFAudioPass(_: *FAudio.FAudioVoiceCallback) {}
#[Swag.CallingConvention(.C)]
private func ignoreFAudioError(_: *FAudio.FAudioVoiceCallback, _: *void?, _: u32) {}
#[Swag.CallingConvention(.C)]
private func ignoreFAudioStart(_: *FAudio.FAudioVoiceCallback, _: u32) {}

#[Swag.CallingConvention(.C)]
private func onFAudioBufferEnd(_: *FAudio.FAudioVoiceCallback, context: *void?)
{
    let voice = cast(*Voice?, context)
    if not voice or voice.hasState(.PendingDestroy) do
        return
    let current = Swag.getContext()
    if current == null or current.allocator.buffer == null do
        Swag.setContext(&g_Driver.fAudio.callbackContext)
    g_Driver.updateVoice(voice, .UpdateBuffers)
}

impl Voice
{
    func createFAudio(voice: *Voice, createFlags = VoiceCreateFlags.Default) fail
    {
        let file = unwrap voice.file
        if not file.channelCount or file.channelCount > 8 do
            fail BadParameterError{"FAudio supports one through eight source channels"}
        if file.sampleRate < 1000 or file.sampleRate > 200000 do
            fail BadParameterError{"FAudio source sample rate must be between 1000 and 200000 Hz"}
        var format: FAudio.FAudioWaveFormatExtensible
        format.Format.wFormatTag     = FAudio.FAUDIO_FORMAT_EXTENSIBLE
        format.Format.nChannels      = cast(u16, file.channelCount)
        format.Format.nSamplesPerSec = file.sampleRate
        format.Format.wBitsPerSample = cast(u16, file.bitsPerSample)
        format.Format.cbSize         = 22
        format.dwChannelMask         = file.waveSpeakerMask
        format.SubFormat             = {Data1: 1, Data2: 0, Data3: 0x0010, Data4: [0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71]}
        switch file.encoding
        {
        case .Pcm8, .Pcm16, .Pcm24, .Pcm32:
            voice.requestedEncoding = file.encoding

        case .Float32:
            format.SubFormat.Data1  = 3
            voice.requestedEncoding = .Float32

        default:
            format.Format.wBitsPerSample = 16
            voice.requestedEncoding      = .Pcm16
        }

        format.Samples.wValidBitsPerSample = format.Format.wBitsPerSample
        format.Format.nBlockAlign          = cast(u16, file.channelCount * (format.Format.wBitsPerSample / 8))
        format.Format.nAvgBytesPerSec      = file.sampleRate * format.Format.nBlockAlign
        let flags  = createFlags.has(.PitchControl) ? 0'u32 : FAudio.FAUDIO_VOICE_NOPITCH
        let native = &g_Driver.fAudio
        try checkFAudio(native.FAudio_CreateSourceVoice(unwrap native.engine, &voice.handle, &format.Format, flags, FAudio.FAUDIO_DEFAULT_FREQ_RATIO, &native.callbacks, null, null), "cannot create FAudio source voice")
    }

    mtd destroyFAudio()
    {
        if .handle do
            g_Driver.fAudio.FAudioVoice_DestroyVoice(.handle)
        .handle = null
    }

    mtd updateFAudio()->bool fail
    {
        if not .handle do
            return false
        let native = &g_Driver.fAudio
        var state: FAudio.FAudioVoiceState
        native.FAudioSourceVoice_GetState(.handle, &state, 0)
        while state.BuffersQueued < NumDecodedBuffers - 1
        {
            let {buffer, size} = try .readBuffer()
            if not size do
                break
            if size > Swag.U32.Max do
                fail OverflowError{"audio buffer exceeds the native size limit"}
            let submitted = FAudio.FAudioBuffer{AudioBytes: cast(u32, size),
                                                pAudioData: cast(const [*]u8?, buffer), pContext: me}
            try checkFAudio(native.FAudioSourceVoice_SubmitSourceBuffer(.handle, &submitted, null),
                            "cannot submit FAudio source buffer")
            native.FAudioSourceVoice_GetState(.handle, &state, 0)
        }

        return state.BuffersQueued != 0
    }

    mtd playFAudio(batchId: u32 = 0) fail
    {
        Sync.scopedLock(&g_Driver.fAudio.mixerMutex)
        try checkFAudio(g_Driver.fAudio.FAudioSourceVoice_Start(unwrap .handle, 0, batchId), "cannot start FAudio voice")
    }

    mtd stopFAudio(batchId: u32 = 0) fail
    {
        Sync.scopedLock(&g_Driver.fAudio.mixerMutex)
        if .handle do
            try checkFAudio(g_Driver.fAudio.FAudioSourceVoice_Stop(.handle, 0, batchId), "cannot pause FAudio voice")
    }

    mtd resetFAudio() fail
    {
        Sync.scopedLock(&g_Driver.fAudio.mixerMutex)
        if .handle do
            try checkFAudio(g_Driver.fAudio.FAudioSourceVoice_FlushSourceBuffers(.handle), "cannot flush FAudio voice")
    }

    mtd playedFramesFAudio()->u64
    {
        if not .handle do
            return 0
        var state: FAudio.FAudioVoiceState
        g_Driver.fAudio.FAudioSourceVoice_GetState(.handle, &state, 0)
        return state.SamplesPlayed
    }

    mtd setVolumeFAudio(volume: f32, batchId: u32 = 0) fail
    {
        try checkFAudio(g_Driver.fAudio.FAudioVoice_SetVolume(unwrap .handle, Math.clamp(volume, 0, 1), batchId),
                        "cannot set FAudio voice volume")
    }

    mtd volumeFAudio()->f32 fail
    {
        var volume: f32
        g_Driver.fAudio.FAudioVoice_GetVolume(unwrap .handle, &volume)
        return volume
    }

    mtd setFrequencyRatioFAudio(ratio: f32, batchId: u32 = 0) fail
    {
        Sync.scopedLock(&g_Driver.fAudio.mixerMutex)
        if not Math.isFinite(ratio) or ratio < 1.0 / 1024.0 or ratio > FAudio.FAUDIO_DEFAULT_FREQ_RATIO do
            fail BadParameterError{"FAudio frequency ratio must be between 1/1024 and 2"}
        try checkFAudio(g_Driver.fAudio.FAudioSourceVoice_SetFrequencyRatio(unwrap .handle, ratio, batchId),
                        "cannot set FAudio voice frequency ratio")
    }

    mtd frequencyRatioFAudio()->f32 fail
    {
        var ratio: f32
        g_Driver.fAudio.FAudioSourceVoice_GetFrequencyRatio(unwrap .handle, &ratio)
        return ratio
    }

    mtd setRoutingFAudio(buses: const [..] *Bus) fail
    {
        if buses.count > 16 do
            fail BadParameterError{"too many output buses"}
        var descriptors: [16] FAudio.FAudioSendDescriptor
        for i in buses.count do
            descriptors[i].pOutputVoice = buses[i].handle
        var sends = FAudio.FAudioVoiceSends{SendCount: cast(u32, buses.count), pSends: &descriptors[0]}
        try checkFAudio(g_Driver.fAudio.FAudioVoice_SetOutputVoices(unwrap .handle,
                                                                    buses.count ? &sends : null),
                        "cannot route FAudio voice")
    }
}

impl Bus
{
    func createFAudio(bus: *Bus, numChannels: u32, parent: *Bus? = null) fail
    {
        if numChannels > 8 do
            fail BadParameterError{"audio bus supports at most 8 channels"}
        var descriptor: FAudio.FAudioSendDescriptor
        var sends    = FAudio.FAudioVoiceSends{SendCount: 1, pSends: &descriptor}
        var stage    = Swag.U32.Max
        var ancestor = parent
        while ancestor
        {
            stage    -= 1
            ancestor = ancestor.parent
        }

        if parent do
            descriptor.pOutputVoice = parent.handle
        let native = &g_Driver.fAudio
        try checkFAudio(native.FAudio_CreateSubmixVoice(unwrap native.engine,
                                                        &bus.handle,
                                                        numChannels,
                                                        44100,
                                                        0,
                                                        stage,
                                                        parent ? &sends : null,
                                                        null),
                        "cannot create FAudio submix")
    }

    mtd destroyFAudio()
    {
        if .handle do
            g_Driver.fAudio.FAudioVoice_DestroyVoice(.handle)
        .handle = null
    }

    mtd setVolumeFAudio(volume: f32, batchId: u32 = 0) fail
    {
        try checkFAudio(g_Driver.fAudio.FAudioVoice_SetVolume(unwrap .handle, Math.clamp(volume, 0, 1), batchId),
                        "cannot set FAudio bus volume")
    }

    mtd volumeFAudio()->f32 fail
    {
        var volume: f32
        g_Driver.fAudio.FAudioVoice_GetVolume(unwrap .handle, &volume)
        return volume
    }
}

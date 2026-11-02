#global export

alias FAudio      = void
alias FAudioVoice = void

const FAUDIO_DEFAULT_PROCESSOR  = 0xFFFFFFFF'u32
const FAUDIO_DEFAULT_FREQ_RATIO = 2'f32
const FAUDIO_VOICE_NOPITCH      = 0x0002'u32
const FAUDIO_VOICE_USEFILTER    = 0x0008'u32
const FAUDIO_FORMAT_EXTENSIBLE  = 0xFFFE'u16

#[Swag.Pack(1)]
struct FAudioGUID { public { Data1: u32; Data2: u16; Data3: u16; Data4: [8] u8 } }

#[Swag.Pack(1)]
struct FAudioWaveFormatEx
{
    public
    {
        wFormatTag:      u16
        nChannels:       u16
        nSamplesPerSec:  u32
        nAvgBytesPerSec: u32
        nBlockAlign:     u16
        wBitsPerSample:  u16
        cbSize:          u16
    }
}

#[Swag.Pack(1)]
struct FAudioWaveFormatExtensible
{
    public { Format: FAudioWaveFormatEx; Samples: union { wValidBitsPerSample: u16; wSamplesPerBlock: u16; wReserved: u16 }; dwChannelMask: u32; SubFormat: FAudioGUID }
}

#[Swag.Pack(1)]
struct FAudioBuffer
{
    public
    {
        Flags:      u32
        AudioBytes: u32
        pAudioData: const [*] u8?
        PlayBegin:  u32
        PlayLength: u32
        LoopBegin:  u32
        LoopLength: u32
        LoopCount:  u32
        pContext:   *void?
    }
}

#[Swag.Pack(1)]
struct FAudioVoiceState { public { pCurrentBufferContext: *void?; BuffersQueued: u32; SamplesPlayed: u64 } }
#[Swag.Pack(1)]
struct FAudioSendDescriptor { public { Flags: u32; pOutputVoice: *FAudioVoice? } }
#[Swag.Pack(1)]
struct FAudioVoiceSends { public { SendCount: u32; pSends: *FAudioSendDescriptor? } }

#[Swag.CallingConvention(.C)]
alias OnBufferEndFunc                = func(*FAudioVoiceCallback, *void?)
#[Swag.CallingConvention(.C)]
alias OnBufferStartFunc              = func(*FAudioVoiceCallback, *void?)
#[Swag.CallingConvention(.C)]
alias OnLoopEndFunc                  = func(*FAudioVoiceCallback, *void?)
#[Swag.CallingConvention(.C)]
alias OnStreamEndFunc                = func(*FAudioVoiceCallback)
#[Swag.CallingConvention(.C)]
alias OnVoiceErrorFunc               = func(*FAudioVoiceCallback, *void?, u32)
#[Swag.CallingConvention(.C)]
alias OnVoiceProcessingPassEndFunc   = func(*FAudioVoiceCallback)
#[Swag.CallingConvention(.C)]
alias OnVoiceProcessingPassStartFunc = func(*FAudioVoiceCallback, u32)

struct FAudioVoiceCallback
{
    public
    {
        OnBufferEnd:                OnBufferEndFunc?
        OnBufferStart:              OnBufferStartFunc?
        OnLoopEnd:                  OnLoopEndFunc?
        OnStreamEnd:                OnStreamEndFunc?
        OnVoiceError:               OnVoiceErrorFunc?
        OnVoiceProcessingPassEnd:   OnVoiceProcessingPassEndFunc?
        OnVoiceProcessingPassStart: OnVoiceProcessingPassStartFunc?
    }
}

#assert(#sizeof(FAudioWaveFormatEx) == 18)
#assert(#sizeof(FAudioWaveFormatExtensible) == 40)
#assert(#sizeof(FAudioBuffer) == 44)
#assert(#sizeof(FAudioVoiceState) == 20)
#assert(#sizeof(FAudioSendDescriptor) == 12)
#assert(#sizeof(FAudioVoiceSends) == 12)
#assert(#sizeof(FAudioVoiceCallback) == 56)

#[Swag.CallingConvention(.C)]
alias FAudioCreate_fn                         = func(**FAudio?, u32, u32)->u32

#[Swag.CallingConvention(.C)]
alias FAudio_Release_fn                       = func(*FAudio)->u32

#[Swag.CallingConvention(.C)]
alias FAudio_StopEngine_fn                    = func(*FAudio)

#[Swag.CallingConvention(.C)]
alias FAudio_CreateMasteringVoice_fn          = func(*FAudio, **FAudioVoice?, u32, u32, u32, u32, const *void?)->u32

#[Swag.CallingConvention(.C)]
alias FAudio_CreateSourceVoice_fn             = func(*FAudio, **FAudioVoice?, const *FAudioWaveFormatEx, u32, f32, *FAudioVoiceCallback?, const *FAudioVoiceSends?, const *void?)->u32

#[Swag.CallingConvention(.C)]
alias FAudio_CreateSubmixVoice_fn             = func(*FAudio, **FAudioVoice?, u32, u32, u32, u32, const *FAudioVoiceSends?, const *void?)->u32

#[Swag.CallingConvention(.C)]
alias FAudioVoice_DestroyVoice_fn             = func(*FAudioVoice)

#[Swag.CallingConvention(.C)]
alias FAudioVoice_SetVolume_fn                = func(*FAudioVoice, f32, u32)->u32

#[Swag.CallingConvention(.C)]
alias FAudioVoice_GetVolume_fn                = func(*FAudioVoice, *f32)

#[Swag.CallingConvention(.C)]
alias FAudioVoice_SetOutputVoices_fn          = func(*FAudioVoice, const *FAudioVoiceSends?)->u32

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_Start_fn              = func(*FAudioVoice, u32, u32)->u32

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_Stop_fn               = func(*FAudioVoice, u32, u32)->u32

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_FlushSourceBuffers_fn = func(*FAudioVoice)->u32

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_SubmitSourceBuffer_fn = func(*FAudioVoice, const *FAudioBuffer, const *void?)->u32

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_GetState_fn           = func(*FAudioVoice, *FAudioVoiceState, u32)

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_SetFrequencyRatio_fn  = func(*FAudioVoice, f32, u32)->u32

#[Swag.CallingConvention(.C)]
alias FAudioSourceVoice_GetFrequencyRatio_fn  = func(*FAudioVoice, *f32)

#[Swag.CallingConvention(.C)]
alias FAudioEngineCallEXT = func(*FAudio, *f32)
#[Swag.CallingConvention(.C)]
alias FAudioEngineProcedureEXT = func(FAudioEngineCallEXT, *FAudio, *f32, *void)
#[Swag.CallingConvention(.C)]
alias FAudio_SetEngineProcedureEXT_fn = func(*FAudio, FAudioEngineProcedureEXT, *void)

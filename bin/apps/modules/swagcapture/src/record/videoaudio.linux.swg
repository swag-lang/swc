#global if #os == Swag.TargetOs.Linux

using Core, Video

// Linux currently records video without native sound sources.
struct VideoRecordingAudio {}

impl VideoRecordingAudio
{
    func configs(_: bool, _: bool)->Array'Mp4.SoftwareAudioConfig => {}
    mtd start(_: *VideoCaptureSession, _: bool, _: bool) fail {}
    mtd pump() fail {}
    mtd close() {}
    mtd finish() fail {}
}

#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Pixel, Video, Audio

// Stopping must retain more queued sound than the live pump's 4096-frame interface budget.
#test
{
    let path = Gui.Testing.tempFilePath("capture-audio-finalize-", ".mp4")
    defer discard catch File.delete(path)
    let configs = VideoRecordingAudio.configs(true, true)
    var session = expect VideoCaptureSession.create(path, {0, 0, 16, 16},
                                                    expect FrameRate.create(30, 1), false, configs.toSlice())
    discard expect session.captureAt(0)
    var audio: VideoRecordingAudio
    audio.microphoneQueue = expect CaptureQueue.create(48_000, 1, 0, 48_000, slots: 16)
    audio.systemQueue = expect CaptureQueue.create(48_000, 2, 0, 48_000, slots: 16)
    audio.microphonePump = expect VideoAudioPump.create(&session, &audio.microphoneQueue, 0)
    audio.systemPump = expect VideoAudioPump.create(&session, &audio.systemQueue, 1)
    audio.wantsMicrophone = true
    audio.wantsSystem = true
    var mono: [960] s16
    var stereo: [1920] s16
    for index in mono.count
    {
        mono[index] = cast(s16, index % 160 * 80)
        stereo[index * 2], stereo[index * 2 + 1] = mono[index]
    }
    for index in 12'u64
    {
        discard expect audio.microphoneQueue.push(mono, index * 960)
        discard expect audio.systemQueue.push(stereo, index * 960)
    }
    audio.close()
    Swag.require(audio.microphonePump.inputFrameCount() == 11_520)
    Swag.require(audio.systemPump.inputFrameCount() == 11_520)
    audio.close()
    expect session.end()
    var reader = expect Video.Reader.open(path)
    Swag.require(reader.audioTrackCount() == 2)
    for index in 2'u32 do
        Swag.require(reader.audioTrack(index)!.sampleFrameCount() == 11_520)
}

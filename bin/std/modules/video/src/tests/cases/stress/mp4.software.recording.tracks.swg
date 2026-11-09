#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

// Encodes one second of 1080p60 video with four independently timed AAC sound tracks.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("mp4-software-four-tracks-1080p60", "mp4")
    defer discard catch File.delete(path)
    let image = Image.create(1920, 1080, .BGRA8)
    Memory.set(image.pixels.storage(), 115, image.pixels.count)
    let configs: [4] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice},
                                                {48_000, 2, .Full},
                                                {48_000, 1, .Full},
                                                {48_000, 2, .Voice}]
    var recorder = expect Mp4.SoftwareRecording.createWithAudioTracks(
        path, 1920, 1080, 90_000, Swag.makeSlice(&configs[0], configs.count), keyInterval: 120)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 48_000, 90_000)
    var mono: [1_024] s16
    var stereo: [2 * 1_024] s16
    for frame in 1_024'u64
    {
        mono[frame] = cast(s16, Math.round(8_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                               800.0 * frame / 48_000.0)))
        stereo[frame * 2] = mono[frame]
        stereo[frame * 2 + 1] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                        1_600.0 * frame / 48_000.0)))
    }

    var watch: Time.Stopwatch
    watch.start()
    var audioBlocks = 0'u64
    for frame in 60'u64
    {
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))
        while audioBlocks < 47 and audioBlocks * 1_024 < (frame + 1) * 800
        {
            expect recorder.addAudioFrames(Swag.makeSlice(&mono[0], mono.count), 0)
            expect recorder.addAudioFrames(Swag.makeSlice(&stereo[0], stereo.count), 1)
            expect recorder.addAudioFrames(Swag.makeSlice(&mono[0], mono.count), 2)
            expect recorder.addAudioFrames(Swag.makeSlice(&stereo[0], stereo.count), 3)
            audioBlocks += 1
        }
    }
    expect recorder.end()
    watch.stop()
    Console.printf("Software MP4 four audio tracks 1080p60: % us for 60 video and % audio packets\n",
                   watch.elapsedMicroseconds(), (audioBlocks + 1) * 4)
    Swag.require(recorder.videoFrameCount() == 60 and recorder.audioTrackCount() == 4)
    for index in 4'u32
    {
        Swag.require(expect recorder.audioInputFrameCountOf(index) == 47 * 1_024)
        Swag.require(expect recorder.audioPacketCountOf(index) == 48)
    }

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 60 and summary.audioTracks.count == 4)
    Swag.require(not summary.hasIncompleteTail)
    for track in summary.audioTracks do
        Swag.require(track.packetCount == 48)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 60 and reader.audioTrackCount() == 4)
    for index in 4'u32
    {
        let sound = unwrap reader.audioTrack(index)
        Swag.require(sound.sampleFrameCount() == 47 * 1_024)
        Swag.require(Math.abs(sound.timelineStartSeconds()) < 0.000001)
        Swag.require(sound.numChannels() == configs[index].channelCount)
    }
}

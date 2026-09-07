#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Audio

// The opening worker can finish after a distant seek. Its old window must not replace the
// sought window even when no complete audio index is available yet.
#test
{
    var index:     Matroska.FileIndex
    var tracks:    Array'SoundFile
    var subtitles: Array'Subtitle.Track
    Matroska.selectSoundWindow(&index, 0)
    Matroska.selectSoundWindow(&index, 480_000_000_000)
    Matroska.publishSeekSound(&index, &tracks, &subtitles, 480_000_000_000, 540_000_000_000)
    let sought = Atomic.get(&index.currentSeekSound)
    Swag.assert(sought != 0)

    Matroska.publishSeekSound(&index, &tracks, &subtitles, 0, 60_000_000_000)
    Swag.assert(Atomic.get(&index.currentSeekSound) == sought)
    Swag.assert(Atomic.get(&index.seekSoundEnd) == 540_000_000_000)
    Swag.assert(index.seekSounds.count == 1)
}

// Once the full index is playable, a late bounded window must not hide the rest of the film.
#test
{
    var index:     Matroska.FileIndex
    var tracks:    Array'SoundFile
    var subtitles: Array'Subtitle.Track
    Matroska.selectSoundWindow(&index, 0)
    Matroska.publishFullSound(&index, &tracks, &subtitles)
    Matroska.publishSeekSound(&index, &tracks, &subtitles, 0, 60_000_000_000)
    Swag.assert(Atomic.get(&index.currentSeekSound) == 0)
    Swag.assert(index.seekSounds.count == 0)
}

// A foreground seek keeps its bounded window while the full scanner is paused. Completing
// that scan must not remove the window before the decoder resumes it.
#test
{
    var index:     Matroska.FileIndex
    var tracks:    Array'SoundFile
    var subtitles: Array'Subtitle.Track
    Atomic.exchange(&index.soundPause, 1)
    Matroska.selectSoundWindow(&index, 480_000_000_000)
    Matroska.publishSeekSound(&index, &tracks, &subtitles, 480_000_000_000, 540_000_000_000)
    let sought = Atomic.get(&index.currentSeekSound)
    Swag.assert(sought != 0)
    Matroska.publishFullSound(&index, &tracks, &subtitles)
    Swag.assert(Atomic.get(&index.currentSeekSound) == sought)
    Swag.assert(Atomic.get(&index.soundStage) == 1)
}

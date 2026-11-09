#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A video frame and an audio sample taken at the same instant receive the same session timestamp.
// Suspending an attached window removes the entire pause from both tracks.
#test
{
    var clock: RecordingClock
    clock.startAt(1_000_000)
    let videoTime = clock.elapsedAt(1_250_000)
    let audioTime = clock.elapsedAt(1_250_000)
    Swag.require(videoTime == 250_000 and audioTime == videoTime)

    clock.pauseAt(1_400_000)
    Swag.require(clock.elapsedAt(3_800_000) == 400_000)
    clock.resumeAt(4_000_000)
    Swag.require(clock.elapsedAt(4_100_000) == 500_000)

    clock.pauseAt(4_300_000)
    Swag.require(clock.elapsedAt(8_000_000) == 700_000)
    clock.startAt(9_000_000)
    Swag.require(clock.elapsedAt(9_010_000) == 10_000)
}

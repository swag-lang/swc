#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

// setProgression saturates to the [0..1] range.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let bar = ProgressBar.create(&host.root, {20, 20, 200, 20})
    @assert(bar.progression == 0)

    bar.setProgression(0.5)
    @assert(Math.abs(bar.progression - 0.5) < 0.001)

    bar.setProgression(2)
    @assert(bar.progression == 1)

    bar.setProgression(-1)
    @assert(bar.progression == 0)

    host.shutdown()
}

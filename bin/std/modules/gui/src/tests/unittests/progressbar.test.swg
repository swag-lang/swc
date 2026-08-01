#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// setValue saturates to the [0..1] range and indeterminate mode preserves it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let bar = ProgressBar.create(&host.root, {20, 20, 200, 20})
    @assert(bar.value == 0)

    bar.setValue(0.5)
    @assert(Math.abs(bar.value - 0.5) < 0.001)

    bar.setValue(2)
    @assert(bar.value == 1)

    bar.setValue(-1)
    @assert(bar.value == 0)

    bar.setValue(0.25)
    bar.animationPhase = 0.75
    bar.updateFlags(.Indeterminate)
    @assert(bar.flags.has(.Indeterminate))
    @assert(bar.value == 0.25 and bar.animationPhase == 0)

    bar.updateFlags(remove: .Indeterminate)
    @assert(!bar.flags.has(.Indeterminate) and bar.value == 0.25)

    host.shutdown()
}

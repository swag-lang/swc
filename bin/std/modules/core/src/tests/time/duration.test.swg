#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    let seconds: Time.Duration = 5's
    @assert(seconds.timeInSeconds == 5)
    @assert(seconds.toMs() == 5000)

    let milliseconds: Time.Duration = 250'ms
    @assert(milliseconds.timeInSeconds == 0.25)
    @assert(milliseconds.toMs() == 250)

    let minutes: Time.Duration = 2'min
    @assert(minutes.timeInSeconds == 120)

    let hours: Time.Duration = 1'h
    @assert(hours.timeInSeconds == 3600)

    let fromMs = Time.Duration.fromMs(1500)
    @assert(fromMs.timeInSeconds == 1.5)
}

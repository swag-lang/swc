#global public
#global namespace Time

alias TimerHandle = #null const *void

struct Timer
{
    userLambda: #null func(Timer)
    handle:     TimerHandle
    context:    Swag.Context
}

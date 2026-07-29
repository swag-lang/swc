#global public
#global namespace Time

// Names the timer handle type.
alias TimerHandle = #null const *void

// Represents timer.
struct Timer
{
    userLambda: #null func(Timer) // User lambda associated with this value.
    handle:     TimerHandle // Handle associated with this value.
    context:    Swag.Context // Context associated with this value.
}

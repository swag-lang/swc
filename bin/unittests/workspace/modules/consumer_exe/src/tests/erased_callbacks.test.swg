#global if #command == Swag.CompilerCommand.Test

using RuntimeCtxDll

// The callback is typed with this module's struct, and the call reaches the single instance
// compiled by the provider.
struct ErasedConsumerView
{
    using base: DepErasedBase
    total:      s32
}

var g_ErasedConsumerView: ErasedConsumerView

#test
{
    var animator: DepErasedAnimator
    animator.start(&g_ErasedConsumerView, func(view, value) { view.total += value })
    animator.step(4)
    animator.step(3)
    Swag.assert(g_ErasedConsumerView.total == 7)
}

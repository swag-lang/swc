#global public

using Pixel

// Used to animate the blending of a color.
struct BlendColor
{
    public speed: f32 = 8     // Positive interpolation speed in units per second; non-positive values complete immediately.

    // Interpolation state owned by the application animator. Set a target with `apply` and read
    // the current value with `cur`.

    internal
    {
        curVec4:   Math.Vector4           // Color of the current frame.
        destVec4:  Math.Vector4           // Color the interpolation runs to.
        themeCrc:  u32 = Swag.U32.Max     // Theme the endpoints were resolved against.
        targetWnd: #null *Wnd             // Window borrowing this blend while a track is active.
    }
}

impl BlendColor
{
    // Retargets this blend toward `target` on the supplied window's animation clock.
    mtd apply(wnd: *Wnd, target: Color)
    {
        let previousWnd = .targetWnd
        if previousWnd and previousWnd != wnd
        {
            .targetWnd = null
            if previousWnd.surface do
                previousWnd.app().animator.cancel(previousWnd, AnimationChannel.fromPointer(me))
        }

        if wnd.app().dirtyTheme != .themeCrc
        {
            .themeCrc = wnd.app().dirtyTheme

            // A palette change is one atomic visual state, not an interaction inside the current
            // palette. Cancel any old track and resolve both endpoints in the new palette so a
            // control never drifts through colors that belong to neither theme.
            let activeWnd = .targetWnd
            .targetWnd = null
            if activeWnd and activeWnd.surface do
                activeWnd.app().animator.cancel(activeWnd, AnimationChannel.fromPointer(me))
            .curVec4, .destVec4 = target.toVector4()
            return
        }

        let vec4 = target.toVector4()
        if .destVec4 == vec4 do
            return
        .destVec4 = vec4

        var source      = .curVec4
        var destination = vec4
        if source.w == 0
        {
            source.x = destination.x
            source.y = destination.y
            source.z = destination.z
        }

        if destination.w == 0
        {
            destination.x = source.x
            destination.y = source.y
            destination.z = source.z
        }

        var options: AnimationOptions
        if .speed > 0 do
            options.duration = Time.Duration.fromSeconds(1.0 / .speed)
        else do
            options.duration = {}
        options.easing           = .Linear
        options.preserveProgress = true
        .targetWnd               = null
        let handle = wnd.app().animator.animateVector4(wnd,
                                                       AnimationChannel.fromPointer(me),
                                                       source,
                                                       destination,
                                                       func|blend=me|(animationWnd, value)
                                                       {
                                                           discard animationWnd
                                                           blend.curVec4 = value
                                                       },
                                                       options,
                                                       func|blend=me, vec4, wnd|(result)
                                                       {
                                                           if blend.targetWnd != wnd do
                                                               return
                                                           if result == .Completed do
                                                               blend.curVec4 = vec4
                                                           else do
                                                               blend.destVec4 = blend.curVec4
                                                           blend.targetWnd = null
                                                       })
        if wnd.app().animator.isActive(handle) do
            .targetWnd = wnd
        else
        {
            .curVec4   = vec4
            .targetWnd = null
        }
    }

    // Reset the blend
    mtd reset()
    {
        let wnd = .targetWnd
        .targetWnd = null
        .destVec4  = .curVec4
        if wnd and wnd.surface do
            wnd.app().animator.cancel(wnd, AnimationChannel.fromPointer(me))
        .themeCrc = Swag.U32.Max
    }

    // Returns the current interpolated color.
    mtd cur()->Color
    {
        return Color.fromVector4(.curVec4)
    }
}

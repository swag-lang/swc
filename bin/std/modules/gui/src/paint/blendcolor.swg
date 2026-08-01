#global public

using Pixel

// Used to animate the blending of a color.
struct BlendColor
{
    speed: f32 = 8     // Speed of the interpolation, in units per second.

    // Interpolation state, advanced one step per frame. Set a target with 'setColor' and read
    // the current value with 'color'; the endpoints and the cursor between them are derived.
    internal
    {
        curVec4:   Math.Vector4           // Color of the current frame.
        startVec4: Math.Vector4           // Color the interpolation started from.
        destVec4:  Math.Vector4           // Color the interpolation runs to.
        factor:    f32                    // Cursor between the endpoints, from 0 to 1.
        themeCrc:  u32 = Swag.U32.Max     // Theme the endpoints were resolved against.
    }
}

impl BlendColor
{
    // Apply the color lerp to reach 'target'
    mtd apply(wnd: *Wnd, target: Color)
    {
        if wnd.app().dirtyTheme != .themeCrc
        {
            .themeCrc                       = wnd.app().dirtyTheme
            .curVec4, .startVec4, .destVec4 = target.toVector4()
            .factor                         = 1.0
            return
        }

        let vec4 = target.toVector4()
        if .destVec4 != vec4
        {
            .startVec4 = .curVec4
            .destVec4  = vec4
            .factor    = 0
        }
        elif .factor >= 1.0
        {
            .curVec4, .startVec4, .destVec4 = target.toVector4()
            return
        }

        var startV = .startVec4
        var destV  = .destVec4
        if startV.w == 0
        {
            startV.x = .destVec4.x
            startV.y = .destVec4.y
            startV.z = .destVec4.z
        }

        if destV.w == 0
        {
            destV.x = .startVec4.x
            destV.y = .startVec4.y
            destV.z = .startVec4.z
        }

        .curVec4 = Math.Vector4.lerp(startV, destV, .factor)
        .factor  += wnd.app().deltaSeconds() * .speed
        wnd.invalidate()
    }

    // Reset the blend
    mtd reset()
    {
        .themeCrc = Swag.U32.Max
    }

    // Returns the current interpolated color.
    mtd cur()->Color
    {
        return Color.fromVector4(.curVec4)
    }
}

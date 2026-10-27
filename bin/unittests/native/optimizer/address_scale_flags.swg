#global private

// A 32-byte element is beyond the scales an address encodes, so each element address below needs
// a rewrite. It sits between the comparison and the conditional move that reads its flags.
struct ScalePlane
{
    pixels: [*] u8?
    count:  u64
    width:  s32
    height: s32
    stride: s32
}

struct ScaleFrame
{
    planes: [3] ScalePlane
    blocks: u64
    valid:  bool
}

struct ScaleDecoder
{
    current: ScaleFrame
    past:    ScaleFrame
    future:  ScaleFrame
    kind:    s32
}

#[Swag.NoInline]
func scalePlaneWidth(plane: *ScalePlane, x, y: s32)->s32 => plane.width + x * 0 + y * 0

#[Swag.NoInline, Swag.Safety(.BoundCheck, false)]
func scaleSelectedWidths(decoder: *ScaleDecoder, kind: s32)->s32
{
    var sum = 0's32
    for channel in 3's32
    {
        let size = channel == 0 ? 16 : 8
        for y in size
        {
            for x in size
            {
                let reference = decoder.kind == 2 ? &decoder.future.planes[channel] : &decoder.past.planes[channel]
                var value: s32
                if kind != 5 do
                    value = scalePlaneWidth(reference, cast(s32, x), cast(s32, y))
                if kind == 10 or kind == 5 do
                    value += scalePlaneWidth(&decoder.future.planes[channel], cast(s32, x), cast(s32, y))
                sum += value
            }
        }
    }

    return sum
}

#test
{
    var decoder: ScaleDecoder
    for i in 3
    {
        decoder.future.planes[i].width = 1
        decoder.past.planes[i].width   = 100
    }

    decoder.kind = 2
    Swag.assert(scaleSelectedWidths(&decoder, 2) == 384)
    decoder.kind = 3
    Swag.assert(scaleSelectedWidths(&decoder, 4) == 38_400)
}

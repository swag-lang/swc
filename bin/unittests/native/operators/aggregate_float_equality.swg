#global private

struct FloatPair { x: f32; y: f32 }

#[Swag.NoInline]
func loadPair(value: const *FloatPair)->FloatPair => value[]

#[Swag.NoInline]
func loadArray(value: const *[4] f32)->[4] f32 => value[]

#test
{
    const nan       = cast #bit (f32, 0x7FC0_0001'u32)
    const positive  = FloatPair{0.0, 0.0}
    const negative  = FloatPair{-0.0, 0.0}
    const unordered = FloatPair{nan, 0.0}
    #assert(positive == negative)
    #assert(unordered != unordered)

    var values = [positive, negative, unordered]
    Swag.require(loadPair(&values[0]) == loadPair(&values[1]))
    Swag.require(loadPair(&values[2]) != loadPair(&values[2]))
    Swag.require((loadPair(&values[0]), ) == (loadPair(&values[1]),))
    Swag.require({point: loadPair(&values[2])} != {point: loadPair(&values[2])})
}

#test
{
    const nan = cast #bit (f32, 0x7FC0_0001'u32)
    const positive:  [4] f32 = [0.0, 1.0, 2.0, 3.0]
    const negative:  [4] f32 = [-0.0, 1.0, 2.0, 3.0]
    const unordered: [4] f32 = [nan, 1.0, 2.0, 3.0]
    #assert(positive == negative)
    #assert(unordered != unordered)

    var values = [positive, negative, unordered]
    Swag.require(loadArray(&values[0]) == loadArray(&values[1]))
    Swag.require(loadArray(&values[2]) != loadArray(&values[2]))
}

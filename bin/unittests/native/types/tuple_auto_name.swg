#global private
#global #[Swag.ExplicitNullability]

func readAutoNamedTupleThroughDecltype(seed: s32)->s32
{
    let capture = seed + 1
    let masks   = seed + 2
    var params  = {capture, boundRects: seed + 3, masks}
    let raw     = cast(#nonull *void) &params
    let p       = cast(#nonull *#decltype(params)) raw
    return p.capture + p.boundRects + p.masks
}

#test
{
    @assert(readAutoNamedTupleThroughDecltype(10) == 36)
}

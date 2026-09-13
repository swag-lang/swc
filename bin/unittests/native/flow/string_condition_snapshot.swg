#global private

// Default initialization between a named condition and its branch clears XMM registers.
// Those clears preserve the comparison flags even after the boolean test is fused away.
struct Mask
{
    id:        u32 = 0xFFFFFFFF
    transform: [6] f32
}

struct State
{
    mask:  Mask
    alpha: f32 = 1
}

#[Swag.NoInline]
func name(value: string)->string => value

#[Swag.NoInline]
func mutate(state: *State)
{
    state.mask.id = 42
    state.alpha   = 0.25
}

#[Swag.NoInline]
func capture(value: string, state: State)->State
{
    var inner      = state
    let isGroup    = name(value) == "Transparency"
    var outerMask: Mask
    var outerAlpha = 1.0'f32
    if isGroup
    {
        outerMask   = inner.mask
        outerAlpha  = inner.alpha
        inner.mask  = Mask{}
        inner.alpha = 1
    }
    mutate(&inner)
    return {outerMask, outerAlpha}
}

#test
{
    let saved = capture("Transparency", {mask: {id: 7}, alpha: 0.5})
    Swag.assert(saved.mask.id == 7)
    Swag.assert(saved.alpha == 0.5)
    let untouched = capture("Other", {mask: {id: 7}, alpha: 0.5})
    Swag.assert(untouched.mask.id == 0xFFFFFFFF)
    Swag.assert(untouched.alpha == 1)
}

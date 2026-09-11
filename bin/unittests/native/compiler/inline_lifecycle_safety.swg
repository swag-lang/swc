#global private

struct InlineMovedValue
{
    value: s32
}

#[Swag.Inline, Swag.Safety(.Lifecycle, true), Swag.Sanity(.Lifecycle, false)]
func inlineMoveWithPoison(source: *InlineMovedValue)
{
    var target = #move source[]
    discard target
}

#[Swag.Inline, Swag.Safety(.Lifecycle, false), Swag.Sanity(.Lifecycle, false)]
func inlineMoveWithoutPoison(source: *InlineMovedValue)
{
    var target = #move source[]
    discard target
}

#[Swag.Inline]
func nestedInlineMoveWithPoison(source: *InlineMovedValue)
{
    inlineMoveWithPoison(source)
}

// Inlining must retain the callee's explicit lifecycle guard in either build configuration.
#[Swag.Sanity(.Lifecycle, false)]
#test
{
    var source = InlineMovedValue{value: 19}
    inlineMoveWithPoison(&source)
    Swag.assert(source.value == -572662307)
}

#[Swag.Sanity(.Lifecycle, false)]
#test
{
    var source = InlineMovedValue{value: 23}
    inlineMoveWithoutPoison(&source)
    Swag.assert(source.value == 23)
}

#[Swag.Sanity(.Lifecycle, false)]
#test
{
    var source = InlineMovedValue{value: 29}
    nestedInlineMoveWithPoison(&source)
    Swag.assert(source.value == -572662307)
}

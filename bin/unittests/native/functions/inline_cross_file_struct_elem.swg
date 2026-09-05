#global private

// The parameter order deliberately differs from 'opIndexAssign' (me, index, value): a callee
// parameter symbol leaking into this host would be remapped by position onto 'buffer' or 'delta'
// and miscompile silently instead of failing.
#[Swag.NoInline]
func accumulate(delta: InlineCrossFile.Pair, buffer: InlineCrossFile.Buffer'InlineCrossFile.Pair, index: u64)
{
    var target = buffer
    target[index] += delta
}

#test
{
    var pairs  = [InlineCrossFile.Pair{1, 2}, InlineCrossFile.Pair{3, 4}]
    var buffer = InlineCrossFile.Buffer'InlineCrossFile.Pair{&pairs[0]}

    // A host without parameters: a leaked callee parameter has no incoming argument to read.
    buffer[1] += InlineCrossFile.Pair{10, 20}
    Swag.assert(pairs[1].x == 13 and pairs[1].y == 24)

    // A host with parameters: a leaked callee parameter would read the wrong incoming argument.
    accumulate({5, 5}, buffer, 0)
    Swag.assert(pairs[0].x == 6 and pairs[0].y == 7)
}

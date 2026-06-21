#global fileprivate

#test
{
    var concrete: InlineRegressionBug16.Implemented
    var fallback: InlineRegressionBug16.DefaultOnly

    let implemented = cast(InlineRegressionBug16.ITest) concrete
    @assert(implemented.isImplemented())

    let defaultOnly = cast(InlineRegressionBug16.ITest) fallback
    @assert(!defaultOnly.isImplemented())
}

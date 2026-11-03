#global private

#test
{
    var concrete: InlineRegressionBug16.Implemented
    var fallback: InlineRegressionBug16.DefaultOnly

    let implemented = cast(InlineRegressionBug16.ITest, concrete)
    Swag.require(implemented.isImplemented())

    let defaultOnly = cast(InlineRegressionBug16.ITest, fallback)
    Swag.require(not defaultOnly.isImplemented())
}

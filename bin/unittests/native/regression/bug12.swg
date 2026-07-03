#global private

#test
{
    let fct = InlineRegressionBug12.getInc()

    @assert(fct() == 11)
    @assert(fct() == 12)
}

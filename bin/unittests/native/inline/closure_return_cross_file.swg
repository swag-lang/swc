#global private

#test
{
    let fct = InlineRegressionBug12.getInc()

    Swag.assert(fct() == 11)
    Swag.assert(fct() == 12)
}

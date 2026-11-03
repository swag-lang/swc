#global private

#test
{
    let fct = InlineRegressionBug12.getInc()

    Swag.require(fct() == 11)
    Swag.require(fct() == 12)
}

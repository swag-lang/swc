#global private

#test
{
    Swag.require(InlineRegressionBug8.scoreNameRecord(3, 10, 0x0409) == 70)
    Swag.require(InlineRegressionBug8.scoreNameRecord(3, 1, 0) == 55)
    Swag.require(InlineRegressionBug8.scoreNameRecord(0, 0, 0) == 30)
    Swag.require(InlineRegressionBug8.scoreNameRecord(1, 0, 0) == 10)
    Swag.require(InlineRegressionBug8.scoreNameRecord(2, 0, 0) == 0)
}

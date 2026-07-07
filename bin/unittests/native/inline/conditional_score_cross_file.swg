#global private

#test
{
    @assert(InlineRegressionBug8.scoreNameRecord(3, 10, 0x0409) == 70)
    @assert(InlineRegressionBug8.scoreNameRecord(3, 1, 0) == 55)
    @assert(InlineRegressionBug8.scoreNameRecord(0, 0, 0) == 30)
    @assert(InlineRegressionBug8.scoreNameRecord(1, 0, 0) == 10)
    @assert(InlineRegressionBug8.scoreNameRecord(2, 0, 0) == 0)
}

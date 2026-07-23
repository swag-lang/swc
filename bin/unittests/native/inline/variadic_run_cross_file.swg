#global private

const InlineRegressionBug14Value = #run InlineRegressionBug14.sum(1, 2, 3, 4)
#assert(InlineRegressionBug14Value == 10)

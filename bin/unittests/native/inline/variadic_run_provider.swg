#global internal

namespace InlineRegressionBug14
{
    #[Swag.Inline]
    func sum(values: s32...)->s32
    {
        var result = 0_s32
        for v in values
        {
            result += v
        }
        return result
    }
}

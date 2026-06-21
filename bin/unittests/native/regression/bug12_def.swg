#global moduleprivate

namespace InlineRegressionBug12
{
    #[Swag.Inline]
    func getInc()->func||()->s32
    {
        let x = 10

        return func|x|()->s32
        {
            x += 1
            return x
        }
    }
}

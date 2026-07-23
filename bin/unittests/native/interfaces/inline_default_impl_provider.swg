#global internal

namespace InlineRegressionBug16
{
    struct Implemented {}

    struct DefaultOnly {}

    interface ITest
    {
        #[Swag.Inline]
        mtd isImplemented()->bool
        {
            return false
        }
    }

    impl ITest for Implemented
    {
        mtd impl isImplemented()->bool
        {
            return true
        }
    }

    impl ITest for DefaultOnly {}
}

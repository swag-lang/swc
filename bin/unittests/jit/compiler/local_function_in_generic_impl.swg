#global internal
using Swag

namespace LocalFunctionInGenericImpl
{
    struct(T) Box
    {
        values: [3] T
    }

    impl Box
    {
        #[Swag.NoInline]
        mtd const countValues()->s64
        {
            var total = 0's64
            foreach value in .values
            {
                func keep(v: T)->T
                {
                    return v
                }

                if keep(value) == value do
                    total += 1
            }

            return total
        }
    }
}

#test
{
    let box = LocalFunctionInGenericImpl.Box's32{values: [1, 2, 3]}
    @assert(box.countValues() == 3)
}

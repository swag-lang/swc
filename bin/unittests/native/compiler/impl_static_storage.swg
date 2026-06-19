// impl-scoped variables need standalone storage even when accessed from compiler functions.
#global fileprivate
using Swag

namespace compiler_impl_static_storage
{
    struct Cache
    {
    }

    impl Cache
    {
        var values: [4] s32 = undefined

        #[Swag.Compiler]
        func seed(index: u8, value: s32)
        {
            values[index] = value
        }

        func get(index: u8)->s32
        {
            return values[index]
        }
    }

    #test
    {
        #run
        {
            Cache.seed(0, 7)
            Cache.seed(1, 9)
        }

        @assert(Cache.get(0) == 7)
        @assert(Cache.get(1) == 9)
    }
}

#global #[Swag.ExplicitNullability]
#global internal
using Swag

namespace ClosureGenericCallbackSupport
{
    struct ByteSet
    {
        values: [4] u8
        count:  u32
    }

    impl ByteSet
    {
        #[Swag.NoInline]
        mtd const contains(value: u8)->bool
        {
            for i in count
            {
                if values[i] == value do
                    return true
            }

            return false
        }
    }

    #[Swag.NoInline]
    func invokeUnary(value: u8, cb: func||(u8)->bool)->bool
    {
        return cb(value)
    }

    #[Swag.NoInline]
    func(T) invokeGeneric(value: T, cb: func||(T)->bool)->bool
    {
        return cb(value)
    }

    #[Swag.NoInline]
    func(T) allOf(values: const [..] T, cb: func||(T)->bool)->bool
    {
        for v in values
        {
            if !cb(v) do
                return false
        }

        return true
    }
}

#global private

// A method of a generic instance is analyzed on demand, outside the walk that opened its
// namespaces. Its body must still see what every enclosing namespace declares.
namespace Outer
{
    struct Marker
    {
        value: s32 = 7
    }

    namespace Inner
    {
        struct(T) Box
        {
            item: T
        }

        impl Box
        {
            mtd marker()->s32
            {
                let marker: Marker
                return marker.value
            }
        }
    }
}

namespace First.Second
{
    struct(T) Pair
    {
        left, right: T
    }

    impl Pair
    {
        mtd scaled()->T => (left + right) * Scale
    }
}

namespace First
{
    const Scale = 3
}

#test
{
    let box: Outer.Inner.Box!{s32}
    Swag.require(box.marker() == 7)

    let pair = First.Second.Pair!{s32}{1, 2}
    Swag.require(pair.scaled() == 9)
}

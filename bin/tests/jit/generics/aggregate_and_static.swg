#global fileprivate

struct(T) Pair
{
    first:  T
    second: T
}

func(T) pairFirst(value: Pair'T)->T
{
    return value.first
}

struct(T) Vector3
{
    x: T
    y: T
    z: T
}

impl Vector3
{
    func dot(a: const &Vector3'T, b: const &Vector3'T)->T
    {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }
}

#test
{
    let value = pairFirst({second: 2'u16, first: 1'u16})

    #assert(#typeof(value) == u16)
    @assert(value == 1'u16)
}

#test
{
    var a: Vector3's32 = {x: 1, y: 2, z: 3}
    var b: Vector3's32 = {x: 4, y: 5, z: 6}
    let d = Vector3's32.dot(&a, &b)

    #assert(#typeof(d) == s32)
    @assert(d == 32)
}

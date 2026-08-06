#global private

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

alias VectorAlias  = Vector3
alias VectorAlias2 = VectorAlias

func semaTest001()
{
    var a: VectorAlias2's32 = {x: 1, y: 2, z: 3}
    var b: VectorAlias2's32 = {x: 4, y: 5, z: 6}
    let d = VectorAlias2's32.dot(&a, &b)

    #assert(#typeof(d) == s32)
}

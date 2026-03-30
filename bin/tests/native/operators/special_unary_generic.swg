#global fileprivate

struct(T) IntUnaryBox
{
    value: T
}

impl IntUnaryBox
{
    func(op: string) opUnary(me)->IntUnaryBox'T
    {
        #if op == "+" do
            return {value: +me.value}
        #elif op == "-" do
            return {value: -me.value}
        #elif op == "~" do
            return {value: ~.value}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

struct(T) BoolUnaryBox
{
    value: T
}

impl BoolUnaryBox
{
    func(op: string) opUnary(me)->BoolUnaryBox'T
    {
        #if op == "!" do
            return {value: !me.value}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

struct(T) IntUnaryVec3
{
    x: T
    y: T
    z: T
}

impl IntUnaryVec3
{
    func(op: string) opUnary(me)->IntUnaryVec3'T
    {
        #if op == "+" do
            return {x: +me.x, y: +me.y, z: +me.z}
        #elif op == "-" do
            return {x: -me.x, y: -me.y, z: -me.z}
        #elif op == "~" do
            return {x: ~me.x, y: ~me.y, z: ~me.z}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

#test
{
    var value: IntUnaryBox'u32 = {value: 42}
    let pos = +value

    @assert(pos.value == 42)
}

#test
{
    var value: IntUnaryBox's32 = {value: 42}
    let neg = -value
    let inv = ~value

    @assert(neg.value == -42)
    @assert(inv.value == -43)
}

#test
{
    var value: BoolUnaryBox'bool = {value: false}
    let flipped = !value

    @assert(flipped.value)
}

#test
{
    var value: IntUnaryVec3'u64 = {x: 1, y: 2, z: 3}
    let pos = +value

    @assert(pos.x == 1)
    @assert(pos.y == 2)
    @assert(pos.z == 3)
}

#test
{
    var value: IntUnaryVec3's64 = {x: 1, y: -2, z: 3}
    let neg = -value
    let inv = ~value

    @assert(neg.x == -1)
    @assert(neg.y == 2)
    @assert(neg.z == -3)
    @assert(inv.x == -2)
    @assert(inv.y == 1)
    @assert(inv.z == -4)
}

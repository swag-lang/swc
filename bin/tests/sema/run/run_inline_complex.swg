#global fileprivate

//#[Swag.PrintMicro]
#[Swag.Optimize(false)]
#run
{
    let x = 1
    //@assert(false)
}

/*
struct Pair
{
    a: s32
    b: s32
}

struct Box
{
    left: Pair
    right: Pair
}

struct Payload
{
    values: [3] s32
    tag: u8
}

#[Swag.Inline]
func inlineMakePair(a: s32, b: s32)->Pair => Pair{a, b}

#[Swag.Inline]
func inlinePairEcho(pair: Pair)->Pair => pair

#[Swag.Inline]
func inlineMakeBox(a: s32, b: s32, c: s32, d: s32)->Box => Box{Pair{a, b}, Pair{c, d}}

#[Swag.Inline]
func inlineBoxEcho(box: Box)->Box => box

#[Swag.Inline]
func inlineArrayEcho(v: [3] s32)->[3] s32 => v

#[Swag.Inline]
func inlineMakePayload(a: s32, b: s32, c: s32, tag: u8 = 1)->Payload => Payload{[a, b, c], tag}

#[Swag.Inline]
func inlinePayloadEcho(payload: Payload)->Payload => payload

#run
{
    var p0 = inlineMakePair(20, 22)
    @assert(p0.a == 20)
    @assert(p0.b == 22)

    var p1 = inlinePairEcho(Pair{10, 32})
    @assert(p1.a == 10)
    @assert(p1.b == 32)

    var p2 = inlinePairEcho(pair: Pair{41, 1})
    @assert(p2.a == 41)
    @assert(p2.b == 1)

    var b0 = inlineMakeBox(10, 11, 9, 12)
    @assert(b0.left.a == 10)
    @assert(b0.left.b == 11)
    @assert(b0.right.a == 9)
    @assert(b0.right.b == 12)

    var b1 = inlineBoxEcho(Box{Pair{1, 2}, Pair{3, 4}})
    @assert(b1.left.a == 1)
    @assert(b1.left.b == 2)
    @assert(b1.right.a == 3)
    @assert(b1.right.b == 4)

    var a0 = inlineArrayEcho([10, 20, 12])
    @assert(a0[0] == 10)
    @assert(a0[1] == 20)
    @assert(a0[2] == 12)

    var a1: [3] s32 = [5, 15, 22]
    var a2 = inlineArrayEcho(a1)
    @assert(a2[0] == 5)
    @assert(a2[1] == 15)
    @assert(a2[2] == 22)

    var pay0 = inlineMakePayload(10, 20, 12, 0)
    @assert(pay0.values[0] == 10)
    @assert(pay0.values[1] == 20)
    @assert(pay0.values[2] == 12)
    @assert(pay0.tag == 0)

    var pay1 = inlineMakePayload(13, 14, 15)
    @assert(pay1.values[0] == 13)
    @assert(pay1.values[1] == 14)
    @assert(pay1.values[2] == 15)
    @assert(pay1.tag == 1)

    var pay2 = inlinePayloadEcho(Payload{[20, 21, 22], 2})
    @assert(pay2.values[0] == 20)
    @assert(pay2.values[1] == 21)
    @assert(pay2.values[2] == 22)
    @assert(pay2.tag == 2)
}
*/
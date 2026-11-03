// 

#global private

struct Pair
{
    a: s32
    b: s32
}

struct Box
{
    left:  Pair
    right: Pair
}

struct Payload
{
    values: [3] s32
    tag:    u8
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

#test
{
    var p0 = inlineMakePair(20, 22)
    Swag.require(p0.a == 20)
    Swag.require(p0.b == 22)

    var a0 = inlineArrayEcho([10, 20, 12])
    Swag.require(a0[0] == 10)
    Swag.require(a0[1] == 20)
    Swag.require(a0[2] == 12)

    var a1: [3] s32 = [5, 15, 22]
    var a2 = inlineArrayEcho(a1)
    Swag.require(a2[0] == 5)
    Swag.require(a2[1] == 15)
    Swag.require(a2[2] == 22)

    var pay0 = inlineMakePayload(10, 20, 12, 0)
    Swag.require(pay0.values[0] == 10)
    Swag.require(pay0.values[1] == 20)
    Swag.require(pay0.values[2] == 12)
    Swag.require(pay0.tag == 0)

    var pay1 = inlineMakePayload(13, 14, 15)
    Swag.require(pay1.values[0] == 13)
    Swag.require(pay1.values[1] == 14)
    Swag.require(pay1.values[2] == 15)
    Swag.require(pay1.tag == 1)

    var pay2 = inlinePayloadEcho(Payload{[20, 21, 22], 2})
    Swag.require(pay2.values[0] == 20)
    Swag.require(pay2.values[1] == 21)
    Swag.require(pay2.values[2] == 22)
    Swag.require(pay2.tag == 2)
}

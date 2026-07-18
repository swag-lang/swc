#global private
#global #[Swag.ExplicitNullability]

struct InitCapturePair
{
    left:  s32
    right: s32
}

struct InitCaptureBox
{
    value: s32
}

struct InitCaptureOwner
{
    bias: s32
}

alias InitCaptureNullary = func||()->s32

impl InitCaptureOwner
{
    mtd makeCallback()->InitCaptureNullary
    {
        return func|self = me, saved = me.bias + 1|()->s32 { return self.bias + saved }
    }
}

func semaTest001()
{
    let base = 10
    let step = 4
    let cb: InitCaptureNullary = func|sum = base + step|()->s32 { return sum }
    #assert(#typeof(cb) == InitCaptureNullary)
}

func semaTest002()
{
    let pair = InitCapturePair{left: 2, right: 5}
    let cb: InitCaptureNullary = func|leftValue = pair.left, rightValue = pair.right|()->s32 { return leftValue * 10 + rightValue }
    #assert(#typeof(cb) == InitCaptureNullary)
}

func semaTest003()
{
    var box = InitCaptureBox{value: 8}
    let cb: InitCaptureNullary = func|&current = box.value|()->s32 { current += 1; return current }
    #assert(#typeof(cb) == InitCaptureNullary)
}

func semaTest004()
{
    var owner = InitCaptureOwner{bias: 6}
    let cb = owner.makeCallback()
    #assert(#typeof(cb) == InitCaptureNullary)
}

func semaTest005()
{
    let base = 0x10
    let bit  = 0x04
    let cb: InitCaptureNullary = func|mask = base | (bit)|()->s32 { return mask }
    #assert(#typeof(cb) == InitCaptureNullary)
}

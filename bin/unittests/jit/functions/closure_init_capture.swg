#global private

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
    value: s32
}

impl InitCaptureOwner
{
    mtd makeCallback()->func||()->s32
    {
        return func|self = me, saved = me.value|()->s32
        {
            self.value += 1
            return saved * 10 + self.value
        }
    }
}

#test
{
    var base = 2
    var step = 5
    let cb: func||()->s32 = func|var sum = base + step|()->s32
    {
        sum += 1
        return sum
    }

    base = 100
    Swag.require(cb() == 8)
    Swag.require(cb() == 9)
}

#test
{
    let a = InitCaptureBox{value: 3}
    let b = InitCaptureBox{value: 7}
    let cb: func||()->s32 = func|left = a.value, right = b.value|()->s32 { return left * 10 + right }
    Swag.require(cb() == 37)
}

#test
{
    var owner = InitCaptureOwner{value: 4}
    let cb    = owner.makeCallback()
    Swag.require(cb() == 45)
    Swag.require(cb() == 46)
    Swag.require(owner.value == 6)
}

#test
{
    var value = 10
    let cb: func||()->s32 = func|&current = value|()->s32
    {
        current += 3
        return current
    }

    Swag.require(cb() == 13)
    Swag.require(value == 13)
    value = 20
    Swag.require(cb() == 23)
}

#test
{
    var pair = InitCapturePair{left: 1, right: 2}
    let cb: func||()->s32 = func|&left = pair.left, right = pair.right|()->s32
    {
        left += right
        return left
    }

    Swag.require(cb() == 3)
    Swag.require(cb() == 5)
    Swag.require(pair.left == 5)
    Swag.require(pair.right == 2)
}

#test
{
    let base = 0x10
    let bit  = 0x04
    let cb: func||()->s32 = func|mask = base | (bit)|()->s32 { return mask }
    Swag.require(cb() == 0x14)
}

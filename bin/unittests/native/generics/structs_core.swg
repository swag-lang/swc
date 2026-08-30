#global private

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

func(T, N: s32) bufferCount(buffer: Buffer'(T, N))->s32 => N
func(T) unbox(box: Box'T)->T => box.value

func sumFour(buffer: Buffer'(s32, 4))->s32
{
    return buffer.values[0] + buffer.values[1] + buffer.values[2] + buffer.values[3]
}

func(T) makeBox(value: T)->Box'T
{
    return {value: value}
}

func(T) boxValue(box: Box'T)->T => box.value

#test
{
    let stringBox: Box'string = {value: "swag"}
    let intBox:    Box's32    = {value: 42}
    let boolBox:   Box'bool   = {value: true}
    let floatBox:  Box'f64    = {value: 3.14}

    Swag.assert(stringBox.value == "swag")
    Swag.assert(intBox.value == 42)
    Swag.assert(boolBox.value == true)
    Swag.assert(floatBox.value == 3.14)
}

#test
{
    let buffer: Buffer'(s32, 4) = {values: [1, 2, 3, 4]}
    Swag.assert(buffer.values[0] == 1)
    Swag.assert(buffer.values[3] == 4)
    Swag.assert(bufferCount'(s32, 4)(buffer) == 4)
    Swag.assert(sumFour(buffer) == 10)

    let small: Buffer'(u8, 2) = {values: [10'u8, 20]}
    Swag.assert(small.values[0] == 10'u8)
    Swag.assert(small.values[1] == 20'u8)
}

#test
{
    let b = makeBox(42)
    Swag.assert(b.value == 42)

    let b2 = makeBox("hello")
    Swag.assert(b2.value == "hello")

    let b3 = makeBox(true)
    Swag.assert(b3.value == true)

    let nested = makeBox(makeBox(7))
    Swag.assert(nested.value.value == 7)
}

#test
{
    let b: Box's32 = {value: 99}
    Swag.assert(unbox(b) == 99)
    Swag.assert(boxValue(b) == 99)

    let s: Box'string = {value: "works"}
    Swag.assert(unbox(s) == "works")
    Swag.assert(boxValue(s) == "works")
}

#test
{
    {
        struct(T) LocalBox
        {
            value: T
        }

        let intBox:  LocalBox's32  = {value: 11}
        let boolBox: LocalBox'bool = {value: false}

        Swag.assert(intBox.value == 11)
        Swag.assert(boolBox.value == false)
    }
    {
        struct(T, N: s32) LocalBuffer
        {
            values: [N] T
        }

        let buffer: LocalBuffer'(u16, 2) = {values: [5'u16, 9]}
        Swag.assert(buffer.values[0] == 5'u16)
        Swag.assert(buffer.values[1] == 9'u16)
    }
}

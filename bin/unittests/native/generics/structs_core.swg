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

    Swag.require(stringBox.value == "swag")
    Swag.require(intBox.value == 42)
    Swag.require(boolBox.value == true)
    Swag.require(floatBox.value == 3.14)
}

#test
{
    let buffer: Buffer'(s32, 4) = {values: [1, 2, 3, 4]}
    Swag.require(buffer.values[0] == 1)
    Swag.require(buffer.values[3] == 4)
    Swag.require(bufferCount'(s32, 4)(buffer) == 4)
    Swag.require(sumFour(buffer) == 10)

    let small: Buffer'(u8, 2) = {values: [10'u8, 20]}
    Swag.require(small.values[0] == 10'u8)
    Swag.require(small.values[1] == 20'u8)
}

#test
{
    let b = makeBox(42)
    Swag.require(b.value == 42)

    let b2 = makeBox("hello")
    Swag.require(b2.value == "hello")

    let b3 = makeBox(true)
    Swag.require(b3.value == true)

    let nested = makeBox(makeBox(7))
    Swag.require(nested.value.value == 7)
}

#test
{
    let b: Box's32 = {value: 99}
    Swag.require(unbox(b) == 99)
    Swag.require(boxValue(b) == 99)

    let s: Box'string = {value: "works"}
    Swag.require(unbox(s) == "works")
    Swag.require(boxValue(s) == "works")
}

#test
{
    scope
    {
        struct(T) LocalBox
        {
            value: T
        }

        let intBox:  LocalBox's32  = {value: 11}
        let boolBox: LocalBox'bool = {value: false}

        Swag.require(intBox.value == 11)
        Swag.require(boolBox.value == false)
    }
    scope
    {
        struct(T, N: s32) LocalBuffer
        {
            values: [N] T
        }

        let buffer: LocalBuffer'(u16, 2) = {values: [5'u16, 9]}
        Swag.require(buffer.values[0] == 5'u16)
        Swag.require(buffer.values[1] == 9'u16)
    }
}

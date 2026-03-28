#global fileprivate

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
    let intBox: Box's32 = {value: 42}
    let boolBox: Box'bool = {value: true}
    let floatBox: Box'f64 = {value: 3.14}

    @assert(stringBox.value == "swag")
    @assert(intBox.value == 42)
    @assert(boolBox.value == true)
    @assert(floatBox.value == 3.14)
}

#test
{
    let buffer: Buffer'(s32, 4) = {values: [1, 2, 3, 4]}
    @assert(buffer.values[0] == 1)
    @assert(buffer.values[3] == 4)
    @assert(bufferCount'(s32, 4)(buffer) == 4)
    @assert(sumFour(buffer) == 10)

    let small: Buffer'(u8, 2) = {values: [10'u8, 20]}
    @assert(small.values[0] == 10'u8)
    @assert(small.values[1] == 20'u8)
}

#test
{
    let b = makeBox(42)
    @assert(b.value == 42)

    let b2 = makeBox("hello")
    @assert(b2.value == "hello")

    let b3 = makeBox(true)
    @assert(b3.value == true)

    let nested = makeBox(makeBox(7))
    @assert(nested.value.value == 7)
}

#test
{
    let b: Box's32 = {value: 99}
    @assert(unbox(b) == 99)
    @assert(boxValue(b) == 99)

    let s: Box'string = {value: "works"}
    @assert(unbox(s) == "works")
    @assert(boxValue(s) == "works")
}

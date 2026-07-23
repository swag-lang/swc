#global private

func(T) identity(value: T)->T                        => value
func(T) keepDeducedType(value, low, high: T)->T      => value
func(T) doubleLeftLiteral(value: T)                  => 2 * value
func(T = s32, V = s32) mixedMultiply(a: T, b: V)     => a * b
func(T = s32) defaultTypeValue()->T                  => 42
func(N: s32 = 3) defaultConstValue()->s32            => N
func(T, N: s32) arrayCount(values: [N] T)->s32       => N
func(T, N: s32 = 2) partialCount(values: [N] T)->s32 => N

struct(T, N: s32) Buffer
{
    values: [N] T
}

func(T, N: s32) bufferCount(buffer: Buffer'(T, N))->s32 => N

func genericFunctionMakeS32()->s32 => 42
func genericFunctionConsumeS32(value: s32) {}
func genericFunctionS32ToBool(value: s32)->bool => value == 42

func(T) callGenericFactory(factory: func()->T)->T
{
    return factory()
}

func(T) acceptGenericConsumer(consumer: func(T))
{
    consumer(42)
}

func(T, U) applyGenericMapper(mapper: func(T)->U, value: T)->U
{
    return mapper(value)
}

func(T) genericVariadicFirst(values: T...)->T
{
    return values[0]
}

func(T) genericVariadicAfterHead(head: s32, values: T...)->T
{
    return values[1]
}

func(T) genericVariadicForward(values: T...)->T
{
    return genericVariadicFirst(values)
}

func(T) genericDefaultArgument(value: T = 42)->T
{
    return value
}

func(T) genericDefaultArray(values: [2] T = [1'u16, 2'u16])->T
{
    return values[0]
}

func(T) genericDefaultMatrix(values: [2, 2] T = [[1'u8, 2'u8], [3'u8, 4'u8]])->T
{
    return values[1][0]
}

func(T) genericDefaultSlice(values: const [..] T = [1'u16, 2'u16])->T
{
    return values[0]
}

func(T) genericDefaultStringSlice(values: const [..] T = "abc")->T
{
    return values[0]
}

func(T) genericSliceFirst(values: const [..] T)->T
{
    return values[0]
}

func(T, N: s32) genericDefaultBuffer(buffer: Buffer'(T, N) = {values: [1'u16, 2'u16, 3'u16]})->s32
{
    return N
}

func(U, M: s32) genericDefaultRenamedBuffer(buffer: Buffer'(U, M) = {values: [1'u8, 2'u8]})->U
{
    return buffer.values[0]
}

func(T) genericAnonymousField(value: struct { field: T })->T
{
    return value.field
}

func(T) genericDefaultAnonymousField(value: struct { field: T } = {field: 12'u16})->T
{
    return value.field
}

func semaTest001()
{
    #assert(identity'(s32)(42) == 42)
    #assert(identity'(bool)(true) == true)
    #assert(identity(12'u16) == 12'u16)
    #assert(doubleLeftLiteral'(s32)(21) == 42)
    #assert(doubleLeftLiteral(2.5'f32) == 5.0'f32)
    let mixed = mixedMultiply(1's32, 2'f32)
    #assert(#typeof(mixed) == f32)
}

func semaTest002()
{
    #assert(#typeof(defaultTypeValue()) == s32)
    #assert(defaultTypeValue() == 42)
    #assert(#typeof(defaultTypeValue'(f64)()) == f64)
    #assert(defaultTypeValue'(f64)() == 42.0)
}

func semaTest003()
{
    #assert(defaultConstValue() == 3)
    #assert(defaultConstValue'(10)() == 10)
}

func semaTest004()
{
    let values: [4] u16 = [10'u16, 20, 30, 40]
    let pair:   [2] s32 = [1, 2]

    #assert(arrayCount'(u16, 4)(values) == 4)
    #assert(arrayCount(values) == 4)
    #assert(partialCount'(s32)(pair) == 2)
}

func semaTest005()
{
    func(T) localDouble(value: T)                         => 2 * value
    func(T = s32, V = s32) localMixedMultiply(a: T, b: V) => a * b

    #assert(localDouble'(s32)(21) == 42)
    #assert(localDouble(2.5'f32) == 5.0'f32)
    let localMixed = localMixedMultiply(1's32, 2'f32)
    #assert(#typeof(localMixed) == f32)
}

func semaTest006()
{
    let buffer: Buffer'(u16, 4)

    #assert(#typeof(buffer.values) == #type [4] u16)
    #assert(bufferCount'(u16, 4)(buffer) == 4)
}

func semaTest007()
{
    let made = callGenericFactory(&genericFunctionMakeS32)
    #assert(#typeof(made) == s32)

    acceptGenericConsumer(&genericFunctionConsumeS32)

    let mapped = applyGenericMapper(&genericFunctionS32ToBool, 42)
    #assert(#typeof(mapped) == bool)
}

func semaTest008()
{
    let first = genericVariadicFirst(1'u16, 2'u16)
    #assert(#typeof(first) == u16)

    let tail = genericVariadicAfterHead(10, 3'u8, 4'u8)
    #assert(#typeof(tail) == u8)

    let forwarded = genericVariadicForward(5's64, 6's64)
    #assert(#typeof(forwarded) == s64)
}

func semaTest009()
{
    let value = genericDefaultArgument()
    #assert(#typeof(value) == s32)
}

func semaTest010()
{
    let value = genericDefaultArray()
    #assert(#typeof(value) == u16)
}

func semaTest011()
{
    let value = genericDefaultMatrix()
    #assert(#typeof(value) == u8)
}

func semaTest012()
{
    let value = genericDefaultSlice()
    #assert(#typeof(value) == u16)
}

func semaTest013()
{
    let value = genericDefaultStringSlice()
    #assert(#typeof(value) == u8)
}

func semaTest014()
{
    let value = genericSliceFirst("abc")
    #assert(#typeof(value) == u8)
}

func semaTest015()
{
    #assert(genericDefaultBuffer() == 3)
}

func semaTest016()
{
    let value = genericDefaultRenamedBuffer()
    #assert(#typeof(value) == u8)
}

func semaTest017()
{
    let value = genericAnonymousField(struct { field: u16 }{field: 12'u16})
    #assert(#typeof(value) == u16)
}

func semaTest018()
{
    let value = genericDefaultAnonymousField()
    #assert(#typeof(value) == u16)
}

func semaTest019()
{
    let value: f32 = 0.5
    let high:  s32 = 10
    let result = keepDeducedType(value, 0, high)
    #assert(#typeof(result) == f32)
}

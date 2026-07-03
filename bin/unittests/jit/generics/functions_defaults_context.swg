#global private

struct(T, N: s32) Buffer
{
    values: [N] T
}

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

#test
{
    let made = callGenericFactory(&genericFunctionMakeS32)
    let mapped = applyGenericMapper(&genericFunctionS32ToBool, 42)

    #assert(#typeof(made) == s32)
    #assert(#typeof(mapped) == bool)
    @assert(made == 42)
    @assert(mapped)
}

#test
{
    acceptGenericConsumer(&genericFunctionConsumeS32)

    let first = genericVariadicFirst(1'u16, 2'u16)
    let tail = genericVariadicAfterHead(10, 3'u8, 4'u8)
    let forwarded = genericVariadicForward(5's64, 6's64)

    #assert(#typeof(first) == u16)
    #assert(#typeof(tail) == u8)
    #assert(#typeof(forwarded) == s64)
    @assert(first == 1'u16)
    @assert(tail == 4'u8)
    @assert(forwarded == 5's64)
}

#test
{
    let value = genericDefaultArgument()
    let arrayValue = genericDefaultArray()
    let matrixValue = genericDefaultMatrix()
    let sliceValue = genericDefaultSlice()
    let stringValue = genericDefaultStringSlice()
    let firstChar = genericSliceFirst("abc")

    #assert(#typeof(value) == s32)
    #assert(#typeof(arrayValue) == u16)
    #assert(#typeof(matrixValue) == u8)
    #assert(#typeof(sliceValue) == u16)
    #assert(#typeof(stringValue) == u8)
    #assert(#typeof(firstChar) == u8)
    @assert(value == 42)
    @assert(arrayValue == 1'u16)
    @assert(matrixValue == 3'u8)
    @assert(sliceValue == 1'u16)
    @assert(stringValue == "a"[0])
    @assert(firstChar == "a"[0])
}

#test
{
    let count = genericDefaultBuffer()
    let renamed = genericDefaultRenamedBuffer()
    let field = genericAnonymousField(struct { field: u16 }{field: 12'u16})
    let defaultField = genericDefaultAnonymousField()

    #assert(#typeof(renamed) == u8)
    #assert(#typeof(field) == u16)
    #assert(#typeof(defaultField) == u16)
    @assert(count == 3)
    @assert(renamed == 1'u8)
    @assert(field == 12'u16)
    @assert(defaultField == 12'u16)
}

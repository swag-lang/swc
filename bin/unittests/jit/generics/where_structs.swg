#global private

alias Real64 = f64

struct(T) FloatPoint
    where T == f32 or T == f64
{
    x, y: T
}

struct(T, N: s32) FixedNumbers
    where N > 0
    where T == s32 or T == s64
{
    values: [N] T
}

struct(T, Rows: s32, Cols: s32) DenseMatrix
    where
{
    if Rows > 0 and Cols > 0 and (T == f32 or T == f64) do
        return true
    return false
}
{
    data: [Rows * Cols] T
}

struct(T = Real64) DefaultFloatBox
    where T == f32 or T == f64
{
    value: T
}

struct(T, U = T) TwinValue
    where T == U
{
    first:  T
    second: U
}

struct(T, N: s32 = 4) SmallVector
    where N > 0
    where N <= 4
{
    values: [N] T
}

struct(T) FloatSegment
    where T == f32 or T == f64
{
    start: FloatPoint'T
    stop:  FloatPoint'T
}

struct(T, Rows: s32, Cols: s32 = Rows) SquareMatrix
    where Rows > 0
    where Cols > 0
    where Rows == Cols
    where T == f32 or T == f64
{
    data: [Rows * Cols] T
}

struct(T, Min: s32, Max: s32) BoundedRange
    where Min <= Max
    where T == s32 or T == s64 or T == f32 or T == f64
{
    min: T
    max: T
}

struct(T, Count: s32) FloatHistory
    where
{
    if Count >= 2 and (T == f32 or T == f64) do
        return true
    return false
}
{
    values: [Count] T
}

#test
{
    let point:      FloatPoint'f64 = {x: 1.0, y: 2.0}
    let fixed:      FixedNumbers'(s64, 3) = {values: [10, 20, 30]}
    let defaultBox: DefaultFloatBox = {value: 4.0}
    let twin:       TwinValue's32 = {first: 1, second: 2}

    #assert(#typeof(point.x) == f64)
    #assert(#typeof(fixed.values[0]) == s64)
    #assert(#typeof(defaultBox.value) == Real64)
    #assert(#typeof(twin.second) == s32)
    @assert(point.x == 1.0'f64)
    @assert(point.y == 2.0'f64)
    @assert(fixed.values[2] == 30's64)
    @assert(defaultBox.value == 4.0'f64)
    @assert(twin.first == 1)
    @assert(twin.second == 2)
}

#test
{
    let compact: SmallVector'(u16, 2) = {values: [10'u16, 20]}
    let small:   SmallVector'u8 = {values: [1'u8, 2, 3, 4]}
    let segment: FloatSegment'f32 = {start: {x: 0.0, y: 1.0}, stop: {x: 2.0, y: 3.0}}
    var matrix:  DenseMatrix'(f32, 2, 3)

    matrix.data[0] = 1.0
    matrix.data[5] = 6.0

    #assert(#typeof(compact.values) == #type [2] u16)
    #assert(#typeof(small.values) == #type [4] u8)
    #assert(#typeof(segment.start.x) == f32)
    #assert(#typeof(matrix.data[0]) == f32)
    @assert(compact.values[0] == 10'u16)
    @assert(compact.values[1] == 20'u16)
    @assert(small.values[3] == 4'u8)
    @assert(segment.stop.y == 3.0'f32)
    @assert(matrix.data[0] == 1.0'f32)
    @assert(matrix.data[5] == 6.0'f32)
}

#test
{
    let square:  SquareMatrix'(f32, 2) = {data: [1.0'f32, 2.0, 3.0, 4.0]}
    let safe:    BoundedRange'(f32, 0, 100) = {min: 10.0, max: 90.0}
    let history: FloatHistory'(f64, 3) = {values: [1.0'f64, 2.0, 3.0]}

    #assert(#typeof(square.data) == #type [4] f32)
    #assert(#typeof(safe.min) == f32)
    #assert(#typeof(history.values[1]) == f64)
    @assert(square.data[3] == 4.0'f32)
    @assert(safe.min == 10.0'f32)
    @assert(safe.max == 90.0'f32)
    @assert(history.values[0] == 1.0'f64)
    @assert(history.values[2] == 3.0'f64)
}

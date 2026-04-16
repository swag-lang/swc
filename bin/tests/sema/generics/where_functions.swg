#global fileprivate

var runtimeFlag: bool
alias Real32 = f32

struct(A, B) Pair
{
    first: A
    second: B
}

#[Swag.Overload]
func(T) kind(value: T)->u8
    where T == f32 or T == f64
{
    return 1
}

#[Swag.Overload]
func(T) kind(value: T)->u8
    where T == s32 or T == s64
{
    return 2
}

func(T) onlyFloat(value: T)->T
    where T == f32 or T == f64
{
    return value
}

func(T) onlyIntegersBlock(value: T)->T
    where
    {
        if T == s32 or T == s64 do
            return true
        return false
    }
{
    return value
}

func(T, N: s32) head(values: [N] T)->T
    where N > 0
    where T == s32 or T == s64
{
    return values[0]
}

func(N: s32) mustBePositive()->s32
    where N > 0
{
    return N
}

func(T = Real32) defaultFloatValue()->T
    where T == f32 or T == f64
{
    return cast(T) 2
}

func(T, U = T) sameTypePair(left: T, right: U)->U
    where T == U
{
    return right
}

func(T, U = T) sameTypeBlock(left: T, right: U)->bool
    where
    {
        if T == U do
            return true
        return false
    }
{
    return true
}

func(T, U) secondIfLeftIsSigned(pair: Pair'(T, U))->U
    where T == s32 or T == s64
{
    return pair.second
}

func(T, N: s32 = 4) fixedTail(values: [N] T)->T
    where N >= 2
{
    return values[N - 1]
}

func(T) badTypeExpr(value: T)->T
    where 1
{
    return value
}

func(T) badTypeBlock(value: T)->T
    where
    {
        return 1
    }
{
    return value
}

func(T) badConstExpr(value: T)->T
    where runtimeFlag
{
    return value
}

struct(T) Wrapper
{
    value: T
}

impl Wrapper
{
    func(U) pairValue(const me, other: U)->U
        where T == f32 and U == s32
    {
        return other
    }

    func(U, Count: s32) repeatValue(const me, other: U)->U
        where
        {
            if T == f32 and U == s32 and Count > 0 do
                return true
            return false
        }
    {
        return other
    }

    func(U = T) mirrorType(const me, other: U)->U
        where T == U
    {
        return other
    }

    func copyIfFloat(const me)->T
        where T == f32 or T == f64
    {
        return me.value
    }
}

struct(T, Count: s32) Window
{
    values: [Count] T
}

impl Window
{
    func(const Index: s32) at(const me)->T
        where Index >= 0
        where Index < Count
    {
        return me.values[Index]
    }

    func(U = T) sameSample(const me, other: U)->U
        where Count > 0
        where T == U
    {
        return other
    }

    func firstIfFloat(const me)->T
        where Count >= 2
        where T == f32 or T == f64
    {
        return me.values[0]
    }
}

#test
{
    @assert(kind(1.0'f32) == 1)
    @assert(kind(1's64) == 2)
    @assert(onlyFloat(1.0'f64) == 1.0'f64)
    @assert(onlyIntegersBlock(12's32) == 12)

    let values: [3] s32 = [5, 6, 7]
    let fixed: [4] u8 = [1'u8, 2, 3, 4]
    @assert(head(values) == 5)
    @assert(mustBePositive'3() == 3)
    @assert(defaultFloatValue() == 2.0'f32)
    @assert(defaultFloatValue'(f64)() == 2.0'f64)
    @assert(fixedTail(fixed) == 4'u8)

    @assert(sameTypePair(1's32, 2's32) == 2)
    @assert(sameTypePair'(f64)(1.0'f64, 2.0'f64) == 2.0'f64)
    @assert(sameTypeBlock(1.5'f32, 2.5'f32))

    let signedPair: Pair'(s32, string) = {first: 7, second: "ok"}
    @assert(secondIfLeftIsSigned(signedPair) == "ok")

    let floatBox: Wrapper'f32 = {value: 1.5}
    @assert(floatBox.pairValue's32(99) == 99)
    @assert(floatBox.repeatValue'(s32, 2)(123) == 123)
    @assert(floatBox.mirrorType(2.5'f32) == 2.5'f32)
    @assert(floatBox.copyIfFloat() == 1.5'f32)

    let floatWindow: Window'(f32, 3) = {values: [10.0'f32, 20.0, 30.0]}
    let intWindow: Window'(s32, 3) = {values: [1, 2, 3]}
    @assert(floatWindow.at'1() == 20.0'f32)
    @assert(intWindow.at'2() == 3)
    @assert(floatWindow.sameSample(77.0'f32) == 77.0'f32)
    @assert(intWindow.sameSample(9's32) == 9)
    @assert(floatWindow.firstIfFloat() == 10.0'f32)
}

#test
{
    onlyFloat(1's32) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    onlyIntegersBlock(1.0'f32) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    kind(true) // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    defaultFloatValue'(s32)() // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    sameTypePair(1's32, true) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    sameTypeBlock(1's32, 2.0'f32) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let nonSigned: Pair'(bool, string) = {first: true, second: "bad"}
    secondIfLeftIsSigned(nonSigned) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let tiny: [1] u8 = [9'u8]
    fixedTail'(u8, 1)(tiny) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    badTypeExpr(1's32) // swc-expected-error {{sema_err_function_where_not_bool}}
}

#test
{
    badTypeBlock(1's32) // swc-expected-error {{sema_err_function_where_not_bool}}
}

#test
{
    badConstExpr(1's32) // swc-expected-error {{sema_err_function_where_not_const}}
}

#test
{
    mustBePositive'0() // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let intBox: Wrapper's32 = {value: 7}
    intBox.pairValue's32(99) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let intBox: Wrapper's32 = {value: 7}
    intBox.copyIfFloat() // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let floatBox: Wrapper'f32 = {value: 1.5}
    floatBox.mirrorType's64(99's64) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let floatBox: Wrapper'f32 = {value: 1.5}
    floatBox.repeatValue'(s32, 0)(99) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let floatWindow: Window'(f32, 3) = {values: [10.0'f32, 20.0, 30.0]}
    floatWindow.at'3() // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let intWindow: Window'(s32, 3) = {values: [1, 2, 3]}
    intWindow.firstIfFloat() // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let floatWindow: Window'(f32, 3) = {values: [10.0'f32, 20.0, 30.0]}
    floatWindow.sameSample's64(4's64) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    let shortWindow: Window'(f32, 1) = {values: [9.0'f32]}
    shortWindow.firstIfFloat() // swc-expected-error {{sema_err_function_where_failed}}
}

#global fileprivate

enum CompressionLevel: u32
{
    NoCompression
    BestSpeed
}

func(T) minLike(x, y: T)->T => x
func minLike(x, y: u32)->u32 => x

#test
{
    minLike(10'u32, CompressionLevel.BestSpeed) // swc-expected-error {{sema_err_generic_function_instantiation_failed}}
}

func(const N: s32) zipLike(lhs: [N] s32, rhs: [N] s32) {}
func zipLike(lhs, rhs: s32) {}

#test
{
    const lhs: [2] s32 = [1, 2]
    const rhs: [3] s32 = [3, 4, 5]
    zipLike(lhs, rhs) // swc-expected-error {{sema_err_generic_function_instantiation_failed}}
}

func(T) ping()->s32 => 1
func ping(value: s32)->s32 => value

#test
{
    ping() // swc-expected-error {{sema_err_generic_function_instantiation_failed}}
}

func(T) severityLike(value: T)->u8
    where T == s32 or T == s64
{
    return 1
}

func severityLike(value: bool)->u8 => 0

#test
{
    severityLike(1.0) // swc-expected-error {{sema_err_generic_function_instantiation_failed}}
}

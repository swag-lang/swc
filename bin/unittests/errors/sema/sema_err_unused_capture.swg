#global private

func run(cb: func||()->s32)->s32 => cb()

func captures()->s32
{
    let a     = 1
    let b     = 2
    var total = run(func|a|()->s32 { return a })
    total += run(func|a, b|()->s32 { return a })     // swc-expected-error {{sema_err_unused_capture}}
    return total
}

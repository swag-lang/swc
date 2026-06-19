#global fileprivate

struct Capture24
{
    a, b, c: u64
}

#test
{
    let a: Capture24 = {a: 1, b: 2, c: 3}
    let b: Capture24 = {a: 4, b: 5, c: 6}
    let c: Capture24 = {a: 7, b: 8, c: 9}
    let tooBig = func|a, b, c|() {} // swc-expected-error {{sema_err_closure_capture_too_large}}
}

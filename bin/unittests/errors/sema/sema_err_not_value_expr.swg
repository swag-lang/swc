#global private

var a: s32 = 0
var b: #decltype(a) = 5
#assert(#typeof(b) == s32)

var c: #decltype(10) = 2
#assert(#typeof(c) == s32)

var d: #decltype(10'u8 + 20's32) = 7
#assert(#typeof(d) == s32)

var e: #decltype(s32) = 9
#assert(#typeof(e) == s32)

namespace N {}
var bad: #decltype(N) = 0     // swc-expected-error {{sema_err_not_value_expr}}

func callbackTarget()->s32 => 42
func acceptCallback(callback: func()->s32)->s32 => callback()

#test
{
    // A function declaration needs '&' to supply a callback value.
    discard acceptCallback(callback: callbackTarget)     // swc-expected-error {{sema_err_not_value_expr}}
}

#test
{
    discard acceptCallback(callbackTarget)     // swc-expected-error {{sema_err_not_value_expr}}
}

#global fileprivate

// Regression: a same-name function declared at a closer scope tier (here the module
// scope) must not shadow better-ranked overloads brought in through a `using`
// directive. Calling `pick` with an f32 argument has to select the exact `f32`
// overload from `N`, not the module-level `f64` one that merely sits at a higher
// priority tier. Before the fix the higher-priority `f64` overload won outright and
// the call resolved to `f64` (this exact shape broke unqualified `Core.Math.cos`/`sin`
// on f32 arguments in the example scripts).

func pick(x: f64)->f64 => x

namespace N
{
    func pick(x: f32)->f32 => x
    func pick(x: f64)->f64 => x
}

using N

func semaTest001()
{
    var a: f32 = 1.0
    #assert(#typeof(pick(a)) == f32)

    var b: f64 = 1.0
    #assert(#typeof(pick(b)) == f64)
}

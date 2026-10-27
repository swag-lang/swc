#global private

struct ErasedBase { x: s32 }
struct ErasedView { using base: ErasedBase; progress: f32 }
struct ErasedOther { using base: ErasedBase; count: s32 }
struct ErasedLate { a: s32; using base: ErasedBase }

func(T is ErasedBase) erasedRead(target: *T)->s32 => target.x
func(T is ErasedBase) erasedNotify(target: *T, notify: func||(*T)) { notify(target) }
func(T is s32) erasedScalar(_: *T) {}     // swc-expected-error {{sema_err_erased_param_bound_not_struct}}
struct(U is ErasedBase) ErasedBox { item: *U? }     // swc-expected-error {{sema_err_erased_param_in_struct}}

#test
{
    var shifted: ErasedLate
    discard erasedRead(&shifted)     // swc-expected-error {{sema_err_erased_param_not_bound}}
}

#test
{
    var value = 1's32
    discard erasedRead(&value)     // swc-expected-error {{sema_err_erased_param_not_struct}}
}

#test
{
    var value = 1's32
    erasedScalar(&value)
}

#test
{
    var box: ErasedBox'ErasedBase
    box.item = null
}

// A callback typed with another struct than the target cannot be read through the bound.
#test
{
    var view: ErasedView
    erasedNotify(&view, func(other: *ErasedOther) { other.count = 1 })     // swc-expected-error {{sema_err_cannot_cast}}
}

// The body cannot hand a callback typed with 'T' another object than the one it received.
var g_ErasedOtherBase: ErasedBase

func(T is ErasedBase) erasedForge(target: *T, notify: func||(*T))
{
    notify(target)
    notify(&g_ErasedOtherBase)     // swc-expected-error {{sema_err_erased_param_forged}}
}

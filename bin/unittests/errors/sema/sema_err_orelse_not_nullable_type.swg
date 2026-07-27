#global private

// 'orelse' substitutes a missing value. A type that can never be null leaves it nothing
// to substitute, so the zero test has to be written explicitly.

func orelseOnInteger()
{
    let count = 0
    let n     = count orelse 10     // swc-expected-error {{sema_err_orelse_not_nullable_type}}
    discard n
}

func orelseOnFloat()
{
    let ratio = 0.0'f32
    let r     = ratio orelse 1.5'f32     // swc-expected-error {{sema_err_orelse_not_nullable_type}}
    discard r
}

func orelseOnBool()
{
    let flag = false
    let b    = flag orelse true     // swc-expected-error {{sema_err_orelse_not_nullable_type}}
    discard b
}

#[Swag.EnumFlags]
enum OrElseFlags { None = 0, A = 1 }

func orelseOnEnumFlags()
{
    let f = OrElseFlags.None
    let g = f orelse OrElseFlags.A     // swc-expected-error {{sema_err_orelse_not_nullable_type}}
    discard g
}

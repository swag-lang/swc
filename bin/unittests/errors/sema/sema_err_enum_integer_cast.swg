#global private

enum Color: s32
{
    Red = 1
    Green = 4
}

const invalid: Color = cast(Color, 99's32) // swc-expected-error {{sema_err_cannot_cast}}

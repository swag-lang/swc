#global private

// Another language's function keyword is reported once, and the declaration still parses.

fn foreignTwice(x: s32)->s32 => x * 2     // swc-expected-error {{'fn' does not declare a function in Swag; [help] use 'func' instead}}

function foreignHalf(x: s32)->s32 => x / 2     // swc-expected-error {{'function' does not declare a function in Swag; [help] use 'func' instead}}

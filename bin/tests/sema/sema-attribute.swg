#global internal

attr MyAttr();

#[MyAttr]
var A: s32 = 0

#[MyAttr]
{
    var B: s32 = 0
    var C: s32 = 0
}

const BB = 1
#[BB] // swc-expected-error {{sema_err_not_attribute}}
const CC = 0

attr Foreign1(module: string, function: string = "")
attr Foreign3(module: s32...)

attr Foreign2(module: any)              // swc-expected-error {{sema_err_invalid_attribute_parameter_type}}
attr Foreign4(module: ..., x: s32)      // swc-expected-error {{sema_err_invalid_attribute_parameter_type}}
attr Foreign5(module: s32..., x: s32)   // swc-expected-error {{sema_err_variadic_not_last}}
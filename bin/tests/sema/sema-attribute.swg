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
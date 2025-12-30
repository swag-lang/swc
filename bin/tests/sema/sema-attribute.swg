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
#[BB]
const CC = 0
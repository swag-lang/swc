// swc-option suite-test

#global fileprivate

var state: s32

#init
{
    state += 1
}

#premain
{
    state += 10
}

#test
{
    state += 100
}

#test
{
    state += 1000
}

#drop
{
    if state != 1111
    {
        var ptr: [*] u8 = null
        ptr[111] = 111
    }
}

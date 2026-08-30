#global private

enum TestKey: u32
{
    None
    A
    B
}

func takesKey(key: TestKey)->u32
{
    return cast(u32) key
}

func semaTest001()
{
    let a = cast(TestKey) 1'u8
    let b = cast(TestKey) 2'u32

    Swag.assert(a == TestKey.A)
    Swag.assert(b == TestKey.B)
    Swag.assert(takesKey(cast(TestKey) 0'u32) == 0'u32)
}

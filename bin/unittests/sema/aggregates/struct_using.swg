#global fileprivate

struct S {}

struct OkValue
{
    using v: S
}

struct OkPtr
{
    using p: *S
}

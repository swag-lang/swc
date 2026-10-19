#[Swag.NoInline]
func low(dst: [*] u64)
{
    for i in 0'u64 until 4'u64 do
        dst[i] = i
}

#[Swag.NoInline]
func high(dst: [*] u64)
{
    for i in 1000000000'u64 until 1000000004'u64 do
        dst[i - 1000000000] = i - 1000000000
}

#main
{
    var a, b: [4] u64
    low(&a[0])
    high(&b[0])
    Swag.print("CHECK=", a[0] + a[1] + a[2] + a[3], " OTHER=", b[0] + b[1] + b[2] + b[3], "\n")
}

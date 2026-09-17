#global private

// Character classes written as `or` chains of ranges and values: the
// optimizer evaluates every link and ORs the bytes instead of branching. Each
// class must still match the table built one value at a time.

#[Swag.Optimize(true), Swag.NoInline]
func isHex(c: u8)->bool => (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')

#[Swag.Optimize(true), Swag.NoInline]
func isAlnum(c: u8)->bool => (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')

#[Swag.Optimize(true), Swag.NoInline]
func isIdentStart(c: u8)->bool => (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

#[Swag.Optimize(true), Swag.NoInline]
func isFar(c: u32)->bool => c == 1 or c == 90 or c == 200 or c == 4000

#[Swag.Optimize(true), Swag.NoInline]
func notControl(c: u8)->bool => not (c < 32 or c == 127)

func table(c: u32, lo, hi: u32)->bool => c >= lo and c <= hi

#test
{
    for v in 0 until 256
    {
        let c = cast(u8) v
        let u = cast(u32) v
        Swag.assert(isHex(c) == (table(u, 48, 57) or table(u, 97, 102) or table(u, 65, 70)))
        Swag.assert(isAlnum(c) == (table(u, 97, 122) or table(u, 65, 90) or table(u, 48, 57)))
        Swag.assert(isIdentStart(c) == (table(u, 97, 122) or table(u, 65, 90) or u == 95))
        Swag.assert(notControl(c) == (u >= 32 and u != 127))
    }

    for v in [0'u32, 1, 2, 89, 90, 91, 199, 200, 201, 3999, 4000, 4001, 0xFFFFFFFF] do
        Swag.assert(isFar(v) == (v == 1 or v == 90 or v == 200 or v == 4000))
}

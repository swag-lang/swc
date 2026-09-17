#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline] func multiplySelected(a, b, c, flag: u8)->u8 => flag != 0 ? a * b : a * c

#test
{
    let values = [0'u8, 1, 2, 7, 15, 127, 128, 255]
    for a in values do for b in values do for c in values do for flag in values do
        Swag.assert(multiplySelected(a, b, c, flag) == a * (flag != 0 ? b : c))
}

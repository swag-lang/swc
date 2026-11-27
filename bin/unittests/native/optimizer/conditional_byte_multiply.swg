#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func multiplySelected(a, b, c, flag: u8)->u8 => flag != 0 ? a * b : a * c

#test
{
    let values = [0_u8, 1, 2, 7, 15, 127, 128, 255]
    for a in values
    {
        for b in values
        {
            for c in values
            {
                for flag in values
                {
                    Swag.require(multiplySelected(a, b, c, flag) == a * (flag != 0 ? b : c))
                }
            }
        }
    }
}

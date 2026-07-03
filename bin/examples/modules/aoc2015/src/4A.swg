/*
--- Day 4: The Ideal Stocking Stuffer ---
Santa needs help mining some AdventCoins (very similar to bitcoins) to use as gifts for all the economically forward-thinking little girls and boys.

To: this, he needs to find MD5 hashes which, in hexadecimal, start with at least five zeroes. The input to the MD5 hash is some secret key (your puzzle input, given below) followed by a number in decimal. To mine AdventCoins, you must find Santa the lowest positive number (no leading zeroes: 1, 2, 3, ...) that produces such a hash.

For example:

If your secret key is abcdef, the answer is 609043, because the MD5 hash of abcdef609043 starts with five zeroes (000001dbbfa...), and it is the lowest such number to: so.
If your secret key is pqrstuv, the lowest number it combines with to make an MD5 hash starting with five zeroes is 1048970; that is, the MD5 hash of pqrstuv1048970 looks like 000006136ef....
Your puzzle input is yzbqklnj.
*/

using Core

internal const DAY4_SECRET = "yzbqklnj"

internal func day4InitBuffer(buffer: &[16] u8)
{
    Memory.copy(&buffer[0], @dataof(DAY4_SECRET), @countof(DAY4_SECRET))
}

internal func day4BuildInput(buffer: &[16] u8, value: u64)->const [..] u8
{
    var digits: [20] u8
    var digitCount = 0'u64
    var remaining  = value
    for
    {
        digits[digitCount] = cast(u8) (remaining % 10) + '0'
        digitCount += 1
        remaining /= 10
        if !remaining do
            break
    }

    var writeIndex = @countof(DAY4_SECRET)
    while digitCount
    {
        digitCount -= 1
        buffer[writeIndex] = digits[digitCount]
        writeIndex += 1
    }

    return @mkslice(&buffer[0], writeIndex)
}

func day4A()
{
    var buffer: [16] u8
    day4InitBuffer(&buffer)
    for
    {
        let v = Hash.Md5.compute(day4BuildInput(&buffer, @index))
        if v[0] == 0 and v[1] == 0 and (v[2] & 0xF0) == 0
        {
            //Console.print("total: ", @index)
            @assert(@index == 282749)
            break
        }
    }
}

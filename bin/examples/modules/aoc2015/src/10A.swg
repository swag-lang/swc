/*
--- Day 10: Elves Look, Elves Say ---
Today, the Elves are playing a game called look-and-say. They take turns making sequences by reading aloud the previous sequence and using that reading as the next sequence. For example, 211 is read as "one two, two ones", which becomes 1221 (1 2, 2 1s).

Look-and-say sequences are generated iteratively, using the previous value as input for the next step. For each step, take the previous value, and replace each run of digits (like 111) with the number of digits (3) followed by the digit itself (1).

For example:

1 becomes 11 (1 copy of digit 1).
11 becomes 21 (2 copies of digit 1).
21 becomes 1211 (one 2 followed by one 1).
1211 becomes 111221 (one 1, one 2, and two 1s).
111221 becomes 312211 (three 1s, two 2s, and one 1).
Starting with the digits in your puzzle input, apply this process 40 times. What is the length of the result?

Your puzzle input is 1113122113.
*/

using Core

internal var day10LengthsReady = false
internal var day10Length40, day10Length50: u64

internal func day10WriteCount(write: [*] u8, count: u64)->[*] u8
{
    if count < 10
    {
        write[0] = cast(u8) count + '0'
        return write + 1
    }

    var scan = write
    var digits: [20] u8
    var digitCount = 0'u64
    var remaining  = count
    for
    {
        digits[digitCount] = cast(u8) (remaining % 10) + '0'
        digitCount += 1
        remaining /= 10
        if !remaining do
            break
    }

    while digitCount
    {
        digitCount -= 1
        scan[0] = digits[digitCount]
        scan += 1
    }

    return scan
}

internal func day10RunStep(input: string, output: &String)
{
    output.clear()
    output.reserve((@countof(input) * 2) + 1)

    let inputLen = @countof(input)
    var i        = 0'u64
    var write    = output.buffer
    while i < inputLen
    {
        let digit = input[i]
        var count = 1'u64
        i += 1
        while i < inputLen and input[i] == digit
        {
            count += 1
            i += 1
        }

        write    = day10WriteCount(write, count)
        write[0] = digit
        write += 1
    }

    output.length = cast(u64) (write - output.buffer)
    output.buffer[output.length] = 0
}

internal func day10EnsureLengths()
{
    if day10LengthsReady do
        return

    var current: String = "1113122113"
    var next: String
    for 50
    {
        day10RunStep(current.toString(), &next)
        swap(&current, &next)

        if @index == 39 do
            day10Length40 = current.length
    }

    day10Length50    = current.length
    day10LengthsReady = true
}

func day10A()
{
    day10EnsureLengths()
    @assert(day10Length40 == 360154)
}

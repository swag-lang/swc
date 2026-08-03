#global if WINDOWS and #command == Swag.CompilerCommand.Test
#global private

func containsDriveLetter(letters: const [..] rune, expected: rune)->bool
{
    for letter in letters where letter == expected do
        return true
    return false
}

#test
{
    let available = File.availableDriveLetters()
    var previous = 0'rune
    for letter in available
    {
        @assert(letter >= 'A' and letter <= 'Z')
        @assert(previous == 0 or previous < letter)
        @assert(!Directory.exists(Format.toString("%:\\", letter)))
        previous = letter
    }

    for [index] in 26
    {
        let letter = cast(rune) ('A' + index)
        if Directory.exists(Format.toString("%:\\", letter)) do
            @assert(!containsDriveLetter(available.toSlice(), letter))
    }
}

#assert('\x41' == 'A')

#assert("\n" ++ "\t" == "\n\t")
#assert("A\\B" == #"A\B"#)
#assert("The quote is: \"Hello\"" == "The quote is: \"Hello\"")
#assert("Line one.\r\nLine two." == "Line one.\r\nLine two.")

#assert('A' == 'A') // Basic character
#assert('\'' == '\'') // Single quote escape
#assert('\"' == '"') // Double quote escape
#assert('\\' == '\\') // Backslash escape

#assert("\x41" == "A") // 'A'
#assert("\x61" == "a") // 'a'
#assert("\x0A" == "\n") // Newline via hex escape

#assert("\u0041" == "A") // 'A'
#assert("\u000D" == "\r") // Carriage return
#assert("\u2603" == "☃") // Unicode snowman
#assert("\U0001F600" == "😀") // Unicode grinning face (requires 8-digit escape)

#assert('\n''u8 == 10)
#assert('\n''u16 == 10)
#assert('\n''u32 == 10)
#assert('\n''u64 == 10)
#assert('\n' == 10)
#assert('\n' == 10'u8)
#assert('\n' == 10'u16)
#assert('\n' == 10'u32)
#assert('\n' == 10'u64)

#assert(s32 == s32)
#assert(s32 != u32)
#assert(!(s8 == s32))
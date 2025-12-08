#assert('\x41' == 'A')

#assert("\n" ++ "\t" == "\n\t")
#assert("A\\B" == #"A\B"#)
#assert("The quote is: \"Hello\"" == "The quote is: \"Hello\"")
#assert("Line one.\r\nLine two." == "Line one.\r\nLine two.")

#assert('A' == 'A')
#assert('\'' == '\'')
#assert('\"' == '"')
#assert('\\' == '\\')

#assert("\x41" == "A")
#assert("\x61" == "a")
#assert("\x0A" == "\n")

#assert("\u0041" == "A")
#assert("\u000D" == "\r")
#assert("\u2603" == "☃")
#assert("\U0001F600" == "😀")

#assert('\n''u8 == 10)
#assert('\n''u16 == 10)
#assert('\n''u32 == 10)
#assert('\n''u64 == 10)
#assert('\n' == 10)
#assert('\n' == 10'u8)
#assert('\n' == 10'u16)
#assert('\n' == 10'u32)
#assert('\n' == 10'u64)

#assert('a''rune == 'a')

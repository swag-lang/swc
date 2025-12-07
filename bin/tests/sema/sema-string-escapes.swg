#assert("\n" ++ "\t" == "\n\t")
#assert("A\\B" == #"A\B"#)
#assert("The quote is: \"Hello\"" == "The quote is: \"Hello\"")
#assert("Line one.\r\nLine two." == "Line one.\r\nLine two.")
#assert("Null terminator:\0" == "Null terminator:")

#assert('A' == 'A') // Basic character
#assert('\'' == '\'') // Single quote escape
#assert('\"' == '"') // Double quote escape
#assert('\\' == '\\') // Backslash escape
#assert('\n' == 10) // ASCII newline check (assuming char is an integer type)

#assert("\x41" == "A") // 'A'
#assert("\x61" == "a") // 'a'
#assert("\x0A" == "\n") // Newline via hex escape
#assert('\x41' == 'A')

#assert("\u0041" == "A") // 'A'
#assert("\u000D" == "\r") // Carriage return
#assert("\u2603" == "☃") // Unicode snowman
#assert("\U0001F600" == "😀") // Unicode grinning face (requires 8-digit escape)

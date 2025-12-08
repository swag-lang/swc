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

#assert("\b" == "\b")
#assert("\f" == "\f")
#assert("\v" == "\v")

#assert("\r" == "\r")
#assert("\r\n" != "\n")

#assert("\0" == "\0")

#assert("\x42" == "B")
#assert("\x42" == "\x42")
#assert("\xFF" == "\xFF")

#assert("\u0000" == "\0")
#assert("\u0061" == "a")
#assert("\u00E9" == "é")
#assert("\u4E00" == "一")

#assert("\U00000041" == "A")
#assert("\U0010FFFF" == "\U0010FFFF")

#assert(#"Line\nNo\tEscape"# == "Line\\nNo\\tEscape")
#assert(#"C:\Path\To\File"# == "C:\\Path\\To\\File")

#assert("Hello\u0020World" == "Hello World")
#assert("A" ++ "\n" ++ "B" == "A\nB")

#assert("Quote: \"test\"" == "Quote: \"test\"")

#assert("Path\\" == "Path\\")
#assert("\\\\" == "\\\\")


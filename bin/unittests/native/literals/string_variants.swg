#global private     //

const Eol = #raw """
"""

// Raw strings: no escape processing
#test
{
    let a = #raw "hello"
    let b = #raw "C:\Path\To\File"
    let c = #raw "no \n escape here"

    #assert(#typeof(a) == string)
    #assert(#typeof(b) == string)

    Swag.assert(a == "hello")
    Swag.assert(b == "C:\\Path\\To\\File")
    Swag.assert(c == "no \\n escape here")
}

// Raw strings preserve backslashes literally
#test
{
    let raw = #raw "A\B"
    let normal = "A\\B"
    Swag.assert(raw == normal)
}

// Raw strings with embedded quotes. A raw literal cannot end with a quote, because the
// quote would run into the closing delimiter.
#test
{
    let a = #raw """say "hello" twice"""
    Swag.assert(a == "say \"hello\" twice")
}

// Multiline strings
#test
{
    let a = """hello"""
    Swag.assert(a == "hello")
}

#test
{
    let a = """line1
line2
line3"""
    Swag.assert(a[0] == cast(u8) 'l'rune)
    Swag.assert(a.count > 10)
}

// Multiline strings support escape sequences
#test
{
    let a = """tab\there"""
    let b = "tab\there"
    Swag.assert(a == b)
}

// Multiline strings with embedded double quotes
#test
{
    let a = """This is "quoted" text"""
    Swag.assert(a == "This is \"quoted\" text")
}

#test
{
    let a = """this is
               a
               string
               """
    Swag.assert(a == "this is" ++ Eol ++ "a" ++ Eol ++ "string" ++ Eol)
}

#test
{
    let a = #raw """this is
              a
              string
              """
    Swag.assert(a == "this is" ++ Eol ++ "a" ++ Eol ++ "string" ++ Eol)
}

#test
{
    let a = """first
               second
           third
                 fourth
               """
    Swag.assert(a == "first" ++ Eol ++ "second" ++ Eol ++ "third" ++ Eol ++ "  fourth" ++ Eol)
}

#test
{
    let a = """\
            this is
            a
            string
            """
    Swag.assert(a == "this is" ++ Eol ++ "a" ++ Eol ++ "string" ++ Eol)
}

// Multiline empty
#test
{
    let a = """"""
    Swag.assert(a.count == 0)
}

// Raw vs normal string comparison
#test
{
    Swag.assert(#raw "hello world" == "hello world")
    Swag.assert(#raw "\n" != "\n")
    Swag.assert(#raw "\t" != "\t")
    Swag.assert(#raw "A\\B" == "A\\\\B")
}

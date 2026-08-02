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

    @assert(a == "hello")
    @assert(b == "C:\\Path\\To\\File")
    @assert(c == "no \\n escape here")
}

// Raw strings preserve backslashes literally
#test
{
    let raw = #raw "A\B"
    let normal = "A\\B"
    @assert(raw == normal)
}

// Raw strings with embedded quotes. A raw literal cannot end with a quote, because the
// quote would run into the closing delimiter.
#test
{
    let a = #raw """say "hello" twice"""
    @assert(a == "say \"hello\" twice")
}

// Multiline strings
#test
{
    let a = """hello"""
    @assert(a == "hello")
}

#test
{
    let a = """line1
line2
line3"""
    @assert(a[0] == cast(u8) 'l'rune)
    @assert(@countof(a) > 10)
}

// Multiline strings support escape sequences
#test
{
    let a = """tab\there"""
    let b = "tab\there"
    @assert(a == b)
}

// Multiline strings with embedded double quotes
#test
{
    let a = """This is "quoted" text"""
    @assert(a == "This is \"quoted\" text")
}

#test
{
    let a = """this is
               a
               string
               """
    @assert(a == "this is" ++ Eol ++ "a" ++ Eol ++ "string" ++ Eol)
}

#test
{
    let a = #raw """this is
              a
              string
              """
    @assert(a == "this is" ++ Eol ++ "a" ++ Eol ++ "string" ++ Eol)
}

#test
{
    let a = """first
               second
           third
                 fourth
               """
    @assert(a == "first" ++ Eol ++ "second" ++ Eol ++ "third" ++ Eol ++ "  fourth" ++ Eol)
}

#test
{
    let a = """\
            this is
            a
            string
            """
    @assert(a == "this is" ++ Eol ++ "a" ++ Eol ++ "string" ++ Eol)
}

// Multiline empty
#test
{
    let a = """"""
    @assert(@countof(a) == 0)
}

// Raw vs normal string comparison
#test
{
    @assert(#raw "hello world" == "hello world")
    @assert(#raw "\n" != "\n")
    @assert(#raw "\t" != "\t")
    @assert(#raw "A\\B" == "A\\\\B")
}

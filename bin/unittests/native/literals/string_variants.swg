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

    Swag.require(a == "hello")
    Swag.require(b == "C:\\Path\\To\\File")
    Swag.require(c == "no \\n escape here")
}

// Raw strings preserve backslashes literally
#test
{
    let raw = #raw "A\B"
    let normal = "A\\B"
    Swag.require(raw == normal)
}

// Raw strings with embedded quotes. A raw literal cannot end with a quote, because the
// quote would run into the closing delimiter.
#test
{
    let a = #raw """say "hello" twice"""
    Swag.require(a == "say \"hello\" twice")
}

// Multiline strings
#test
{
    let a = """hello"""
    Swag.require(a == "hello")
}

#test
{
    let a = """line1
line2
line3"""
    Swag.require(a[0] == cast(u8, 'l'rune))
    Swag.require(a.count > 10)
}

// Multiline strings support escape sequences
#test
{
    let a = """tab\there"""
    let b = "tab\there"
    Swag.require(a == b)
}

// Multiline strings with embedded double quotes
#test
{
    let a = """This is "quoted" text"""
    Swag.require(a == "This is \"quoted\" text")
}

#test
{
    let a = """this is
               a
               string
               """
    Swag.require(a == #stringof("this is", Eol, "a", Eol, "string", Eol))
}

#test
{
    let a = #raw """this is
              a
              string
              """
    Swag.require(a == #stringof("this is", Eol, "a", Eol, "string", Eol))
}

#test
{
    let a = """first
               second
           third
                 fourth
               """
    Swag.require(a == #stringof("first", Eol, "second", Eol, "third", Eol, "  fourth", Eol))
}

#test
{
    let a = """\
            this is
            a
            string
            """
    Swag.require(a == #stringof("this is", Eol, "a", Eol, "string", Eol))
}

// Multiline empty
#test
{
    let a = """"""
    Swag.require(a.count == 0)
}

// Raw vs normal string comparison
#test
{
    Swag.require(#raw "hello world" == "hello world")
    Swag.require(#raw "\n" != "\n")
    Swag.require(#raw "\t" != "\t")
    Swag.require(#raw "A\\B" == "A\\\\B")
}

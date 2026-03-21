#global fileprivate //

// Raw strings: no escape processing
#test
{
    let a = #"hello"#
    let b = #"C:\Path\To\File"#
    let c = #"no \n escape here"#

    #assert(#typeof(a) == string)
    #assert(#typeof(b) == string)

    @assert(a == "hello")
    @assert(b == "C:\\Path\\To\\File")
    @assert(c == "no \\n escape here")
}

// Raw strings preserve backslashes literally
#test
{
    let raw    = #"A\B"#
    let normal = "A\\B"
    @assert(raw == normal)
}

// Raw strings with embedded quotes
#test
{
    let a = #"say "hello""#
    @assert(a == "say \"hello\"")
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
    @assert(a[0] == cast(u8) 'l''rune)
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

// Multiline empty
#test
{
    let a = """"""
    @assert(@countof(a) == 0)
}

// Raw vs normal string comparison
#test
{
    @assert(#"hello world"# == "hello world")
    @assert(#"\n"#          != "\n")
    @assert(#"\t"#          != "\t")
    @assert(#"A\\B"#        == "A\\\\B")
}

enum A
{
    #assert(A)
    B,
    C,
}

#assert(A)
#assert(A) #assert(A) // swc-expected-error {{ParserExpectedEndOfLine}}
#assert(A
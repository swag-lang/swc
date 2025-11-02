enum A
{
    #assert(A)
    B,
    C,
}

#assert A // swc-expected-error {{ParserExpectedToken}}
// swc-expected-error@+ {{ParserExpectedClosing}}
#assert(A)
#assert(A) #assert(A) // swc-expected-error {{ParserExpectedEndOfLine}}

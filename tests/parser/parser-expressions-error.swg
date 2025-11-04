#assert A // swc-expected-error {{ParserExpectedToken}}
// swc-expected-error@+ {{ParserExpectedClosing}}
#assert(A)
#assert(A) #assert(A) // swc-expected-error {{ParserExpectedEndOfLine}}

#assert(A and (B || C)) // swc-expected-error {{ParserUnexpectedAndOr}}
#assert(A && (B and C)) // swc-expected-error {{ParserUnexpectedAndOr}}

#assert(cast #bit #bit (s32) 9) // swc-expected-error {{ParserDuplicatedModifier}}
#assert(cast #ref1 (s32) 9) // swc-expected-error {{ParserInvalidModifier}}
#assert(a + #wrap b)

#assert(a + / b) // swc-expected-error {{ParserUnexpected}}

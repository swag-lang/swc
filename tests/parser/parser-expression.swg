#assert((A))
#assert((A and B))
#assert(A and B or C)
#assert(A and (B or C))

#assert(A and (B || C)) // swc-expected-error {{ParserUnexpectedAndOr}}
#assert(A && (B and C)) // swc-expected-error {{ParserUnexpectedAndOr}}

#assert(A + 5)
#assert(A + 5 > 5 and true)
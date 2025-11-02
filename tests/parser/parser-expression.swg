#assert((A))
#assert((A and B))
#assert(A and B or C)
#assert(A and (B or C))

#assert(A and (B || C)) // swc-expected-error {{ParserUnexpectedAndOr}}
#assert(A && (B and C)) // swc-expected-error {{ParserUnexpectedAndOr}}

#assert(A == 5)

#assert(A + 5)
#assert(A + 5 > 5 and true)
#assert((A or B) and C)
#assert(A == B)
#assert(A != B and C)
#assert(A < B or B < C)
#assert(A <= B and B <= C)
#assert(A + B * C)
#assert((A + B) * C)
#assert(A / (B - C))
#assert((A + 5) * (B - 3) > 0)


#assert(A == [5])
#assert(A == [5, 4+A])



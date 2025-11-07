// ============================================================================
// Parser Identifiers Ok
// ============================================================================

#assert(A())
#assert(A(1, 2, 3))

#assert(A[])
#assert(A[1, 2, 3])

#assert(A{})
#assert(A{1, 2, 3})

// --- Whitespace & newline variants ---
#assert( A( ) )
#assert(
  A(
  1,
  2,
  3
  )
)

#assert( A[ ] )
#assert(
  A[
    1,
    2,
    3
  ]
)

#assert( A{ } )
#assert(
  A{
    1,
    2,
    3
  }
)

// --- Trailing comma tolerance (enable only if grammar allows) ---
#assert(A(1,2,))       // function call trailing comma
#assert(A[1,2,])       // array deref trailing comma
#assert(A{1,2,})       // struct init trailing comma

// --- Single-arg forms ---
#assert(A(0))
#assert(A[0])
#assert(A{0})

// --- Mixed nesting (call/array/struct as subexpressions) ---
#assert(A( B(), C[1,2], D{3,4} ))
#assert(A[ B(), C[1,2], D{3,4} ])
#assert(A{ B(), C[1,2], D{3,4} })

// Nested deeper
#assert(A( B( C{} ), D[ E() , F{1} ] ))
#assert(A[ B( C{} ), D[ E() , F{1} ] ])
#assert(A{ B( C{} ), D[ E() , F{1} ] })

// --- Empty-in-empty combos ---
#assert(A( B(), C(), D() ))
#assert(A[ B[], C[], D[] ])
#assert(A{ B{}, C{}, D{} })

// --- Spacing corner cases ---
#assert(A(1 ,2 ,3))
#assert(A[1 ,2 ,3])
#assert(A{1 ,2 ,3})

#assert(A(  1,2,3  ))
#assert(A[  1,2,3  ])
#assert(A{  1,2,3  })

// --- Mixed empty & non-empty combos ---
#assert(A( B(), C[1], D{} ))
#assert(A[ B(1), C[], D{2} ])
#assert(A{ B{}, C(3), D[4] })

// --- Long arity / stress args ---
#assert(A(0,1,2,3,4,5,6,7,8,9))
#assert(A[0,1,2,3,4,5,6,7,8,9])
#assert(A{0,1,2,3,4,5,6,7,8,9})

// --- Line breaks right after openers (lexer/punctuator stress) ---
#assert(A(
))
#assert(A[
])
#assert(A{
})

// --- Adjacent constructs to test greedy parsing ---
#assert(A(B(1,2)))
#assert(A[B[1,2]])
#assert(A{B{1,2}})

// --- Interleaved constructs inside one list ---
#assert(A( B[1,2], C{3,4}, D() ))
#assert(A[ B(), C{1}, D[2] ])
#assert(A{ B[9], C(), D{8} })

// --- Heterogeneous literal-like contents ---
// If your language distinguishes ints/bools/strings/etc., these still just test delimiter parsing.
#assert(A( true, false, "x" ))
#assert(A[ true, false, "x" ])
#assert(A{ true, false, "x" })

// --- Deeply nested with line breaks ---
#assert(
  A(
    B(
      C{
        D[1,2],
        E(),
        F{ G[3] }
      }
    ),
    H[ I{ J() }, K(), L[4,5] ]
  )
)

// --- Spaces before closers ---
#assert(A(1,2,3   ))
#assert(A[1,2,3   ])
#assert(A{1,2,3   })

// --- No-space tight forms ---
#assert(A(1,2,3))
#assert(A[1,2,3])
#assert(A{1,2,3})

// --- Combinations starting empty then populated ---
#assert(A( B(), C(1) ))
#assert(A[ B[], C[1] ])
#assert(A{ B{}, C{1} })

// --- Big mixed case (parser backtracking / precedence) ---
#assert(
  A{
    B(1,2,3),
    C[4,5,6],
    D{
      E(),
      F[7],
      G{8,9},
      H( I{ J[10] }, K(), L[11,12] )
    }
  }
)

#assert(main())
#assert(!main1())
#assert(main() and true)
#assert(main1() or true)

#assert(main'A())
#assert(main'(A)())
#assert(main'(A, B)())

#assert(A(name: 1+2+3+4))
#assert(A(name: 1+2+3+4, a: A()))
#assert(A{name: 1+2+3+4, a: A()})

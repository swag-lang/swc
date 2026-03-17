#global fileprivate // swc-option sema-only
#global skip
const A = #"\titi"# ++
          #"\tata"# ++
          "toto" ++
          """tonton"""

#test
{
    @assert(A == #"\titi\tatatototonton"#)
}

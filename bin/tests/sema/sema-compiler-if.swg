#global internal

#if false { const A = 0 } #else { const A = 1 }
#assert(A == 1)

#if true { const T1 = 1 } #else { const T1 = 0 }
#assert(T1 == 1)

#if false { const E1 = 0 } #elif true { const E1 = 2 } #else { const E1 = 3 }
#assert(E1 == 2)

#if false { const E2 = 0 } #elif false { const E2 = 1 } #else { const E2 = 3 }
#assert(E2 == 3)

#if false { const C1 = 0 }
#elif false { const C1 = 1 }
#elif true { const C1 = 2 }
#elif true { const C1 = 99 }
#else { const C1 = 3 }
#assert(C1 == 2)

#if true {
  #if false { const N = 0 } #else { const N = 4 }
}
#assert(N == 4)

// 1) Outer #if is false, inner #if/#elif/#else chain must be completely ignored.
//    Only the #else of the outer chain should matter.

#if false {
  #if true  { const S1 = 1 }
  #elif true { const S1 = 2 }
  #else { const S1 = 3 }
} #else {
  const S1 = 42
}
#assert(S1 == 42)


// 2) Outer #if is true, so the #else (which contains a nested chain) is skipped.

#if true {
  const S2 = 10
} #else {
  #if false { const S2 = 0 }
  #elif true { const S2 = 1 }
  #else { const S2 = 2 }
}
#assert(S2 == 10)


// 3) Outer #if is false, hits an #elif true branch, so everything in the original
//    false branch (including nested #if/#else chain) must be ignored.

#if false {
  #if false { const S3 = -1 }
  #elif true {
    #if true { const S3 = 1 } #else { const S3 = 2 }
  } #else {
    const S3 = 3
  }
} #elif true {
  const S3 = 99
} #else {
  const S3 = 100
}
#assert(S3 == 99)


// 4) Deeply nested: multiple layers of skipped chains before the taken one.
//    None of the inner definitions in skipped parts may affect the final binding.

#if false {
  #if true {
    const S4 = 1
  } #elif true {
    const S4 = 2
  } #else {
    const S4 = 3
  }
} #elif false {
  #if true { const S4 = 4 } #else { const S4 = 5 }
} #elif true {
  const S4 = 123
  #if false {
    const S4 = 999
  } #elif true {
    // even this is skipped because the outer #if already chose this branch's body,
    // but the inner condition itself is false, so do nothing.
  } #else {
    const S4 = 777
  }
} #else {
  const S4 = -1
}
#assert(S4 == 123)

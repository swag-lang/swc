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

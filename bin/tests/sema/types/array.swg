#global fileprivate

var A: [?] s32
#assert(#nameof(#typeof(A)) == "[?] s32")
#assert(#nameof(#typeof(A)) != "[?] bool")

enum C { A}

var F: [2, 3, 4] s32
#assert(#nameof(#typeof(F)) == "[2, 3, 4] s32")

var F0: [2, 3, 4] s32
#assert(#nameof(#typeof(F0[0])) == "[3, 4] s32")
#assert(#nameof(#typeof(F0[0, 0])) == "[4] s32")
#assert(#nameof(#typeof(F0[0, 0, 0])) == "s32")

var F1: [2][3][4] s32
#assert(#nameof(#typeof(F1[0])) == "[3][4] s32")
#assert(#nameof(#typeof(F1[0][0])) == "[4] s32")
#assert(#nameof(#typeof(F1[0][0][0])) == "s32")

// Multi-index on C-style nested arrays flattens through inner dimensions.
var F2: [2][2] s32
#assert(#nameof(#typeof(F2[0, 0])) == "s32")
#assert(#nameof(#typeof(F2[0])) == "[2] s32")

var F3: [2][3][4] s32
#assert(#nameof(#typeof(F3[0, 0])) == "[4] s32")
#assert(#nameof(#typeof(F3[0, 0, 0])) == "s32")

const F4: [2, 2] s32 = [[1, 2], [3, 4]]
#assert(#nameof(#typeof(F4[0])) == "[2] s32")
#assert(#nameof(#typeof(F4[0, 0])) == "s32")
#assert(F4[0, 0] == 1)
#assert(F4[0, 1] == 2)
#assert(F4[1, 0] == 3)
#assert(F4[1, 1] == 4)

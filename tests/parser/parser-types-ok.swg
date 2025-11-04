// ============================================================================
// Parser Types Ok
// ============================================================================

enum TOTO: const [..] s32
{
    R = 1
    G = 3
    B = 0
}

enum A : B { B = 0, C = 1, }

enum A : u32 {}
enum A : *T {}
enum A : **T {}

enum A : [*] s32 {}
enum A : [..] s32 {}
enum A : [?] s32 {}
enum A : [5] A {}
enum A : [5][10] A {}
enum A : [5][10] ****A {}
enum A : [5][..] ****A {}
enum A : &A {}
enum A : &&A {}
enum A : *const *A {}

enum A : [/* toto */ * ] s32 {}

// Valid: pointers + arrays + qualifiers
enum A : *A {}
enum A : *const A {}
enum A : **A {}
enum A : *const *A {}
enum A : *[5]A {}
enum A : [5]*A {}
enum A : [5][10]*const A {}
enum A : [/* c */5] A {}
enum A : [5] /* c */ [10] A {}
enum A : &*A {}
enum A : &&*A {}
enum A : [5][..] *const *A {}
enum A : [*] *A {}
enum A : [..] &A {}
enum A : [?] &A {}

enum A : [* /* stuck */ ] s32 {}
enum A : [.. /* stuck */ ] s32 {}
enum A : [? /* stuck */ ] s32 {}

// Valid: more combos to stress nesting
enum A : [1][2][3] ***A {}
enum A : & & A {}
enum A : *const [5]A {}
enum A : [5]*const *A {}

enum AA: const [2, 2] s32 {}
enum AA: const [2, 2, 3, 5][1, 2] s32 {}

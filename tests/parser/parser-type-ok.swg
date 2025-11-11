enum TOTO: const [..] s32
{
    R = 1
    G = 3
    B = 0
}

enum A : B { B = 0, C = 1, }

enum A : u32 { Z }
enum A : *T { Z }
enum A : **T { Z }

enum A : [*] s32 { Z }
enum A : [..] s32 { Z }
enum A : [?] s32 { Z }
enum A : [5] A { Z }
enum A : [5][10] A { Z }
enum A : [5][10] ****A { Z }
enum A : [5][..] ****A { Z }
enum A : &A { Z }
enum A : &&A { Z }
enum A : *const *A { Z }

enum A : [/* toto */ * ] s32 { Z }

// Valid: pointers + arrays + qualifiers
enum A : *A { Z }
enum A : *const A { Z }
enum A : **A { Z }
enum A : *const *A { Z }
enum A : *[5]A { Z }
enum A : [5]*A { Z }
enum A : [5][10]*const A { Z }
enum A : [/* c */5] A { Z }
enum A : [5] /* c */ [10] A { Z }
enum A : &*A { Z }
enum A : &&*A { Z }
enum A : [5][..] *const *A { Z }
enum A : [*] *A { Z }
enum A : [..] &A { Z }
enum A : [?] &A { Z }

enum A : [* /* stuck */ ] s32 { Z }
enum A : [.. /* stuck */ ] s32 { Z }
enum A : [? /* stuck */ ] s32 { Z }

// Valid: more combos to stress nesting
enum A : [1][2][3] ***A { Z }
enum A : & & A { Z }
enum A : *const [5]A { Z }
enum A : [5]*const *A { Z }

enum AA: const [2, 2] s32 { Z }
enum AA: const [2, 2, 3, 5][1, 2] s32 { Z }

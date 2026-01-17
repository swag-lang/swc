#global internal

 struct AA
{
    x: s32
    y: *BB
}

struct BB
{
    x: s32
    y: any
    z: *void
}

struct CC { a: *CC }
#assert(#sizeof(CC) == 8)

// swc-expected-error@(+1,+2,+3) {{sema_err_cyclic_dependency}}
const D1: s32 = D2 + 1
const D2: s32 = D3 + 1
const D3: s32 = D1

struct DD { a: DD } // swc-expected-error {{sema_err_struct_circular_reference}}

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
struct EE { a: FF }
struct FF { a: EE }

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
const C1: s32 = C2
const C2: s32 = C1

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
enum EG { EG_A = EH }
const EH: s32 = EG.EG_A

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
enum EI { EI_A = EJ.EJ_B }
enum EJ { EJ_B = EI.EI_A }

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
struct KK { v: KEnum }
enum KEnum { KEnum_A = #sizeof(KK) }

struct LL { p: *LLEnum }
enum LLEnum { LLEnum_A = #sizeof(LL) }

const NC: s32 = 42
enum NonCyclicEnum
{
    NCE_A = NC,
    NCE_B = NC + 1
}
#assert(NonCyclicEnum.NCE_A == 42)
#assert(NonCyclicEnum.NCE_B == 43)

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
struct S0 { x: [4] S1 }
struct S1 { y: S0 }

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    let x = st.x
}
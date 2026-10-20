#global private

// The gather's destructive mask lives in XMM15, a nonvolatile register: a function
// that gathers must give it back intact to a caller still holding a value there.

var g_Values: [12] f64

#[Swag.NoInline]
func gatherAndTouch(base: const [*] s32, index: u32)->s32
{
    // The store keeps the caller's loads of 'g_Values' on their side of the call.
    g_Values[0] = 0
    let lanes = cast([4] s32, Swag.vecGather(base, Swag.vecSplat(index)))
    return lanes[0]
}

// Twelve floats live across the call fill every nonvolatile float register.
#[Swag.NoInline]
func sumAcrossGather(base: const [*] s32)->f64
{
    let a0  = g_Values[0]
    let a1  = g_Values[1]
    let a2  = g_Values[2]
    let a3  = g_Values[3]
    let a4  = g_Values[4]
    let a5  = g_Values[5]
    let a6  = g_Values[6]
    let a7  = g_Values[7]
    let a8  = g_Values[8]
    let a9  = g_Values[9]
    let a10 = g_Values[10]
    let a11 = g_Values[11]

    let gathered = gatherAndTouch(base, 2)
    return a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11 + cast(f64, gathered)
}

#test
{
    for i in 12 do
        g_Values[i] = cast(f64, i + 1)

    let table = [10's32, 20, 30, 40]
    Swag.assert(sumAcrossGather(table.buffer) == 78.0 + 30.0)
}

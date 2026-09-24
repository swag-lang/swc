#global private

const A: [5] u64 = [1, 2, 3, 4, 5]
const B: [5] u64 = [5, 4, 3, 2, 1]
const C: [5] u64 = [2, 3, 5, 7, 11]

// Branches within a counted loop must keep their destinations when the
// constant-index table reads are folded into each unrolled copy.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func weightedScore(seed: u64)->u64
{
    var total = seed
    for i in 5'u64
    {
        let a      = A[i] + seed
        let b      = B[i] + 2
        let c      = C[i] + 1
        let mixed  = a * a + b * b + c * c + a * b
        if (mixed & 1) == 0
        {
            total += mixed
            continue
        }

        let tail = (a + b + c) * (b + 1) + a * c
        total += tail > 100 ? tail : a + b + c
    }

    return total
}

#test
{
    Swag.assert(weightedScore(0) == 488)
    Swag.assert(weightedScore(3) == 707)
}

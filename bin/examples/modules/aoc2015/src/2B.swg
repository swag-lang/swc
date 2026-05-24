/*
--- Part Two ---
The elves are also running low on ribbon. Ribbon is all the same width, so they only have to worry about the length they need to order, which they would again like to be exact.

The ribbon required to wrap a present is the shortest distance around its sides, or the smallest perimeter of any one face. Each present also requires a bow made out of ribbon as well; the feet of ribbon required for the perfect bow is equal to the cubic feet of volume of the present. Don't ask how they tie the bow, though; they'll never tell.

For example:

A present with dimensions 2x3x4 requires 2+2+3+3 = 10 feet of ribbon to wrap the present plus 2*3*4 = 24 feet of ribbon for the bow, for a total of 34 feet.
A present with dimensions 1x1x10 requires 1+1+1+1 = 4 feet of ribbon to wrap the present plus 1*1*10 = 10 feet of ribbon for the bow, for a total of 14 feet.
How many total feet of ribbon should they order?
*/

using Core

func day2B()
{
    day2B0()
    day2B1()
}

/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
func day2B0()
{
    day2EnsurePresents()

    var total: u64
    foreach gift in day2Presents
    {
        let x = gift.x
        let y = gift.y
        total += gift.x * gift.y * gift.z + 2 * x + 2 * y
    }

    //Console.print("total: ", total)
    @assert(total == 3783758)
}

/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
func day2B1()
{
    day2EnsurePresents()

    var total: u64
    foreach gift in day2Presents do
        total += gift.x * gift.y * gift.z + 2 * gift.x + 2 * gift.y

    //Console.print("total: ", total)
    @assert(total == 3783758)
}

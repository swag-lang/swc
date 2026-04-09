#global fileprivate

#test
{
    func square(x: s32) => x * x
    alias sq = square
    @assert(sq(5) == 25)
}

#test
{
    func add(a: s32, b: s32) => a + b
    alias plus = add
    @assert(plus(3, 7) == 10)
}

#test
{
    func greet()->string { return "hello" }
    alias hi = greet
    @assert(hi() == "hello")
}

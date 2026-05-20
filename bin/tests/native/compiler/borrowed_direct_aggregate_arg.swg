#global fileprivate

struct(T) BorrowedArgBox
{
    value: T
}

func(T) makeBorrowedArgBox(value: T)->BorrowedArgBox'T
{
    return {value: value}
}

#test
{
    let nested = makeBorrowedArgBox(makeBorrowedArgBox(42))
    @assert(nested.value.value == 42)
}

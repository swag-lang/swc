#global private

enum Sparse { First = 10, Second = 50, Third = 100 }
enum Other { Small = 2, Large = 8 }

func(T) memberWithValue(raw: u64)->T
{
    for value in T where cast(u64, value) == raw do
        return value
    Swag.panic("missing enum member", #curlocation)
}

#test
{
    Swag.require(memberWithValue'Sparse(50) == Sparse.Second)
    Swag.require(memberWithValue'Other(8) == Other.Large)
}

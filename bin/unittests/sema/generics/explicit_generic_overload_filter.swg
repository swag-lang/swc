#global private

func choose(value: bool, other: f32)->s32
{
    return 1
}

func(T, U) choose(value: T, other: U)->bool
{
    return #typeof(value) == T and #typeof(other) == U
}

func semaTest001()
{
    #assert(#typeof(choose'(bool)(true, 0.0'f32)) == bool)
}

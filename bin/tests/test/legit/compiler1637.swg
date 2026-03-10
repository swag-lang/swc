#global fileprivate
#global skip
struct A
{
    x:     u32
    y:     u32
}

#test
{
    var st: A
    st.y = 0
}

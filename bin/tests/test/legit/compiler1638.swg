#global fileprivate
#global skip
//#global testerror

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

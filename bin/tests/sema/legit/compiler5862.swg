#global fileprivate
#global skip
struct A
{
    moduleprivate a5862: s32
}

impl A
{
    func toto()
    {
        var a: A
        a.a5862 = 0
    }
}
/*
#test
{
    var a: A
    a.a5862 = 0
}*/

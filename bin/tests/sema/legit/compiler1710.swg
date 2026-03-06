#global fileprivate
#global skip
#test
{
    let str   = "string"
    let tuple = {@dataof(str), 2}
    let ptr   = #typeof(tuple)
}

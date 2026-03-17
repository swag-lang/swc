#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0232"

enum BasicErrors
{
    FailedToLoad
    FailedToSave
}

enum MyErrors1
{
    using BasicErrors
}

#test
{
    var x: MyErrors1
    x = .BasicErrors.FailedToLoad
}

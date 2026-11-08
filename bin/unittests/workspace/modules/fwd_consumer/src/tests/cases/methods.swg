using FwdProvider

#test
{
    var receiver: FwdStore
    var source = FwdValue{4}
    receiver.put(source)
    Swag.require(receiver.value() == 4)
    receiver.put(#move source)
    Swag.require(receiver.value() == 4)
}

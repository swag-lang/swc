#global fileprivate
#global skip
fileprivate
{
    moduleprivate func toto() {}
}

#test
{
    toto()
}

#run { Swag.assert(TransitiveMiddle.value() == 5) }
#main
{
    Swag.assert(TransitiveMiddle.value() == 12)
    Swag.print("transitive source dependency passed\n")
}

#global private

#[Swag.NoInline]
func stop()
{
    Swag.safetyPanic("caught safety failure", #curlocation)
}

#test
{
    let caught = Swag.catchPanic(func() { stop() })
    Swag.require(caught.raised and caught.message() == "caught safety failure")

    let assertion = Swag.catchPanic(func() { Swag.assert(false, "caught assertion") })
    Swag.require(assertion.raised and assertion.message() == "caught assertion")

    let next = Swag.catchPanic(func() {})
    Swag.require(not next.raised)
}

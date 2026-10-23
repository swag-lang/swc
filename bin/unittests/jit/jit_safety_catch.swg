#global private

#[Swag.NoInline]
func stop()
{
    Swag.safetyPanic("caught safety failure", #curlocation)
}

#test
{
    let caught = Swag.catchPanic(func() { stop() })
    Swag.assert(caught.raised and caught.message() == "caught safety failure")

    let assertion = Swag.catchPanic(func() { Swag.assert(false, "caught assertion") })
    Swag.assert(assertion.raised and assertion.message() == "caught assertion")

    let next = Swag.catchPanic(func() {})
    Swag.assert(not next.raised)
}

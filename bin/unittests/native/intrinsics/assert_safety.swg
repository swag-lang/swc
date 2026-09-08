#global private

func condition(count: *s32)->bool
{
    count[] += 1
    return true
}

func message(count: *s32)->string
{
    count[] += 10
    return "assertion message"
}

func location(count: *s32)->Swag.SourceCodeLocation
{
    count[] += 100
    return #curlocation
}

#[Swag.NoInline]
func defaultAssertions()->s32
{
    var count = 0
    Swag.assert(condition(&count), message(&count), location(&count))
    return count
}

#[Swag.Inline, Swag.Safety(.Assert, false)]
func disabledAssertions()->s32
{
    var count = 0
    Swag.assert(condition(&count), message(&count), location(&count))
    Swag.assert(false)
    return count
}

#[Swag.Inline, Swag.Safety(.Assert, true)]
func enabledAssertions()->s32
{
    var count = 0
    Swag.assert(condition(&count), message(&count), location(&count))
    return count
}

func scopedAssertions()->s32
{
    var count = 0
    #[Swag.Safety(.Assert, false)]
    {
        Swag.assert(condition(&count), message(&count))
        #[Swag.Safety(.Assert, true)]
        {
            Swag.assert(condition(&count), message(&count))
        }
        Swag.assert(condition(&count))
    }
    return count
}

#[Swag.Safety(.Assert, false)]
func narrowedAssertion(value: *s32?)->s32
{
    Swag.assert(value != null)
    return value[]
}

#test
{
    const Default  = #run defaultAssertions()
    const Disabled = #run disabledAssertions()
    const Enabled  = #run enabledAssertions()
    const Scoped   = #run scopedAssertions()
    #assert(Default == (#cfg == "devmode" ? 1 : 0))
    #assert(Disabled == 0)
    #assert(Enabled == 1)
    #assert(Scoped == 1)
    #assert(#safety(Swag.SafetyWhat.Assert) == (#cfg == "devmode"))

    // Verification stays active in release without changing the functions' safety settings.
    if defaultAssertions() != Default do Swag.panic("default assertion setting", #curlocation)
    if disabledAssertions() != 0 do Swag.panic("disabled assertion evaluated an argument", #curlocation)
    if enabledAssertions() != 1 do Swag.panic("enabled assertion evaluated its message or location", #curlocation)
    if scopedAssertions() != 1 do Swag.panic("scoped assertion override", #curlocation)
    var value = 42
    if narrowedAssertion(&value) != 42 do Swag.panic("assertion narrowing", #curlocation)
}

var messageCreated = 0
var messageDropped = 0

struct OwnedMessage
{
    value = 1
    // Force caller-owned return storage, as an owning string uses.
    padding: [32] u8
}
impl OwnedMessage
{
    mtd opDrop() { messageDropped += 1 }
    #[Swag.NoInline]
    mtd const text()->string => .value == 1 ? "owned message" : "other message"
    #[Swag.NoInline]
    mtd const condition()->bool => .value == 1
    #[Swag.Implicit]
    mtd const opCast()->string => "owned message"
}

func makeOwnedMessage()->OwnedMessage
{
    messageCreated += 1
    return {}
}

#[Swag.Safety(.Assert, true)]
#test
{
    messageCreated = 0
    messageDropped = 0
    Swag.assert(true, makeOwnedMessage())
    Swag.assert(messageCreated == 0 and messageDropped == 0)
}

// The condition's owner is evaluated and dropped even when diagnostic owners are skipped.
#[Swag.Safety(.Assert, true)]
#test
{
    messageCreated = 0
    messageDropped = 0
    Swag.assert(makeOwnedMessage().condition(), makeOwnedMessage().text())
    Swag.assert(messageCreated == 1 and messageDropped == 1)
}

#[Swag.NoInline, Swag.Safety(.Assert, true)]
func assertWithOwnedMessage(value: bool)
{
    Swag.assert(value, makeOwnedMessage().text())
}

// A borrowed message view must not schedule a drop for its unevaluated owner.
#[Swag.Safety(.Assert, true)]
#test
{
    messageCreated = 0
    messageDropped = 0
    assertWithOwnedMessage(true)
    Swag.assert(messageCreated == 0 and messageDropped == 0)
}

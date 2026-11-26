#global private

struct BindingJob
{
    ready: bool
}

#test
{
    var branches = 0
    if let count = 0 where count == 0
    {
        branches += 1
    }
    if var enabled = false where not enabled
    {
        branches += 2
    }
    if const paused = false where not paused
    {
        branches += 4
    }

    let job = BindingJob{ready: true}
    if not job.ready
    {
        branches += 100
    }
    else if let candidate = job where candidate.ready
    {
        branches += 8
    }

    Swag.require(branches == 15)
}

#[Swag.NoInline]
func bindingText(initializations: *s32, present: bool)->string?
{
    initializations[] += 1
    return present ? "" : null
}

#[Swag.NoInline]
func bindingGuard(evaluations: *s32, passed: bool)->bool
{
    evaluations[] += 1
    return passed
}

#test
{
    var initializations = 0
    var guards = 0
    if let text = bindingText(&initializations, true) where bindingGuard(&guards, true)
    {
        Swag.require(text.count == 0)
    }
    else
    {
        Swag.require(false)
    }

    if let text = bindingText(&initializations, false) where bindingGuard(&guards, true)
    {
        Swag.require(false)
    }
    else
    {
        Swag.require(text == null)
    }

    if var text = bindingText(&initializations, false) where bindingGuard(&guards, true)
    {
        Swag.require(false)
    }
    else
    {
        Swag.require(text == null)
    }

    if var text = bindingText(&initializations, true) where bindingGuard(&guards, false)
    {
        Swag.require(false)
    }
    else
    {
        Swag.require(text != null and text.count == 0)
    }

    if const text: string? = null where bindingGuard(&guards, true)
    {
        Swag.require(false)
    }
    else
    {
        Swag.require(text == null)
    }

    if const text: string? = "" where bindingGuard(&guards, true)
    {
        Swag.require(text.count == 0)
    }
    else
    {
        Swag.require(false)
    }

    if const text: string? = "text" where bindingGuard(&guards, text[0] == 't')
    {
        Swag.require(text.count == 4)
    }
    else
    {
        Swag.require(false)
    }

    Swag.require(initializations == 4 and guards == 4)
}

alias MaybeBoundCount = *s32?

func bindingNumber(value: *s32)->MaybeBoundCount    => value
func bindingEmptySlice(storage: [*] s32)->[..] s32? => Swag.makeSlice(storage, 0)

#test
{
    var count = 0
    if let pointer = bindingNumber(&count) where pointer[] == 0
    {
        pointer[] = 7
    }
    else
    {
        Swag.require(false)
    }
    Swag.require(count == 7)

    var storage: [1] s32
    if let slice = bindingEmptySlice(&storage[0])
    {
        Swag.require(slice.count == 0)
    }
    else
    {
        Swag.require(false)
    }
}

#test
{
    let number: const any = 0_s32
    let other:  const any = "text"
    var guards = 0

    if number is s32 as value where bindingGuard(&guards, value[] == 0)
    {
        Swag.require(value[] == 0)
    }
    else
    {
        Swag.require(false)
    }

    if other is s32 as value where bindingGuard(&guards, value[] == 0)
    {
        Swag.require(false)
    }

    Swag.require(guards == 1)
}

#global private

var value = 42
var cleanups: u32

#[Swag.NoInline]
func load(name: string)->*s32 fail
{
    if name == "missing" do fail Swag.BaseError{"missing"}
    return &value
}

func choose(names: const [..] string)->*s32 fail
{
    for name in names
    {
        catch
        {
            defer { cleanups += 1 }
            return try load(name)
        }
    }
    fail Swag.BaseError{"no candidate"}
}

#[Swag.NoInline]
func chooseWithoutInlining(names: const [..] string)->*s32 fail => try choose(names)

func chooseWithoutCleanup(names: const [..] string)->*s32 fail
{
    for name in names
    {
        catch { return try load(name) }
    }
    fail Swag.BaseError{"no candidate"}
}

func nestedScopes()->*s32
{
    catch
    {
        discard try load("present")
        expect { return try chooseWithoutCleanup(["missing", "present"]) }
    }
    return &value
}

func required()->*s32
{
    expect
    {
        defer { cleanups += 1 }
        return try load("present")
    }
    return &value
}

func loopExits()
{
    for index in 3
    {
        catch
        {
            defer { cleanups += 1 }
            discard try load("present")
            if index == 0 do continue
            break
        }
    }

    for index in 3
    {
        expect
        {
            defer { cleanups += 1 }
            discard try load("present")
            if index == 0 do continue
            break
        }
    }
}

#test
{
    let depth = Swag.getContext().errorIndex
    cleanups = 0
    for 300
    {
        let result = expect choose(["missing", "present"])
        Swag.require(result[] == 42)
        Swag.require(Swag.getContext().errorIndex == depth)
        let other = expect chooseWithoutInlining(["missing", "present"])
        Swag.require(other == result)
        Swag.require(Swag.getContext().errorIndex == depth)
    }
    Swag.require(cleanups == 1200)
}

#test
{
    let depth = Swag.getContext().errorIndex
    cleanups = 0
    for 300
    {
        Swag.require(required()[] == 42)
        loopExits()
        Swag.require(Swag.getContext().errorIndex == depth)
    }
    Swag.require(cleanups == 1500)
}

#test
{
    let depth = Swag.getContext().errorIndex
    for 300
    {
        Swag.require(nestedScopes()[] == 42)
        Swag.require(Swag.getContext().errorIndex == depth)
    }
}

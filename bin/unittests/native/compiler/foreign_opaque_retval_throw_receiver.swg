#global private

#[Swag.Opaque]
struct BigOpaque
{
    payload: [472] u8
    capture: string
    matched: bool
}

impl BigOpaque
{
    mtd prepare(value: string) throw
    {
        .matched = true
        .capture = value
    }

    func create(value: string)->BigOpaque throw
    {
        var result: retval
        assume
        {
            result.prepare(value)
        }
        return result
    }

    mtd match(value: string)->bool
    {
        .matched = true
        .capture = value
        return true
    }

    mtd getCapture()->string
    {
        return .capture
    }
}

func captureValue(line: string)->string throw
{
    var r = BigOpaque.create("init")
    discard r.match(line)
    return r.getCapture()
}

func captureValueInAssumeBlock(line: string)->string
{
    var result = ""
    assume
    {
        var r = BigOpaque.create("init")
        discard r.match(line)
        result = r.getCapture()
    }

    return result
}

#test
{
    assume
    {
        @assert(captureValue("2x3x4") == "2x3x4")
        @assert(captureValueInAssumeBlock("2x3x4") == "2x3x4")
    }
}

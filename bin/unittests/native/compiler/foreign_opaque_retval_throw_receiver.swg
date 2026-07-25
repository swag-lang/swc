#global private

#[Swag.Opaque]
struct BigOpaque
{
    payload: [472] u8
    capture: string = ""
    matched: bool
}

impl BigOpaque
{
    mtd prepare(value: string) fail
    {
        .matched = true
        .capture = value
    }

    func create(value: string)->BigOpaque fail
    {
        var result: retval
        expect
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

func captureValue(line: string)->string fail
{
    var r = BigOpaque.create("init")
    discard r.match(line)
    return r.getCapture()
}

func captureValueInAssumeBlock(line: string)->string
{
    var result = ""
    expect
    {
        var r = BigOpaque.create("init")
        discard r.match(line)
        result = r.getCapture()
    }

    return result
}

#test
{
    expect
    {
        @assert(captureValue("2x3x4") == "2x3x4")
        @assert(captureValueInAssumeBlock("2x3x4") == "2x3x4")
    }
}

#global private

// A struct literal field whose value does not convert reports at that value, and names the
// field and the struct that declares it, whatever the depth of the literal.

struct Text
{
    value: string = ""
}

impl Text
{
    #[Swag.Implicit]
    mtd opSet(value: string)
    {
        .value = value
    }
}

struct Options
{
    level: u32
    name:  Text
}

struct Request
{
    source:  Text
    options: Options
}

struct Artifact
{
    request: Request
    count:   u32
}

func flat()
{
    let options = Options{
        level:
            "x"     // swc-expected-error {{value for field 'level' of 'Options' has type 'string', but the field needs 'u32'}}
        }
}

func nested()
{
    let artifact = Artifact{
        request: {
            source: "a",
            options: {
                level:
                    "x"     // swc-expected-error {{value for field 'level' of 'Options' has type 'string', but the field needs 'u32'}}
            }
        }
        }
}

func nestedStruct()
{
    let artifact = Artifact{
        request: {
            source: "a",
            options:
                true     // swc-expected-error {{value for field 'options' of 'Request' has type 'bool', but the field needs 'Options'}}
        }
        }
}

#global private

// A struct literal nested in another converts each field exactly like a literal written alone:
// an untyped integer or float takes the field type, a string goes through the field's implicit
// 'opSet', and an enum shorthand resolves against the field type. A constant nested literal
// whose fold stops at a field built at run time was once re-checked as a stored value, and
// refused those conversions below the first level.

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

enum Kind
{
    Native
    Microcode
}

struct Options
{
    level: u32
    scale: f32
    kind:  Kind
    name:  Text
}

struct Request
{
    source:  Text
    stage:   Text
    level:   u32
    options: Options
}

struct Artifact
{
    request: Request
    count:   u32
}

struct Bundle
{
    artifact: Artifact
    tag:      Text
}

// One level below the typed literal, with fields left to their defaults.
#test
{
    let artifact = Artifact{request: {source: "a", stage: "b"}}
    Swag.assert(artifact.request.source.value == "a" and artifact.request.stage.value == "b")
    Swag.assert(artifact.request.level == 0 and artifact.count == 0)
    Swag.assert(artifact.request.options.kind == .Native)
}

// Two levels below the typed literal.
#test
{
    let artifact = Artifact{request: {source: "a", stage: "b", level: 1, options: {level: 2}}, count: 3}
    Swag.assert(artifact.request.source.value == "a" and artifact.request.stage.value == "b")
    Swag.assert(artifact.request.level == 1 and artifact.request.options.level == 2 and artifact.count == 3)

    let options = Artifact{request: {source: "s", options: {scale: 1.5, kind: .Microcode, name: "n"}}}
    Swag.assert(options.request.options.scale == 1.5 and options.request.options.kind == .Microcode)
    Swag.assert(options.request.options.name.value == "n" and options.request.source.value == "s")
}

// Three levels below the typed literal, and the same literal without a type prefix.
#test
{
    let bundle = Bundle{artifact: {request: {stage: "pre", options: {level: 4, scale: 0.5, kind: .Microcode, name: "deep"}}}, tag: "t"}
    Swag.assert(bundle.tag.value == "t" and bundle.artifact.request.stage.value == "pre")
    Swag.assert(bundle.artifact.request.options.level == 4 and bundle.artifact.request.options.scale == 0.5)
    Swag.assert(bundle.artifact.request.options.kind == .Microcode and bundle.artifact.request.options.name.value == "deep")

    let untyped: Bundle = {artifact: {request: {source: "u", options: {level: 5}}}}
    Swag.assert(untyped.artifact.request.source.value == "u" and untyped.artifact.request.options.level == 5)
}

// A run-time field beside the constant ones takes the same path as an all-constant literal.
#test
{
    let level: u32 = 7
    let artifact   = Artifact{request: {source: "a", options: {level: level, name: "r"}}}
    Swag.assert(artifact.request.options.level == 7 and artifact.request.options.name.value == "r")
    Swag.assert(artifact.request.source.value == "a")
}

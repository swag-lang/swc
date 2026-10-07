#global private

struct NestedRuntimeValue
{
    text:    string?
    padding: [5] u64
}

#[Swag.NoInline]
func nestedRuntimeValue(text: string)->NestedRuntimeValue
{
    var result: retval = {}
    result.text = text
    return result
}

struct NestedRuntimeSettings
{
    preset:        u8
    optimization:  u8
    configuration: NestedRuntimeValue
}

struct NestedRuntimeRequest
{
    source:   NestedRuntimeValue
    stage:    NestedRuntimeValue
    kind:     u8
    settings: NestedRuntimeSettings
}

#[Swag.NoCopy]
struct NestedRuntimeArtifact
{
    request: NestedRuntimeRequest
    padding: [64] u64
}

struct NestedRuntimeBatch
{
    items: [2] NestedRuntimeSettings
}

// Named fields must preserve the concrete storage of every nested runtime literal, including
// omitted defaults. Copying the smaller anonymous layout reads unrelated temporary values.
#test
{
    for level in 3
    {
        var artifact = NestedRuntimeArtifact{request: {
            source: nestedRuntimeValue("source"), stage: nestedRuntimeValue("stage"),
            kind: 2, settings: {optimization: cast(u8, level)}}}
        Swag.assert(artifact.request.source.text == "source")
        Swag.assert(artifact.request.stage.text == "stage")
        Swag.assert(artifact.request.kind == 2)
        Swag.assert(artifact.request.settings.preset == 0)
        Swag.assert(artifact.request.settings.optimization == level)
        Swag.assert(artifact.request.settings.configuration.text.count == 0)
        for item in artifact.request.settings.configuration.padding do
            Swag.assert(item == 0)

        var batch = NestedRuntimeBatch{items: [{optimization: cast(u8, level)}, {preset: 7}]}
        Swag.assert(batch.items[0].preset == 0)
        Swag.assert(batch.items[0].optimization == level)
        Swag.assert(batch.items[0].configuration.text.count == 0)
        Swag.assert(batch.items[1].preset == 7)
        Swag.assert(batch.items[1].optimization == 0)
        Swag.assert(batch.items[1].configuration.text.count == 0)
    }
}

#global private

struct NestedRuntimeValue
{
    text:    string?
    padding: [5] u64
}

#[Swag.NoInline]
func nestedRuntimeValue(text: string)->NestedRuntimeValue
{
    var result: #returntype = {}
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
        var artifact = NestedRuntimeArtifact{request: NestedRuntimeRequest{
            source: nestedRuntimeValue("source"), stage: nestedRuntimeValue("stage"),
            kind: 2, settings: NestedRuntimeSettings{optimization: cast(u8, level)}}}
        Swag.require(artifact.request.source.text == "source")
        Swag.require(artifact.request.stage.text == "stage")
        Swag.require(artifact.request.kind == 2)
        Swag.require(artifact.request.settings.preset == 0)
        Swag.require(artifact.request.settings.optimization == level)
        Swag.require(artifact.request.settings.configuration.text.count == 0)
        for item in artifact.request.settings.configuration.padding do
            Swag.require(item == 0)

        var batch = NestedRuntimeBatch{items: [NestedRuntimeSettings{optimization: cast(u8, level)}, NestedRuntimeSettings{preset: 7}]}
        Swag.require(batch.items[0].preset == 0)
        Swag.require(batch.items[0].optimization == level)
        Swag.require(batch.items[0].configuration.text.count == 0)
        Swag.require(batch.items[1].preset == 7)
        Swag.require(batch.items[1].optimization == 0)
        Swag.require(batch.items[1].configuration.text.count == 0)
    }
}

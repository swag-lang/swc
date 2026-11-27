#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderParityScene)
    Testing.assertImageGolden(&image, "render.parity.portable")
}

// The deterministic CPU backend is the reviewable reference for measured strokes too.
#[Swag.TestTag("golden")]
#test
{
    func scene(renderer: IRenderer)->Image => renderStrokeParityScene(renderer)
    let image = renderCpu(&scene)
    Testing.assertImageGolden(&image, "render.parity.stroke")
}

// Text goldens cover bitmap sampling plus the complete built-in MTSDF effects path.
#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderTextParityScene)
    Testing.assertImageGolden(&image, "render.parity.text")
}

// The CPU backend makes composite layer output deterministic and reviewable.
#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderLayerParityScene)
    Testing.assertImageGolden(&image, "render.parity.layer")
}

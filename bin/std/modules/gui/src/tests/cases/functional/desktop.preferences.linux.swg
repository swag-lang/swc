#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

// An independent XSETTINGS producer encoded the same preferences in both byte orders.
#test
{
    const little = #include("../../datas/xsettings.little.bin")
    const big    = #include("../../datas/xsettings.big.bin")
    for bytes in [little, big]
    {
        let values = expect LinuxDesktop.parseSettings(bytes, {})
        Swag.assert(values.scale == 2 and values.reducedMotion and not values.prefersLight)
        var rejected: bool
        discard catch LinuxDesktop.parseSettings(bytes[0 until bytes.count - 1], {})
        {
            rejected = true
        }

        Swag.assert(rejected)
    }
}

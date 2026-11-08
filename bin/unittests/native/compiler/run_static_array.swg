#global private

using Swag

const RunFixed: [2] u8 = #run
{
    var bytes: [2] u8
    bytes[0] = 17
    bytes[1] = 29
    return bytes
}

#[Swag.NoInline]
func runReadFixed(index: u64)->u8 => RunFixed[index]

#test
{
    Swag.require(runReadFixed(0) == 17)
    Swag.require(runReadFixed(1) == 29)
}

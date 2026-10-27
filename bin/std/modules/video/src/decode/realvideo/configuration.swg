#global namespace RealVideo
#global internal

using Core, Core.Errors

// Matroska stores the RealMedia VIDO header, followed by the codec's private flags.
func configurationSize(data: const [..] u8)->{width, height: s32} fail
{
    if data.count < 34 do
        fail InvalidFormatError{"RealVideo configuration is truncated"}
    if data[4] != 'V' or
       data[5] != 'I' or
       data[6] != 'D' or
       data[7] != 'O' or
       data[8] != 'R' or
       data[9] != 'V' or
       data[10] != '4' or
       data[11] != '0' do
        fail InvalidFormatError{"RealVideo configuration has no RV40 video header"}
    let width  = cast(s32, data[12]) * 256 + cast(s32, data[13])
    let height = cast(s32, data[14]) * 256 + cast(s32, data[15])
    if width <= 0 or height <= 0 or width > 8192 or height > 8192 do
        fail InvalidFormatError{"RealVideo picture dimensions exceed the supported range"}
    return {width, height}
}

//! Format: Video for Windows bitmap headers, as containers of that era carried them.
//! Supported: The size of the header, the four characters naming a codec, and the codes that name MPEG-4 Part 2.
//! Not supported: Palettes, and any picture codec other than the one named here.
//! Role: This file owns what a bitmap header says about a picture codec, for every container that carries one.
//
#global namespace Video
#global internal

using Core

// What a container that stored its frames whole took off their front, which is nothing.
var noStoredPrefix: [1] u8
func storedNothing()->const [..] u8 => noStoredPrefix[0 until 0]

// Size of the bitmap header a track of that era carries before anything else it states.
const BitmapInfoHeaderSize = 40_u64

// Where in that header the four characters naming the codec sit.
const BitmapCompressionOffset = 16_u64

// Packs four characters the way a bitmap header stores them, least significant first.
#[Swag.ConstExpr]
func fourCharacterCode(a, b, c, d: u32) => a | (b << 8) | (c << 16) | (d << 24)

// The four-character codes that name MPEG-4 Part 2.
//
// A track of that era states its codec the way an AVI file did, with four characters an encoder
// stamped into a bitmap header. Only codes that name ISO Part 2 belong here: the Microsoft codecs
// of the same years share the lineage but not the bitstream, so their codes are absent and a track
// naming one is refused rather than guessed at.
const Mpeg4FourCcs: [19] u32 = [
    fourCharacterCode('X'_u32, 'V'_u32, 'I'_u32, 'D'_u32),
    fourCharacterCode('D'_u32, 'I'_u32, 'V'_u32, 'X'_u32),
    fourCharacterCode('D'_u32, 'X'_u32, '5'_u32, '0'_u32),
    fourCharacterCode('F'_u32, 'M'_u32, 'P'_u32, '4'_u32),
    fourCharacterCode('M'_u32, 'P'_u32, '4'_u32, 'V'_u32),
    fourCharacterCode('M'_u32, 'P'_u32, '4'_u32, 'S'_u32),
    fourCharacterCode('M'_u32, '4'_u32, 'S'_u32, '2'_u32),
    fourCharacterCode('B'_u32, 'L'_u32, 'Z'_u32, '0'_u32),
    fourCharacterCode('R'_u32, 'M'_u32, 'P'_u32, '4'_u32),
    fourCharacterCode('S'_u32, 'E'_u32, 'D'_u32, 'G'_u32),
    fourCharacterCode('W'_u32, 'V'_u32, '1'_u32, 'F'_u32),
    fourCharacterCode('F'_u32, 'F'_u32, 'D'_u32, 'S'_u32),
    fourCharacterCode('F'_u32, 'V'_u32, 'F'_u32, 'W'_u32),
    fourCharacterCode('3'_u32, 'I'_u32, 'V'_u32, '2'_u32),
    fourCharacterCode('U'_u32, 'M'_u32, 'P'_u32, '4'_u32),
    fourCharacterCode('H'_u32, 'D'_u32, 'X'_u32, '4'_u32),
    fourCharacterCode('D'_u32, 'X'_u32, 'G'_u32, 'M'_u32),
    fourCharacterCode('S'_u32, 'M'_u32, 'P'_u32, '4'_u32),
    fourCharacterCode('P'_u32, 'M'_u32, '4'_u32, 'V'_u32)]

// Whether four characters name a picture codec this module reads as MPEG-4 Part 2.
func isMpeg4FourCc(code: u32)->bool
{
    // The case an encoder chose says who wrote the file, not what its frames hold.
    var upper = 0_u32
    for shift in 4_u32
    {
        upper |= cast(u32, Latin1.toUpper(cast(u8, ((code >> (shift * 8)) & 0xFF)))) << (shift * 8)
    }

    return Slice.contains(Mpeg4FourCcs, upper)
}

// The four characters a bitmap header names its codec with.
func bitmapCompression(header: const [..] u8)->u32
{
    if header.count < BitmapCompressionOffset + 4
    {
        return 0
    }

    var code = 0_u32
    for shift in 4_u64
    {
        code |= cast(u32, header[BitmapCompressionOffset + shift]) << cast(u32, (shift * 8))
    }

    return code
}

// The setup headers at the front of a coded sample: everything before the first coded plane.
//
// A track of that era states no setup headers in the container, and a decoder needs them before it
// can read anything, so they are taken from where the stream itself carries them.
func inlineSetupHeaders(sample: const [..] u8)->const [..] u8
{
    var at = Mpeg4.nextStartCode(sample, 0)
    while at < sample.count
    {
        let code = cast(u32, sample[at + 3])
        if code == Mpeg4.CodeVop
        {
            return sample[until at]
        }

        at = Mpeg4.nextStartCode(sample, at + 1)
    }

    return sample
}

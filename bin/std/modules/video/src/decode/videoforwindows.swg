//! Format: Video for Windows bitmap headers, as containers of that era carried them.
//! Supported: The size of the header, the four characters naming a codec, and the codes that name MPEG-4 Part 2.
//! Not supported: Palettes, and any picture codec other than the one named here.
//! Role: This file owns what a bitmap header says about a picture codec, for every container that carries one.
//
#global namespace Video
#global internal

using Core

// Size of the bitmap header a track of that era carries before anything else it states.
const BitmapInfoHeaderSize = 40'u64

// Where in that header the four characters naming the codec sit.
const BitmapCompressionOffset = 16'u64

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
    fourCharacterCode('X'u32, 'V'u32, 'I'u32, 'D'u32),
    fourCharacterCode('D'u32, 'I'u32, 'V'u32, 'X'u32),
    fourCharacterCode('D'u32, 'X'u32, '5'u32, '0'u32),
    fourCharacterCode('F'u32, 'M'u32, 'P'u32, '4'u32),
    fourCharacterCode('M'u32, 'P'u32, '4'u32, 'V'u32),
    fourCharacterCode('M'u32, 'P'u32, '4'u32, 'S'u32),
    fourCharacterCode('M'u32, '4'u32, 'S'u32, '2'u32),
    fourCharacterCode('B'u32, 'L'u32, 'Z'u32, '0'u32),
    fourCharacterCode('R'u32, 'M'u32, 'P'u32, '4'u32),
    fourCharacterCode('S'u32, 'E'u32, 'D'u32, 'G'u32),
    fourCharacterCode('W'u32, 'V'u32, '1'u32, 'F'u32),
    fourCharacterCode('F'u32, 'F'u32, 'D'u32, 'S'u32),
    fourCharacterCode('F'u32, 'V'u32, 'F'u32, 'W'u32),
    fourCharacterCode('3'u32, 'I'u32, 'V'u32, '2'u32),
    fourCharacterCode('U'u32, 'M'u32, 'P'u32, '4'u32),
    fourCharacterCode('H'u32, 'D'u32, 'X'u32, '4'u32),
    fourCharacterCode('D'u32, 'X'u32, 'G'u32, 'M'u32),
    fourCharacterCode('S'u32, 'M'u32, 'P'u32, '4'u32),
    fourCharacterCode('P'u32, 'M'u32, '4'u32, 'V'u32)]

// Whether four characters name a picture codec this module reads as MPEG-4 Part 2.
func isMpeg4FourCc(code: u32)->bool
{
    // The case an encoder chose says who wrote the file, not what its frames hold.
    var upper = 0'u32
    for shift in 4'u32 do
        upper |= cast(u32) Latin1.toUpper(cast(u8) ((code >> (shift * 8)) & 0xFF)) << (shift * 8)
    return Slice.contains(Mpeg4FourCcs, upper)
}

// The four characters a bitmap header names its codec with.
func bitmapCompression(header: const [..] u8)->u32
{
    if @countof(header) < BitmapCompressionOffset + 4 do
        return 0
    var code = 0'u32
    for shift in 4'u64 do
        code |= cast(u32) header[BitmapCompressionOffset + shift] << cast(u32) (shift * 8)
    return code
}

// The setup headers at the front of a coded sample: everything before the first coded plane.
//
// A track of that era states no setup headers in the container, and a decoder needs them before it
// can read anything, so they are taken from where the stream itself carries them.
func inlineSetupHeaders(sample: const [..] u8)->const [..] u8
{
    if @countof(sample) < 4 do
        return sample
    for at in @countof(sample) - 3 where !sample[at] and !sample[at + 1] and sample[at + 2] == 1 and cast(u32) sample[at + 3] == Mpeg4.CodeVop do
        return sample[0 until at]
    return sample
}

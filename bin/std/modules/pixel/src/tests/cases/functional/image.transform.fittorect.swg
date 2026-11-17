#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10'u8, 11'u8, 12'u8, 13'u8, 20'u8, 21'u8, 22'u8, 23'u8, 30'u8, 31'u8, 32'u8, 33'u8, 40'u8, 41'u8, 42'u8, 43'u8,
        50'u8, 51'u8, 52'u8, 53'u8, 60'u8, 61'u8, 62'u8, 63'u8, 70'u8, 71'u8, 72'u8, 73'u8, 80'u8, 81'u8, 82'u8, 83'u8]

    var src = makeImage(4, 2, .RGBA8, pixels)
    src.cover(2, 2)
    assertImage(src, 2, 2, .RGBA8)

    assertPixel(src, 0, 1, Color.fromArgb(23'u8, 20'u8, 21'u8, 22'u8))
    assertPixel(src, 1, 1, Color.fromArgb(33'u8, 30'u8, 31'u8, 32'u8))
    assertPixel(src, 0, 0, Color.fromArgb(63'u8, 60'u8, 61'u8, 62'u8))
    assertPixel(src, 1, 0, Color.fromArgb(73'u8, 70'u8, 71'u8, 72'u8))

    const tallPixels = [
        70'u8, 71'u8, 72'u8, 73'u8, 80'u8, 81'u8, 82'u8, 83'u8,
        50'u8, 51'u8, 52'u8, 53'u8, 60'u8, 61'u8, 62'u8, 63'u8,
        30'u8, 31'u8, 32'u8, 33'u8, 40'u8, 41'u8, 42'u8, 43'u8,
        10'u8, 11'u8, 12'u8, 13'u8, 20'u8, 21'u8, 22'u8, 23'u8]

    var tall    = makeImage(2, 4, .RGBA8, tallPixels)
    var covered = tall.covered(2, 2)
    assertImage(tall, 2, 4, .RGBA8)
    tall = #move covered
    assertImage(tall, 2, 2, .RGBA8)
    assertPixel(tall, 0, 1, Color.fromArgb(53'u8, 50'u8, 51'u8, 52'u8))
    assertPixel(tall, 1, 1, Color.fromArgb(63'u8, 60'u8, 61'u8, 62'u8))
    assertPixel(tall, 0, 0, Color.fromArgb(33'u8, 30'u8, 31'u8, 32'u8))
    assertPixel(tall, 1, 0, Color.fromArgb(43'u8, 40'u8, 41'u8, 42'u8))
}

#test
{
    const widePixels = [
        10'u8, 20'u8, 30'u8, 255'u8, 40'u8, 50'u8, 60'u8, 255'u8,
        70'u8, 80'u8, 90'u8, 255'u8, 100'u8, 110'u8, 120'u8, 255'u8,
        130'u8, 140'u8, 150'u8, 255'u8, 160'u8, 170'u8, 180'u8, 255'u8,
        190'u8, 200'u8, 210'u8, 255'u8, 220'u8, 230'u8, 240'u8, 255'u8]
    var wide   = makeImage(4, 2, .RGBA8, widePixels)
    let inside = wide.fittedInside(3, 1, .Nearest)
    assertImage(inside, 2, 1, .RGBA8)
    assertImage(wide, 4, 2, .RGBA8)

    var tall = makeImage(2, 4, .RGBA8, [
        10'u8, 20'u8, 30'u8, 255'u8, 40'u8, 50'u8, 60'u8, 255'u8,
        70'u8, 80'u8, 90'u8, 255'u8, 100'u8, 110'u8, 120'u8, 255'u8,
        130'u8, 140'u8, 150'u8, 255'u8, 160'u8, 170'u8, 180'u8, 255'u8,
        190'u8, 200'u8, 210'u8, 255'u8, 220'u8, 230'u8, 240'u8, 255'u8])
    tall.fitInside(3, 3, .Nearest)
    assertImage(tall, 1, 3, .RGBA8)
}

// Temporary PNG decode benchmark probe. Never committed: deleted before merge.
#global if #command == Swag.CompilerCommand.Test

using Swag, Core

const CorpusDir = "C:/Users/chris/AppData/Local/Temp/claude/c--Perso-swag-lang-swc/f6f11577-323b-495f-96a6-9da06b3c3c95/scratchpad/pngbench/corpus"

#[Swag.Safety(.Overflow, false)]
func fnv(data: const [..] u8)->u64
{
    var h = 0xcbf29ce484222325'u64
    for b in data
    {
        h ^= b
        h *= 0x100000001b3
    }

    return h
}

#test
{
    let files = ["gray16.png", "gray8.png", "icon_256.png", "icon_32.png", "interlaced.png",
                 "palette.png", "photo_4k.png", "photo_opt.png", "photo_rgb.png",
                 "photo_rgba.png", "rgb16.png", "screenshot.png"]

    const Rounds = 3
    Console.println("file             us       MP      digest")
    for f in files
    {
        var path: String = CorpusDir
        path += "/"
        path += f
        let bytes = expect File.readAllBytes(path)

        var best = Swag.U64.Max
        var digest: u64
        var mp: u64
        for Rounds
        {
            var sw: Time.Stopwatch
            sw.start()
            let img = expect Image.decode(".png", bytes.toSlice())
            let us  = sw.elapsedMicroseconds()
            if us < best
            {
                best   = us
                digest = fnv(img.pixels.toSlice())
                mp     = cast(u64) img.width * img.height
            }
        }

        Console.println(f, " ", best, " ", mp, " ", Format.toString("%{X}", digest))
    }
}

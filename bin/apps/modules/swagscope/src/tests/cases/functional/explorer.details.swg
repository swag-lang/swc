#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Local audio inspection can provide a track duration without a network lookup or sample decode.
#test
{
    let file = Path.combine(testSourceRoot(#curlocation), "datas", "pacman_beginning.wav")
    Swag.require(localSoundDuration(file) >= 4)
}

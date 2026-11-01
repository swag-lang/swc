#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Local audio inspection can provide a track duration without a network lookup or sample decode.
#test
{
    let file = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", "pacman_beginning.wav")
    Swag.assert(localSoundDuration(file) >= 4)
}

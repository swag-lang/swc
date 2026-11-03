#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Net, Pixel, Audio

// The explicit integration check reaches the real HTTPS services and their artwork redirect.
#[Swag.TestTag("integration.network")]
#test
{
    let tags  = SoundTags{album: "Discovery", artist: "Daft Punk", year: "2001"}
    var music = expect OnlineMusic.lookup(&tags)
    Swag.require(music.id == "48117b90-a16e-34ca-a514-19c702df1158")
    let bytes = expect music.coverBytes()
    Swag.require(bytes.count > 100)
    let chosen = expect OnlineMusic.lookup(&tags, chosenId: music.id)
    Swag.require(chosen.id == music.id and chosen.artistText() == "Daft Punk")
}

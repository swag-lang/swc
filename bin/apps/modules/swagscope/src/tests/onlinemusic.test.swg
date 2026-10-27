#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Net, Pixel, Audio

#test
{
    var group = OnlineMusic{title: "A collaboration"}
    group.artists.add({name: "Artist One", joinphrase: " & "})
    group.artists.add({name: "Artist Two"})
    Swag.assert(group.artistText() == "Artist One & Artist Two")
    var search = MusicSearch{count: 1}
    search.groups.add(group)
    let tags = SoundTags{album: "A collaboration", artist: "Artist One & Artist Two"}
    Swag.assert(search.choose(&tags) == 0)
    let compilation = SoundTags{album: "A collaboration", artist: "Guest Performer", albumArtist: "Artist One & Artist Two"}
    Swag.assert(search.choose(&compilation) == 0)
}

struct MusicServerFixture
{
    late listener: *TcpListener
    port:          u16
    poster:        Array'u8
    requests:      [3] String
}

func serveChosenMusic(thread: const *Threading.Thread)
{
    let fixture = cast(*MusicServerFixture, unwrap thread.userParam)
    var stream  = expect fixture.listener.accept()
    var bytes: [1024] u8
    while Utf8.indexOf(fixture.requests[0].toString(), "\r\n\r\n") == Swag.U64.Max
    {
        let count = expect stream.read(bytes)
        if count == 0 do
            return
        fixture.requests[0] += cast(string, bytes[0 until count])
    }

    let body     = "{\"id\":\"48140466-cff6-3222-bd55-63c27e43190d\",\"title\":\"Discovery\",\"artist-credit\":[{\"name\":\"Daft Punk\"}]}"
    let response = Format.toString("HTTP/1.1 200 OK\r\nContent-Length: %\r\nConnection: close\r\n\r\n%", body.count, body)
    sendMusicBytes(&stream, cast(const [..] u8, response.toString()))
}

func serveMusicRetry(thread: const *Threading.Thread)
{
    let fixture = cast(*MusicServerFixture, unwrap thread.userParam)
    for index in 2
    {
        var stream = expect fixture.listener.accept()
        var bytes: [1024] u8
        while Utf8.indexOf(fixture.requests[index].toString(), "\r\n\r\n") == Swag.U64.Max
        {
            let count = expect stream.read(bytes)
            if count == 0 do
                return
            fixture.requests[index] += cast(string, bytes[0 until count])
        }

        if index == 0
        {
            sendMusicBytes(&stream, cast(const [..] u8, "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"))
            continue
        }

        let body     = "{\"count\":1,\"release-groups\":[{\"id\":\"48140466-cff6-3222-bd55-63c27e43190d\",\"title\":\"Discovery\",\"artist-credit\":[{\"name\":\"Daft Punk\"}]}]}"
        let response = Format.toString("HTTP/1.1 200 OK\r\nContent-Length: %\r\nConnection: close\r\n\r\n%", body.count, body)
        sendMusicBytes(&stream, cast(const [..] u8, response.toString()))
    }
}

// A transient service failure must be retried, not remembered as an album match or miss.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MusicServerFixture{listener: &listener, port: endpoint.port}
    var thread: Threading.Thread
    expect thread.init(&serveMusicRetry, &fixture)
    expect thread.start()
    let source = MusicSource{apiHost: "127.0.0.1", apiPort: endpoint.port, secure: false}
    let tags   = SoundTags{album: "Discovery", artist: "Daft Punk"}
    var error: Swag.Error
    discard catch OnlineMusic.lookup(&tags, source) as error
    Swag.assert(error.value() != null)
    let music = expect OnlineMusic.lookup(&tags, source)
    thread.wait()
    Swag.assert(music.title == "Discovery" and fixture.requests[1].length > 0)
}

#test
{
    let id = "48140466-cff6-3222-bd55-63c27e43190d"
    Swag.assert(validMusicId(id) and not validMusicId("bad-id"))
    var choices: Array'MusicChoice
    var entry = ExplorerEntry{path: "C:/music/test.mp3", size: 10, creationStamp: 1, modifiedStamp: 2}
    setMusicChoice(&choices, &entry, id)
    Swag.assert(musicChoiceId(choices.toSlice(), &entry) == id)
    entry.modifiedStamp += 1
    Swag.assert(musicChoiceId(choices.toSlice(), &entry) == "")
    setMusicChoice(&choices, &entry, "")
    Swag.assert(choices.isEmpty())

    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MusicServerFixture{listener: &listener, port: endpoint.port}
    var thread: Threading.Thread
    expect thread.init(&serveChosenMusic, &fixture)
    expect thread.start()
    let source = MusicSource{apiHost: "127.0.0.1", apiPort: endpoint.port, secure: false}
    let tags: SoundTags
    var music  = expect OnlineMusic.lookup(&tags, source, chosenId: id)
    thread.wait()
    Swag.assert(music.id == id and music.artistText() == "Daft Punk")
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/ws/2/release-group/48140466-cff6-3222-bd55-63c27e43190d?"))
}

func sendMusicBytes(stream: *TcpStream, bytes: const [..] u8)
{
    var offset = 0'u64
    while offset < bytes.count
    {
        let count = expect stream.write(bytes[offset to])
        if count == 0 do
            return
        offset += count
    }
}

func serveMusic(thread: const *Threading.Thread)
{
    let fixture = cast(*MusicServerFixture, unwrap thread.userParam)
    for index in 3
    {
        var stream = expect fixture.listener.accept()
        var bytes: [1024] u8
        while Utf8.indexOf(fixture.requests[index].toString(), "\r\n\r\n") == Swag.U64.Max
        {
            let count = expect stream.read(bytes)
            if count == 0 do
                return
            fixture.requests[index] += cast(string, bytes[0 until count])
        }

        if index == 1
        {
            let redirect = Format.toString("HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:%/cover.jpg\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", fixture.port)
            sendMusicBytes(&stream, cast(const [..] u8, redirect.toString()))
            continue
        }

        let json   = "{\"count\":1,\"release-groups\":[{\"id\":\"48140466-cff6-3222-bd55-63c27e43190d\",\"title\":\"Discovery\",\"first-release-date\":\"2001-03-12\",\"artist-credit\":[{\"name\":\"Daft Punk\",\"artist\":{\"name\":\"Daft Punk\"}}]}]}"
        let body   = index == 0 ? cast(const [..] u8, json) : fixture.poster.toSlice()
        let header = Format.toString("HTTP/1.1 200 OK\r\nContent-Length: %\r\nConnection: close\r\n\r\n", body.count)
        sendMusicBytes(&stream, cast(const [..] u8, header.toString()))
        sendMusicBytes(&stream, body)
    }
}

#test
{
    Swag.assert(musicQueryLiteral("A \"B\" & C") == "A \\\"B\\\" \\& C")
    let source = MusicSource{apiHost: "127.0.0.1", apiPort: 1234,
                             artHost: "127.0.0.1", artPort: 1234, secure: false}
    let current = CoverTarget{host: "127.0.0.1", port: 1234, path: "/front"}
    let next    = expect coverRedirect("http://127.0.0.1:1234/cover.jpg", current, source)
    Swag.assert(next.host == "127.0.0.1" and next.port == 1234 and next.path == "/cover.jpg")
    let archive = expect coverRedirect("http://archive.org/download/cover.jpg#fragment", current, {})
    Swag.assert(archive.host == "archive.org" and archive.port == 443 and archive.path == "/download/cover.jpg")
    for invalid in ["https://archive.org.evil.example/image", "https://archive.org@evil.example/image",
                    "//evil.example/image", "https://archive.org:81/image", "/bad%zz"]
    {
        var error: Swag.Error
        discard catch coverRedirect(invalid, current, source) as error
        Swag.assert(error.value() != null)
    }
}

// The provider lookup and its bounded artwork redirect use a local service.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MusicServerFixture{listener: &listener, port: endpoint.port}
    var image    = Image.create(8, 8, .RGB8)
    let encoded  = expect image.encode("cover.jpg")
    fixture.poster.add(unwrap encoded.toSlice())
    var thread: Threading.Thread
    expect thread.init(&serveMusic, &fixture)
    expect thread.start()

    let source = MusicSource{apiHost: "127.0.0.1", apiPort: endpoint.port,
                             artHost: "127.0.0.1", artPort: endpoint.port, secure: false}
    let tags  = SoundTags{album: "Discovery", artist: "Daft Punk", year: "2001"}
    var music = expect OnlineMusic.lookup(&tags, source)
    let bytes = expect music.coverBytes(source)
    var cover = expect Image.decode("cover.jpg", bytes.toSlice())
    thread.wait()
    listener.close()
    let reused = expect OnlineMusic.lookup(&tags, source)
    Swag.assert(reused.id == music.id)
    let guest = SoundTags{album: "Discovery", artist: "Guest", albumArtist: "Daft Punk", year: "2001"}
    Swag.assert((expect OnlineMusic.lookup(&guest, source)).id == music.id)
    let reusedCover = expect music.coverBytes(source)
    Swag.assert(reusedCover.count == bytes.count)
    Swag.assert(music.title == "Discovery" and cover.isValid())
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/ws/2/release-group/"))
    Swag.assert(Utf8.contains(fixture.requests[1].toString(), "/front-250"))
    Swag.assert(Utf8.contains(fixture.requests[2].toString(), "/cover.jpg"))
    music.label(&cover, &tags)
    let summary = MusicSummary.fromImage(&cover)
    Swag.assert(summary.title == "Discovery" and summary.artist == "Daft Punk")
    Swag.assert(cachedMediaIsFresh(&cover, Time.Timestamp.utcNow().ticks))
}

// The explicit integration check reaches the real HTTPS services and their artwork redirect.
#[Swag.TestTag("integration.network")]
#test
{
    let tags  = SoundTags{album: "Discovery", artist: "Daft Punk", year: "2001"}
    var music = expect OnlineMusic.lookup(&tags)
    Swag.assert(music.id == "48117b90-a16e-34ca-a514-19c702df1158")
    let bytes = expect music.coverBytes()
    Swag.assert(bytes.count > 100)
    let chosen = expect OnlineMusic.lookup(&tags, chosenId: music.id)
    Swag.assert(chosen.id == music.id and chosen.artistText() == "Daft Punk")
}

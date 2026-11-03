#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Local credentials can be replaced and removed without touching the checkout.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-tmdb-options-%", Guid64.random()))
    defer catch Directory.delete(folder, recurse: true)
    let token = "aaa.bbb.cccccccccccccccc"
    let key   = "0123456789abcdef0123456789abcdef"
    Swag.require(validTMDBToken(token) and validTMDBKey(key))
    expect saveTMDBCredentials(folder, token, key, false)
    Swag.require(tmdbStoredCredential("tmdb.token", folder) == token)
    Swag.require(tmdbStoredCredential("tmdb.key", folder) == key)
    expect saveTMDBCredentials(folder, "", "", true)
    Swag.require(tmdbStoredCredential("tmdb.token", folder).isEmpty())
    Swag.require(tmdbStoredCredential("tmdb.key", folder).isEmpty())
}

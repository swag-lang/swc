#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

const EmbeddedHello = [104'u8, 101, 108, 108, 111]
const EmbeddedOther = [111'u8, 107]

// Embedded-only resolution: a registered name always resolves, an unknown one fails.
#test
{
    var bundle: Resources.Bundle
    bundle.addEmbedded("lang/fr/app.tweak", EmbeddedHello)

    Swag.assert(bundle.has("lang/fr/app.tweak"))
    Swag.assert(!bundle.has("lang/de/app.tweak"))
    Swag.assert(!bundle.isOverridden("lang/fr/app.tweak"))

    let bytes = expect bundle.load("lang/fr/app.tweak")
    Swag.assert(bytes.count == 5)
    Swag.assert(bytes[0] == 'h'u8)

    discard catch bundle.load("lang/de/app.tweak") as err
    Swag.assert(err != null)
    Swag.assert(err is Errors.FileNotFoundError)
}

// Re-registering an embedded name replaces the previous bytes.
#test
{
    var bundle: Resources.Bundle
    bundle.addEmbedded("data.bin", EmbeddedHello)
    bundle.addEmbedded("data.bin", EmbeddedOther)

    let bytes = expect bundle.load("data.bin")
    Swag.assert(bytes.count == 2)
    Swag.assert(bytes[0] == 'o'u8)
}

// A disk folder overrides embedded bytes, and a missing folder never matches.
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_bundle_override")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)

    let sub = Path.combine(root.toString(), "lang")
    expect Directory.create(sub)
    discard expect File.writeAllBytes(Path.combine(sub.toString(), "fr.tweak"), [49'u8, 50, 51])

    var bundle: Resources.Bundle
    bundle.addFolder("missing_bundle_folder_that_does_not_exist")
    bundle.addFolder(root.toString())
    bundle.addEmbedded("lang/fr.tweak", EmbeddedHello)

    Swag.assert(bundle.isOverridden("lang/fr.tweak"))
    let bytes = expect bundle.load("lang/fr.tweak")
    Swag.assert(bytes.count == 3)
    Swag.assert(bytes[0] == '1'u8)

    // A name only the embedded table knows still resolves through it.
    bundle.addEmbedded("only/embedded.bin", EmbeddedOther)
    Swag.assert(!bundle.isOverridden("only/embedded.bin"))
    Swag.assert(bundle.has("only/embedded.bin"))
}

// Listing merges disk and embedded names, without duplicates, sorted.
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_bundle_list")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)

    let sub = Path.combine(root.toString(), "lang")
    expect Directory.create(sub)
    discard expect File.writeAllBytes(Path.combine(sub.toString(), "fr.tweak"), [102'u8])
    discard expect File.writeAllBytes(Path.combine(sub.toString(), "de.tweak"), [100'u8])

    var bundle: Resources.Bundle
    bundle.addFolder(root.toString())
    bundle.addEmbedded("lang/fr.tweak", EmbeddedHello)
    bundle.addEmbedded("lang/es.tweak", EmbeddedOther)
    bundle.addEmbedded("theme/widgets.png", EmbeddedOther)

    let names = bundle.list("lang/")
    Swag.assert(names.count == 3)
    Swag.assert(names[0] == "lang/de.tweak")
    Swag.assert(names[1] == "lang/es.tweak")
    Swag.assert(names[2] == "lang/fr.tweak")

    let all = bundle.list("")
    Swag.assert(all.count == 4)
}

// Directory.delete removes an empty directory, refuses a filled one without recurse.
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_directory_delete")
    expect Directory.create(root)
    discard expect File.writeAllBytes(Path.combine(root.toString(), "keep.bin"), [1'u8])

    discard catch Directory.delete(root) as err
    Swag.assert(err != null)
    Swag.assert(Directory.exists(root))

    expect Directory.delete(root, recurse: true)
    Swag.assert(!Directory.exists(root))
}

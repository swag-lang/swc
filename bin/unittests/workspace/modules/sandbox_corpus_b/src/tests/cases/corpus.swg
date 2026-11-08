#global private

using Core

func sourceDirectory(loc: Swag.SourceCodeLocation = #callerlocation)->String
{
    return unwrap Path.directoryName(loc.fileName)
}

#test
{
    Swag.require(Env.isSandboxed())
    let target = Path.combine(sourceDirectory(), "corpus.actual.txt")
    defer discard catch File.delete(target)
    discard expect File.writeAllText(target, "sandbox_corpus_b")
    Swag.require(File.exists(target))

    let outside = Path.combine(unwrap Path.directoryName(Env.corpusRoot()), "corpus-outside.actual.txt")
    var denied: Swag.Error
    discard catch File.writeAllText(outside, "outside") as denied
    Swag.require(denied.value() != null)
}

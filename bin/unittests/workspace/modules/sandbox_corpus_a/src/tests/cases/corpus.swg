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
    discard expect File.writeAllText(target, "sandbox_corpus_a")
    Swag.require(File.exists(target))
}

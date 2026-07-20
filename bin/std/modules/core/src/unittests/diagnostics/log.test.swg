#global #if #command == Swag.CompilerCommand.Test
#global private

struct MemoryLogWriter
{
    lines: [4] String
    count: u32
}

impl ILogWriter for MemoryLogWriter
{
    mtd impl print(text: #nonull string)
    {
        if me.count < @countof(me.lines) do
            me.lines[me.count] = text
        me.count += 1
    }
}

func makeExpectedShortLine(prefix: #nonull string, loc: Swag.SourceCodeLocation, text: #nonull string)->String
{
    var result: retval
    if @countof(prefix)
    {
        result.append(prefix)
        result.append(" ")
    }

    result.append(Path.getFileName(loc.fileName))
    result.append(":")
    result.appendFormat("%", loc.lineStart + 1)
    result.append(" ")
    result.append(text)
    return result
}

func makeExpectedFullLoc(loc: Swag.SourceCodeLocation, text: #nonull string)->String
{
    var result: retval
    result.append(loc.fileName)
    result.append(":")
    result.appendFormat("%", loc.lineStart + 1)
    result.append(":")
    result.appendFormat("%", loc.colStart + 1)
    result.append(":")
    result.appendFormat("%", loc.lineEnd + 1)
    result.append(":")
    result.appendFormat("%", loc.colEnd + 1)
    result.append(" ")
    result.append(text)
    return result
}

func currentLocation(loc = #callerlocation)->Swag.SourceCodeLocation => loc

#test
{
    var log = Log.create()
    log.setPrefix("CORE")
    log.setFlags(LogFlags.Prefix | LogFlags.ShortFileName | LogFlags.Line)

    var writer: MemoryLogWriter
    log.addWriter(cast(ILogWriter) writer)

    let loc = currentLocation()
    log.print("hello", loc)

    @assert(writer.count == 1)
    @assert(writer.lines[0].toString() == makeExpectedShortLine("CORE", loc, "hello").toString())
    @assert(log.getPrefix() == "CORE")
    @assert(log.getFlags() == (LogFlags.Prefix | LogFlags.ShortFileName | LogFlags.Line))
}

#test
{
    var log = Log.create()
    log.setFlags(LogFlags.LongFileName | LogFlags.FullLoc)

    var writerA: MemoryLogWriter
    var writerB: MemoryLogWriter
    log.addWriter(cast(ILogWriter) writerA)
    log.addWriter(cast(ILogWriter) writerB)

    let loc = currentLocation()
    log.print("world", loc)

    let expected = makeExpectedFullLoc(loc, "world")
    @assert(writerA.count == 1)
    @assert(writerB.count == 1)
    @assert(writerA.lines[0].toString() == expected.toString())
    @assert(writerB.lines[0].toString() == expected.toString())
}

#test
{
    var log = Log.create()
    log.setFlags(LogFlags.ShortFileName)

    var writer: MemoryLogWriter
    log.addWriter(cast(ILogWriter) writer)
    log.clearWriters()

    log.addWriter(cast(ILogWriter) writer)

    let secondLoc = currentLocation()
    log.print("second", secondLoc)

    @assert(writer.count == 1)
    var expected: String
    expected.append(Path.getFileName(secondLoc.fileName))
    expected.append(" ")
    expected.append("second")
    @assert(writer.lines[0].toString() == expected.toString())
}

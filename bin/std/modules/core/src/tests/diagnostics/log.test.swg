#global if #command == Swag.CompilerCommand.Test
#global private

struct MemoryLogWriter
{
    lines: [4] String
    count: u32
}

impl ILogWriter for MemoryLogWriter
{
    mtd impl print(text: string)
    {
        if me.count < me.lines.count do
            me.lines[me.count] = text
        me.count += 1
    }
}

func makeExpectedShortLine(prefix: string, loc: Swag.SourceCodeLocation, text: string)->String
{
    var result: retval
    if prefix.count
    {
        result.append(prefix)
        result.append(" ")
    }

    result.append(Path.fileName(loc.fileName))
    result.append(":")
    result.appendFormat("%", loc.lineStart)
    result.append(" ")
    result.append(text)
    return result
}

func makeExpectedFullLoc(loc: Swag.SourceCodeLocation, text: string)->String
{
    var result: retval
    result.append(loc.fileName)
    result.append(":")
    result.appendFormat("%", loc.lineStart)
    result.append(":")
    result.appendFormat("%", loc.colStart)
    result.append(":")
    result.appendFormat("%", loc.lineEnd)
    result.append(":")
    result.appendFormat("%", loc.colEnd)
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
    log.addWriter(writer)

    let loc = currentLocation()
    log.print("hello", loc)

    Swag.assert(writer.count == 1)
    Swag.assert(writer.lines[0].toString() == makeExpectedShortLine("CORE", loc, "hello").toString())
    Swag.assert(log.prefix() == "CORE")
    Swag.assert(log.flags() == (LogFlags.Prefix | LogFlags.ShortFileName | LogFlags.Line))
}

#test
{
    var log = Log.create()
    log.setFlags(LogFlags.LongFileName | LogFlags.FullLoc)

    var writerA: MemoryLogWriter
    var writerB: MemoryLogWriter
    log.addWriter(writerA)
    log.addWriter(writerB)

    let loc = currentLocation()
    log.print("world", loc)

    let expected = makeExpectedFullLoc(loc, "world")
    Swag.assert(writerA.count == 1)
    Swag.assert(writerB.count == 1)
    Swag.assert(writerA.lines[0].toString() == expected.toString())
    Swag.assert(writerB.lines[0].toString() == expected.toString())
}

#test
{
    var log = Log.create()
    log.setFlags(LogFlags.ShortFileName)

    var writer: MemoryLogWriter
    log.addWriter(writer)
    log.clearWriters()

    log.addWriter(writer)

    let secondLoc = currentLocation()
    log.print("second", secondLoc)

    Swag.assert(writer.count == 1)
    var expected: String
    expected.append(Path.fileName(secondLoc.fileName))
    expected.append(" ")
    expected.append("second")
    Swag.assert(writer.lines[0].toString() == expected.toString())
}

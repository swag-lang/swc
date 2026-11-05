#global if #command == Swag.CompilerCommand.Test
#global private

struct MemoryLogWriter
{
    expected: String
    count:    u32
}

impl ILogWriter for MemoryLogWriter
{
    mtd impl print(text: string)
    {
        me.count += 1
        Swag.require(text == me.expected.toString(), Format.toString("Expected '%', got '%'", me.expected.toString(), text))
    }
}

func makeExpectedShortLine(prefix: string, loc: Swag.SourceCodeLocation, text: string)->String
{
    var result: #returntype
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
    var result: #returntype
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

// A local inline String remains alive while its separately named view crosses an interface call.
#test
{
    let expected = String.from("short")
    var writer   = MemoryLogWriter{expected: expected}
    let callback: ILogWriter = writer
    var value    = String.from("short")
    let rendered = value.toString()

    callback.print(rendered)
    Swag.require(writer.count == 1)
}

// The logger's own short inline formatted String remains readable through its writer interface.
#test
{
    let expected = String.from("short")
    var writer   = MemoryLogWriter{expected: expected}
    var log      = Log.create()
    log.setFlags(LogFlags.None)
    log.addWriter(writer)
    log.print("short")
    Swag.require(writer.count == 1)
}

#test
{
    let loc      = currentLocation()
    let expected = makeExpectedShortLine("CORE", loc, "hello")
    var writer   = MemoryLogWriter{expected: expected}

    var log = Log.create()
    log.setPrefix("CORE")
    log.setFlags(LogFlags.Prefix | LogFlags.ShortFileName | LogFlags.Line)
    log.addWriter(writer)
    log.print("hello", loc)

    Swag.require(writer.count == 1)
    Swag.require(log.prefix() == "CORE")
    Swag.require(log.flags() == (LogFlags.Prefix | LogFlags.ShortFileName | LogFlags.Line))
}

#test
{
    let loc      = currentLocation()
    let expected = makeExpectedFullLoc(loc, "world")
    var writerA  = MemoryLogWriter{expected: expected}
    var writerB  = MemoryLogWriter{expected: expected}

    var log = Log.create()
    log.setFlags(LogFlags.LongFileName | LogFlags.FullLoc)
    log.addWriter(writerA)
    log.addWriter(writerB)
    log.print("world", loc)

    Swag.require(writerA.count == 1)
    Swag.require(writerB.count == 1)
}

#test
{
    let secondLoc = currentLocation()
    var expected: String
    expected.append(Path.fileName(secondLoc.fileName))
    expected.append(" ")
    expected.append("second")
    var removedWriter = MemoryLogWriter{expected: "never written"}
    var writer        = MemoryLogWriter{expected: expected}

    var log = Log.create()
    log.setFlags(LogFlags.ShortFileName)

    log.addWriter(removedWriter)
    log.clearWriters()

    log.addWriter(writer)

    log.print("second", secondLoc)

    Swag.require(removedWriter.count == 0)
    Swag.require(writer.count == 1)
}

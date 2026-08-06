#global public

// Flags to control the format of log output.
#[Swag.EnumFlags]
enum LogFlags
{
    None = 0                                                    // No optional header component.
    Prefix                                                      // Include custom prefix in log output.
    Date                                                        // Include date (YYYY/MM/DD).
    Time                                                        // Include time (HH:MM:SS:ms).
    ShortFileName                                               // Include only the file name (exclusive with LongFileName).
    LongFileName                                                // Include full file path (exclusive with ShortFileName).
    Line                                                        // Include only the start line number (exclusive with FullLoc).
    FullLoc                                                     // Include full location (line/col start and end).
    Default = Prefix | Date | Time | LongFileName | FullLoc     // Default logging configuration.
}

// Interface for writing log output.
interface ILogWriter
{
    // Writes one fully formatted log message to the destination.
    mtd print(text: string)
}

// A thread-safe logger that supports multiple output writers and customizable formatting.
struct Log
{
    internal
    {
        lock:        Sync.Mutex                // Protects configuration, writers, and output.
        buf:         StrConv.StringBuilder     // Reused message buffer.
        dt:          Time.DateTime             // Timestamp captured for the current message.
        writers:     Array'ILogWriter          // Registered borrowed writer interfaces.
        prefixText:  String                    // Owned prefix added to each line.
        formatFlags: LogFlags = Default        // Enabled header components.
    }
}

impl Log
{
    // Build the formatted log message header based on the current flags.
    private mtd buildHeader(loc: Swag.SourceCodeLocation)
    {
        if .formatFlags & .Prefix and @countof(.prefixText)
        {
            .buf.appendString(.prefixText)
            .buf.appendString(" ")
        }

        if .formatFlags & .Date
        {
            .buf.appendFormat("%/%{D02}/%{D02} ", .dt.year, .dt.month, .dt.day)
        }

        if .formatFlags & .Time
        {
            .buf.appendFormat("%{D02}:%{D02}:%{D02}:%{D03} ", .dt.hour, .dt.minute, .dt.second, .dt.millisecond)
        }

        if .formatFlags & .ShortFileName
        {
            .buf.appendString(Path.fileName(loc.fileName))
            .buf.appendString(.formatFlags & (.Line | .FullLoc) ? ":" : " ")
        }
        elif .formatFlags & .LongFileName
        {
            .buf.appendString(loc.fileName)
            .buf.appendString(.formatFlags & (.Line | .FullLoc) ? ":" : " ")
        }

        if .formatFlags & .Line
        {
            .buf.appendAny(loc.lineStart)
            .buf.appendString(" ")
        }
        elif .formatFlags & .FullLoc
        {
            .buf.appendFormat("%:%:%:% ", loc.lineStart, loc.colStart, loc.lineEnd, loc.colEnd)
        }
    }

    // Create a new log instance.
    func create()->Log
    {
        var result: retval
        return result
    }

    // Replaces the owned prefix prepended to log messages.
    mtd setPrefix(prefix: string)
    {
        Sync.scopedLock(&.lock)
        .prefixText = prefix
    }

    // Returns an owned snapshot of the current prefix.
    mtd prefix()->String
    {
        Sync.scopedLock(&.lock)
        return .prefixText
    }

    // Set the logger flags.
    mtd setFlags(flags: LogFlags)
    {
        Sync.scopedLock(&.lock)
        .formatFlags = flags
    }

    // Returns the current formatting flags.
    mtd flags()->LogFlags
    {
        Sync.scopedLock(&.lock)
        return .formatFlags
    }

    // Registers a borrowed writer that must outlive its registration.
    mtd addWriter(writer: ILogWriter)
    {
        Sync.scopedLock(&.lock)
        .writers.add(writer)
    }

    // Remove all registered writers.
    mtd clearWriters()
    {
        Sync.scopedLock(&.lock)
        .writers.clear()
    }

    // Print a message to the log with an optional source location.
    mtd print(text: string, loc = #callerlocation)
    {
        // Get this first, to have the time of the call, before the lock
        if .formatFlags & (.Date | .Time) do
            .dt = Time.DateTime.now()

        Sync.scopedLock(&.lock)

        // Build log string
        .buf.clear()
        .buildHeader(loc)
        .buf.appendString(text)
        let rendered:     String = .buf.toString()
        let renderedText: string = rendered.toString()

        // Output default result if no writers
        if .writers.isEmpty()
        {
            Console.lock()
            Console.println(renderedText)
            Console.unlock()
            return
        }

        // Otherwise call all writers
        for w in .writers
        {
            w.print(renderedText)
        }
    }
}

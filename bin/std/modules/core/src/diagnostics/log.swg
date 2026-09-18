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

// Receives the formatted messages of a [[Core.Log]].
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
    // Appends the header components selected by the current flags to the message buffer.
    private mtd buildHeader(loc: Swag.SourceCodeLocation)
    {
        if .formatFlags & .Prefix and not .prefixText.isEmpty()
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

    // Creates a logger with the default flags and no writer.
    func create()->Log => {}

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

    // Replaces the header components written before each message.
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

    // Removes every registered writer, so messages go to the console again.
    mtd clearWriters()
    {
        Sync.scopedLock(&.lock)
        .writers.clear()
    }

    // Writes `text`, after the configured header, to every registered writer or to the console when there is none.
    //
    // `loc` is the source location the header reports; it defaults to the caller.
    mtd print(text: string, loc = #callerlocation)
    {
        // The header reports when the call happened, not when the lock was obtained; the shared
        // fields are only read and written once the lock is held.
        let now = Time.DateTime.now()
        Sync.scopedLock(&.lock)
        if .formatFlags & (.Date | .Time) do
            .dt = now

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
        for w in .writers do
            w.print(renderedText)
    }
}

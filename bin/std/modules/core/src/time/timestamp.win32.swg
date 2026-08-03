#global if WINDOWS
#global namespace Time

public impl Timestamp
{
    // Captures the current UTC wall-clock time.
    func utcNow()->Timestamp
    {
        return fromDateTime(DateTime.utcNow())
    }
}

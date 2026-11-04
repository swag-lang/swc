#global export
#global namespace Http

using Core

// One HTTP request header; both strings are borrowed for the duration of the request.
struct Header
{
    public
    {
        name:  string     // HTTP token field name using ASCII letters, digits, and permitted punctuation.
        value: string     // Field value without control characters.
    }
}

// Limits and headers for a synchronous GET request.
struct GetOptions
{
    public
    {
        headers:      Array'Header                 // Request headers, whose strings are borrowed for the call.
        userAgent:    string = "Swag Net"          // User-Agent sent to the server.
        timeoutMs:    u32    = 15_000              // Timeout in milliseconds: per phase on Windows, whole transfer on Linux.
        maxBodyBytes: u64    = 4 * 1024 * 1024     // Maximum response body size in bytes.
    }
}

// An HTTP response whose body storage is owned by the value.
struct Response
{
    public
    {
        status:   u32          // HTTP status code, including non-success responses.
        body:     Array'u8     // Response body bytes.
        location: String       // Redirect location when supplied; empty otherwise.
    }
}

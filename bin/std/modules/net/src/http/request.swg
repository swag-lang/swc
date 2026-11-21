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

// Receives one response-body chunk and returns whether the transfer should continue.
alias BodyHandler = func(context: *void?, bytes: const [..] u8)->bool

// Fills part or all of a request-body chunk and returns its byte count; zero signals end of input.
alias BodyReader = func(context: *void?, buffer: [..] u8)->u64

// Limits, headers, and optional body streaming callbacks for a synchronous HTTP request.
struct RequestOptions
{
    public
    {
        headers:           Array'Header                 // Request headers, whose strings are borrowed for the call.
        userAgent:         string = "Swag Net"          // User-Agent sent to the server.
        timeoutMs:         u32    = 15_000              // Timeout in milliseconds: per phase on Windows, whole transfer on Linux.
        maxBodyBytes:      u64    = 4 * 1024 * 1024     // Maximum response body size in bytes.
        maxRedirects:      u8                           // Maximum GET redirects to follow; zero returns the redirect response.
        bodyHandler:       BodyHandler?                 // Receives chunks instead of storing the body when supplied.
        bodyContext:       *void?                       // Borrowed state passed to `bodyHandler` for this call.
        requestBodyLength: u64                          // Exact number of bytes the request body reader will produce.
        bodyReader:        BodyReader?                  // Supplies request chunks when sending a streamed body.
        requestContext:    *void?                       // Borrowed state passed to `bodyReader` for this call.
    }
}

// Options accepted by [[Net.Http.get]].
alias GetOptions = RequestOptions

// Options accepted by [[Net.Http.post]].
alias PostOptions = RequestOptions

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

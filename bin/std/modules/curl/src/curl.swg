#global if #os == Swag.TargetOs.Linux
#global export

const CURLE_OK                         = 0's32
const CURLE_FAILED_INIT                = 2's32
const CURLE_NOT_BUILT_IN               = 4's32
const CURLE_OUT_OF_MEMORY              = 27's32
const CURLE_OPERATION_TIMEDOUT         = 28's32
const CURLE_PEER_FAILED_VERIFICATION   = 60's32
const CURLOPT_WRITEDATA                = 10001's32
const CURLOPT_WRITEFUNCTION            = 20011's32
const CURLOPT_USERAGENT                = 10018's32
const CURLOPT_HTTPHEADER               = 10023's32
const CURLOPT_HEADERDATA               = 10029's32
const CURLOPT_NETRC                    = 51's32
const CURLOPT_FOLLOWLOCATION           = 52's32
const CURLOPT_SSL_VERIFYPEER           = 64's32
const CURLOPT_CAINFO                   = 10065's32
const CURLOPT_HEADERFUNCTION           = 20079's32
const CURLOPT_SSL_VERIFYHOST           = 81's32
const CURLOPT_HTTP_VERSION             = 84's32
const CURLOPT_NOSIGNAL                 = 99's32
const CURLOPT_CAPATH                   = 10097's32
const CURLOPT_TIMEOUT_MS               = 155's32
const CURLOPT_CONNECTTIMEOUT_MS        = 156's32
const CURLOPT_PROTOCOLS                = 181's32
const CURLOPT_PROXY_CAINFO = 10246's32
const CURLOPT_PROXY_CAPATH = 10247's32
const CURLOPT_HEADEROPT = 229's32
const CURLOPT_PROXY_SSL_VERIFYPEER     = 248's32
const CURLOPT_PROXY_SSL_VERIFYHOST     = 249's32
const CURLOPT_SUPPRESS_CONNECT_HEADERS = 265's32
const CURLOPT_PATH_AS_IS               = 234's32
const CURLOPT_CURLU                    = 10282's32
const CURLOPT_HTTP09_ALLOWED           = 285's32
const CURLINFO_RESPONSE_CODE           = 2097154's32
const CURLUPART_SCHEME                 = 1's32
const CURLUPART_HOST                   = 5's32
const CURLUPART_PORT                   = 6's32
const CURLUPART_PATH                   = 7's32
const CURLUPART_QUERY                  = 8's32
const CURLUE_OK                        = 0's32
const CURLVERSION_FIRST                = 0's32
const CURL_VERSION_ASYNCHDNS           = 128's32
const CURL_VERSION_THREADSAFE          = 1073741824's32

const CURL_GLOBAL_DEFAULT   = 3's64
const CURL_HTTP_VERSION_1_1 = 2's64
const CURLPROTO_HTTP        = 1's64
const CURLPROTO_HTTPS       = 2's64

struct curl_slist
{
    public
    {
        data: [*]u8
        next: *curl_slist?
    }
}

// The CURLVERSION_FIRST prefix; only this version's fields are read by the consumer.
struct curl_version_info_data
{
    public
    {
        age:             s32
        version:         const [*]u8
        version_num:     u32
        host:            const [*]u8
        features:        s32
        ssl_version:     const [*]u8?
        ssl_version_num: s64
        libz_version:    const [*]u8?
        protocols:       const [*](const [*]u8?)
    }
}

#[Swag.CallingConvention(.C)]
alias curl_global_init_fn    = func(s64)->s32
#[Swag.CallingConvention(.C)]
alias curl_global_cleanup_fn = func()
#[Swag.CallingConvention(.C)]
alias curl_version_info_fn   = func(s32)->const *curl_version_info_data
#[Swag.CallingConvention(.C)]
alias curl_easy_init_fn      = func()->*void?
#[Swag.CallingConvention(.C)]
alias curl_easy_cleanup_fn   = func(*void)
#[Swag.CallingConvention(.C)]
alias curl_easy_setopt_fn    = func(*void, s32, ...)->s32
#[Swag.CallingConvention(.C)]
alias curl_easy_getinfo_fn   = func(*void, s32, ...)->s32
#[Swag.CallingConvention(.C)]
alias curl_easy_perform_fn   = func(*void)->s32
#[Swag.CallingConvention(.C)]
alias curl_slist_append_fn   = func(*curl_slist?, const [*]u8)->*curl_slist?
#[Swag.CallingConvention(.C)]
alias curl_slist_free_all_fn = func(*curl_slist?)
#[Swag.CallingConvention(.C)]
alias curl_url_fn            = func()->*void?
#[Swag.CallingConvention(.C)]
alias curl_url_cleanup_fn    = func(*void)
#[Swag.CallingConvention(.C)]
alias curl_url_set_fn        = func(*void, s32, const [*]u8?, u32)->s32

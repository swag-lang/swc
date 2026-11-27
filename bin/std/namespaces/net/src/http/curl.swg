#global if #os == Swag.TargetOs.Linux
#global internal
#global namespace Curl

/*
Raw libcurl C ABI declarations. Function pointers borrow the loaded library;
the Net backend loads `libcurl.so.4` before resolving its entry points.
*/

const CURLE_OK                         = 0_s32
const CURLE_FAILED_INIT                = 2_s32
const CURLE_NOT_BUILT_IN               = 4_s32
const CURLE_OUT_OF_MEMORY              = 27_s32
const CURLE_OPERATION_TIMEDOUT         = 28_s32
const CURLE_PEER_FAILED_VERIFICATION   = 60_s32
const CURLE_ABORTED_BY_CALLBACK        = 42_s32
const CURLE_READ_ERROR                 = 26_s32
const CURLOPT_URL                      = 10002_s32
const CURLUPART_URL                    = 0_s32
const CURLOPT_WRITEDATA                = 10001_s32
const CURLOPT_WRITEFUNCTION            = 20011_s32
const CURLOPT_USERAGENT                = 10018_s32
const CURLOPT_HTTPHEADER               = 10023_s32
const CURLOPT_HEADERDATA               = 10029_s32
const CURLOPT_NETRC                    = 51_s32
const CURLOPT_FOLLOWLOCATION           = 52_s32
const CURLOPT_MAXREDIRS                = 68_s32
const CURLOPT_SSL_VERIFYPEER           = 64_s32
const CURLOPT_CAINFO                   = 10065_s32
const CURLOPT_HEADERFUNCTION           = 20079_s32
const CURLOPT_SSL_VERIFYHOST           = 81_s32
const CURLOPT_HTTP_VERSION             = 84_s32
const CURLOPT_NOSIGNAL                 = 99_s32
const CURLOPT_CAPATH                   = 10097_s32
const CURLOPT_TIMEOUT_MS               = 155_s32
const CURLOPT_CONNECTTIMEOUT_MS        = 156_s32
const CURLOPT_PROTOCOLS                = 181_s32
const CURLOPT_REDIR_PROTOCOLS          = 182_s32
const CURLOPT_PROXY_CAINFO             = 10246_s32
const CURLOPT_PROXY_CAPATH             = 10247_s32
const CURLOPT_HEADEROPT                = 229_s32
const CURLOPT_PROXY_SSL_VERIFYPEER     = 248_s32
const CURLOPT_PROXY_SSL_VERIFYHOST     = 249_s32
const CURLOPT_SUPPRESS_CONNECT_HEADERS = 265_s32
const CURLOPT_PATH_AS_IS               = 234_s32
const CURLOPT_CURLU                    = 10282_s32
const CURLOPT_HTTP09_ALLOWED           = 285_s32
const CURLOPT_POST                     = 47_s32
const CURLOPT_READDATA                 = 10009_s32
const CURLOPT_READFUNCTION             = 20012_s32
const CURLOPT_POSTFIELDSIZE_LARGE      = 30120_s32
const CURL_READFUNC_ABORT              = 0x10000000_u64
const CURLINFO_RESPONSE_CODE           = 2097154_s32
const CURLUPART_SCHEME                 = 1_s32
const CURLUPART_HOST                   = 5_s32
const CURLUPART_PORT                   = 6_s32
const CURLUPART_PATH                   = 7_s32
const CURLUPART_QUERY                  = 8_s32
const CURLUE_OK                        = 0_s32
const CURLVERSION_FIRST                = 0_s32
const CURL_VERSION_ASYNCHDNS           = 128_s32
const CURL_VERSION_THREADSAFE          = 1073741824_s32

const CURLHEADER_SEPARATE   = 1_s32
const CURL_GLOBAL_DEFAULT   = 3_s64
const CURL_HTTP_VERSION_1_1 = 2_s64
const CURLPROTO_HTTP        = 1_s64
const CURLPROTO_HTTPS       = 2_s64

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

#assert(#sizeof(curl_slist) == 16)
#assert(#offsetof(curl_slist.next) == 8)
#assert(#sizeof(curl_version_info_data) == 72)
#assert(#offsetof(curl_version_info_data.features) == 32)

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

#[Swag.CallingConvention(.C)]
alias curl_url_get_fn        = func(const *void, s32, *([*]u8?), u32)->s32
#[Swag.CallingConvention(.C)]
alias curl_free_fn           = func(*void?)

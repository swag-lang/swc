#global private

func catchFallbackVoid() fail {}

func catchFallbackWithoutResult()
{
    discard catch catchFallbackVoid() orelse 0     // swc-expected-error {{sema_err_catch_fallback_without_result}}
}

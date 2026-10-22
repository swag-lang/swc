#global private

func catchFallbackVoid() fail {}

func catchFallbackWithoutResult()
{
    discard catch catchFallbackVoid() else 0     // swc-expected-error {{sema_err_catch_fallback_without_result}}
}

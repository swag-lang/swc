<?php
// A missing or disabled JIT cannot silently supply an interpreted measurement.
if (in_array('--require-jit', $argv, true)) {
    $status = function_exists('opcache_get_status') ? opcache_get_status(false) : false;
    if (!$status || !($status['jit']['on'] ?? false)) {
        fwrite(STDERR, "PHP tracing JIT is not active\n");
        exit(1);
    }
}

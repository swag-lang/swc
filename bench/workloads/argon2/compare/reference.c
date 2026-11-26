#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <argon2.h>
#include <openssl/core_names.h>
#include <openssl/kdf.h>
#include <openssl/params.h>
#include <openssl/thread.h>

static uint8_t password[] = "parallel benchmark";
static uint8_t salt[] = "benchmark salt!!";

static uint64_t nanoseconds(clockid_t clock)
{
    struct timespec time;
    if (clock_gettime(clock, &time) != 0)
        abort();
    return (uint64_t)time.tv_sec * UINT64_C(1000000000) + (uint64_t)time.tv_nsec;
}

static int benchmark_libargon2(uint32_t memory, uint32_t workers, uint8_t tag[32], uint64_t *elapsed, uint64_t *cpu_elapsed)
{
    uint8_t warmup[32];
    argon2_context context = {
        .out = warmup, .outlen = sizeof warmup,
        .pwd = password, .pwdlen = sizeof password - 1,
        .salt = salt, .saltlen = sizeof salt - 1,
        .t_cost = 3, .m_cost = memory, .lanes = 4, .threads = workers,
        .version = ARGON2_VERSION_13, .flags = ARGON2_DEFAULT_FLAGS,
    };
    if (argon2id_ctx(&context) != ARGON2_OK)
        return 0;

    context.out = tag;
    const uint64_t start = nanoseconds(CLOCK_MONOTONIC);
    const uint64_t cpu_start = nanoseconds(CLOCK_PROCESS_CPUTIME_ID);
    const int status = argon2id_ctx(&context);
    *cpu_elapsed = nanoseconds(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    *elapsed = nanoseconds(CLOCK_MONOTONIC) - start;
    return status == ARGON2_OK && memcmp(warmup, tag, sizeof warmup) == 0;
}

static int benchmark_openssl(uint32_t memory, uint32_t workers, uint8_t tag[32], uint64_t *elapsed, uint64_t *cpu_elapsed)
{
    OSSL_LIB_CTX *library = OSSL_LIB_CTX_new();
    if (library == NULL)
        return 0;
    if (workers > 1 && !OSSL_set_max_threads(library, workers)) {
        OSSL_LIB_CTX_free(library);
        return 0;
    }

    EVP_KDF *algorithm = EVP_KDF_fetch(library, "ARGON2ID", NULL);
    EVP_KDF_CTX *context = algorithm == NULL ? NULL : EVP_KDF_CTX_new(algorithm);
    uint32_t passes = 3, lanes = 4, version = ARGON2_VERSION_13;
    OSSL_PARAM parameters[] = {
        OSSL_PARAM_construct_octet_string(OSSL_KDF_PARAM_PASSWORD, password, sizeof password - 1),
        OSSL_PARAM_construct_octet_string(OSSL_KDF_PARAM_SALT, salt, sizeof salt - 1),
        OSSL_PARAM_construct_uint32(OSSL_KDF_PARAM_ITER, &passes),
        OSSL_PARAM_construct_uint32(OSSL_KDF_PARAM_ARGON2_MEMCOST, &memory),
        OSSL_PARAM_construct_uint32(OSSL_KDF_PARAM_ARGON2_LANES, &lanes),
        OSSL_PARAM_construct_uint32(OSSL_KDF_PARAM_THREADS, &workers),
        OSSL_PARAM_construct_uint32(OSSL_KDF_PARAM_ARGON2_VERSION, &version),
        OSSL_PARAM_construct_end(),
    };

    uint8_t warmup[32];
    int ok = context != NULL && EVP_KDF_derive(context, warmup, sizeof warmup, parameters);
    if (ok) {
        const uint64_t start = nanoseconds(CLOCK_MONOTONIC);
        const uint64_t cpu_start = nanoseconds(CLOCK_PROCESS_CPUTIME_ID);
        ok = EVP_KDF_derive(context, tag, sizeof warmup, parameters);
        *cpu_elapsed = nanoseconds(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
        *elapsed = nanoseconds(CLOCK_MONOTONIC) - start;
        ok = ok && memcmp(warmup, tag, sizeof warmup) == 0;
    }

    EVP_KDF_CTX_free(context);
    EVP_KDF_free(algorithm);
    OSSL_LIB_CTX_free(library);
    return ok;
}

int main(int argc, char **argv)
{
    if (argc != 4)
        return EXIT_FAILURE;
    const uint32_t memory = (uint32_t)strtoul(argv[2], NULL, 10);
    const uint32_t workers = (uint32_t)strtoul(argv[3], NULL, 10);
    uint8_t tag[32];
    uint64_t elapsed, cpu_elapsed;
    int ok = 0;

    if (strcmp(argv[1], "libargon2") == 0)
        ok = benchmark_libargon2(memory, workers, tag, &elapsed, &cpu_elapsed);
    else if (strcmp(argv[1], "openssl") == 0)
        ok = benchmark_openssl(memory, workers, tag, &elapsed, &cpu_elapsed);

    if (!ok)
        return EXIT_FAILURE;

    printf("%llu %llu ", (unsigned long long)(elapsed / 1000), (unsigned long long)(cpu_elapsed / 1000));
    for (size_t i = 0; i < sizeof tag; i++)
        printf("%02x", (unsigned)tag[i]);
    putchar('\n');
    return EXIT_SUCCESS;
}

#define _POSIX_C_SOURCE 200809L

#include <blake3.h>
#include <crc64.h>
#include <isal_api.h>
#include <libdeflate.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <zlib.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* liblzma's public CRC function. */
extern uint64_t lzma_crc64(const uint8_t *, size_t, uint64_t);
extern const char *lzma_version_string(void);

static const unsigned char key[] = "0123456789abcdefghijklmnopqrstuv";
static const unsigned char nonce[] = "0123456789ab";
static const unsigned char chacha_iv[] = "\1\0\0\0" "0123456789ab";
static const unsigned char associated_data[] = "swag-crypto-1";

static EVP_MD *digest;
static EVP_MD_CTX *digest_context;
static EVP_CIPHER *cipher;
static EVP_CIPHER_CTX *cipher_context;
static EVP_MAC *mac;
static EVP_MAC_CTX *mac_context;
static int authenticated;

typedef void (*operation)(const unsigned char *, size_t, unsigned char *);

static void require(int valid, const char *message)
{
    if (!valid) {
        fprintf(stderr, "%s\n", message);
        exit(EXIT_FAILURE);
    }
}

static void store_checksum(unsigned char *output, uint64_t checksum, size_t bytes)
{
    for (size_t index = 0; index < bytes; ++index)
        output[index] = checksum >> (8 * index);
}

static void deflate_adler(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, libdeflate_adler32(1, p, n), 4);
}

static void deflate_crc(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, libdeflate_crc32(0, p, n), 4);
}

static void zlib_adler(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, adler32_z(1, p, n), 4);
}

static void zlib_crc(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, crc32_z(0, p, n), 4);
}

static void isal_ecma(const unsigned char *p, size_t n, unsigned char *out)
{
    /* ISA-L complements the seed and result. ECMA-182 uses zero at both ends. */
    store_checksum(out, ~crc64_ecma_norm(UINT64_MAX, p, n), 8);
}

static void isal_iso(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, crc64_iso_refl(0, p, n), 8);
}

static void isal_xz(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, crc64_ecma_refl(0, p, n), 8);
}

static void xz_crc(const unsigned char *p, size_t n, unsigned char *out)
{
    store_checksum(out, lzma_crc64(p, n, 0), 8);
}

static void hash_blake3(const unsigned char *p, size_t n, unsigned char *out)
{
    blake3_hasher state;
    blake3_hasher_init(&state);
    blake3_hasher_update(&state, p, n);
    blake3_hasher_finalize(&state, out, BLAKE3_OUT_LEN);
}

static void digest_evp(const unsigned char *p, size_t n, unsigned char *out)
{
    require(EVP_DigestInit_ex2(digest_context, digest, NULL) &&
            EVP_DigestUpdate(digest_context, p, n) &&
            EVP_DigestFinal_ex(digest_context, out, NULL), "OpenSSL digest failed");
}

static void mac_evp(const unsigned char *p, size_t n, unsigned char *out)
{
    size_t length = 0;
    require(EVP_MAC_init(mac_context, key, sizeof(key) - 1, NULL) &&
            EVP_MAC_update(mac_context, p, n) &&
            EVP_MAC_final(mac_context, out, &length, 16) && length == 16,
            "OpenSSL Poly1305 failed");
}

static void encrypt_evp(const unsigned char *p, size_t n, unsigned char *out)
{
    const unsigned char *iv = authenticated ? nonce : chacha_iv;
    int used = 0;
    int tail = 0;
    require(EVP_EncryptInit_ex2(cipher_context, cipher, key, iv, NULL),
            "OpenSSL cipher initialization failed");
    if (authenticated)
        require(EVP_EncryptUpdate(cipher_context, NULL, &used, associated_data,
                                  sizeof(associated_data) - 1), "OpenSSL AAD failed");
    require(EVP_EncryptUpdate(cipher_context, out, &used, p, (int)n) &&
            EVP_EncryptFinal_ex(cipher_context, out + used, &tail) &&
            (size_t)(used + tail) == n, "OpenSSL encryption failed");
    if (authenticated)
        require(EVP_CIPHER_CTX_ctrl(cipher_context, EVP_CTRL_AEAD_GET_TAG, 16, out + n),
                "OpenSSL authentication tag failed");
}

static operation select_operation(const char *name, size_t input_size, size_t *result_size)
{
    static const struct { const char *name; operation run; size_t size; } direct[] = {
        {"adler32-libdeflate", deflate_adler, 4},
        {"crc32-libdeflate", deflate_crc, 4},
        {"adler32-zlib", zlib_adler, 4},
        {"crc32-zlib", zlib_crc, 4},
        {"crc64-ecma", isal_ecma, 8},
        {"crc64-iso", isal_iso, 8},
        {"crc64-xz", isal_xz, 8},
        {"crc64-xz-liblzma", xz_crc, 8},
        {"blake3", hash_blake3, 32},
    };
    for (size_t index = 0; index < sizeof(direct) / sizeof(direct[0]); ++index) {
        if (!strcmp(name, direct[index].name)) {
            *result_size = direct[index].size;
            return direct[index].run;
        }
    }

    if (!strcmp(name, "poly1305")) {
        mac = EVP_MAC_fetch(NULL, "POLY1305", NULL);
        require(mac != NULL, "OpenSSL could not fetch Poly1305");
        mac_context = EVP_MAC_CTX_new(mac);
        require(mac_context != NULL, "OpenSSL could not allocate a MAC context");
        *result_size = 16;
        return mac_evp;
    }

    if (!strcmp(name, "chacha20") || !strcmp(name, "chacha20-poly1305") ||
        !strcmp(name, "aes-256-gcm")) {
        authenticated = strcmp(name, "chacha20") != 0;
        cipher = EVP_CIPHER_fetch(NULL, name, NULL);
        require(cipher != NULL, "OpenSSL could not fetch cipher");
        cipher_context = EVP_CIPHER_CTX_new();
        require(cipher_context != NULL, "OpenSSL could not allocate a cipher context");
        *result_size = input_size + (authenticated ? 16 : 0);
        return encrypt_evp;
    }

    digest = EVP_MD_fetch(NULL, name, NULL);
    require(digest != NULL, "OpenSSL could not fetch digest");
    digest_context = EVP_MD_CTX_new();
    require(digest_context != NULL, "OpenSSL could not allocate a digest context");
    *result_size = EVP_MD_get_size(digest);
    return digest_evp;
}

static uint64_t clock_ticks(clockid_t clock)
{
    struct timespec stamp;
    require(clock_gettime(clock, &stamp) == 0, "clock_gettime failed");
    return stamp.tv_sec * UINT64_C(1000000000) + stamp.tv_nsec;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        printf("%s | zlib %s | BLAKE3 %s | libdeflate %s | ISA-L %s | liblzma %s\n",
               OpenSSL_version(OPENSSL_VERSION), zlibVersion(), blake3_version(),
               LIBDEFLATE_VERSION_STRING, isal_get_version_str(), lzma_version_string());
        return EXIT_SUCCESS;
    }

    require(argc == 6, "Usage: reference ALGORITHM INPUT OUTPUT ITERATIONS OFFSET");
    char *end;
    const uint64_t iterations = strtoull(argv[4], &end, 10);
    require(*end == '\0' && iterations > 0, "Expected positive iterations");
    const size_t offset = strtoull(argv[5], &end, 10);
    require(*end == '\0', "Expected numeric offset");

    FILE *file = fopen(argv[2], "rb");
    require(file != NULL && fseek(file, 0, SEEK_END) == 0, "Could not open input");
    const long length = ftell(file);
    require(length >= 0 && length <= INT32_MAX && (size_t)length >= offset, "Invalid input size");
    require(fseek(file, 0, SEEK_SET) == 0, "Could not seek to input start");
    unsigned char *input = malloc(length ? (size_t)length : 1);
    require(input != NULL && fread(input, 1, length, file) == (size_t)length,
            "Could not read input");
    require(fclose(file) == 0, "Could not close input");

    const size_t size = length - offset;
    size_t result_size;
    const operation run = select_operation(argv[1], size, &result_size);
    unsigned char *result = malloc(result_size ? result_size : 1);
    require(result != NULL, "Could not allocate result");

    run(input + offset, size, result);
    const uint64_t wall_start = clock_ticks(CLOCK_MONOTONIC);
    const uint64_t cpu_start = clock_ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (uint64_t iteration = 0; iteration < iterations; ++iteration)
        run(input + offset, size, result);
    const uint64_t cpu_elapsed = clock_ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const uint64_t wall_elapsed = clock_ticks(CLOCK_MONOTONIC) - wall_start;

    file = fopen(argv[3], "wb");
    require(file != NULL && fwrite(result, 1, result_size, file) == result_size,
            "Could not write result");
    require(fclose(file) == 0, "Could not close result");
    printf("%llu %llu 1000000000\n", (unsigned long long)wall_elapsed,
           (unsigned long long)cpu_elapsed);

    EVP_MD_CTX_free(digest_context);
    EVP_MD_free(digest);
    EVP_CIPHER_CTX_free(cipher_context);
    EVP_CIPHER_free(cipher);
    EVP_MAC_CTX_free(mac_context);
    EVP_MAC_free(mac);
    free(input);
    free(result);
    return EXIT_SUCCESS;
}

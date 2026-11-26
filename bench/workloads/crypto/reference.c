#define _POSIX_C_SOURCE 200809L

#include <blake3.h>
#include <crc64.h>
#include <isal_api.h>
#include <libdeflate.h>
#include <openssl/core_names.h>
#include <openssl/crypto.h>
#include <openssl/ec.h>
#include <openssl/evp.h>
#include <openssl/param_build.h>
#include <zlib.h>

#ifdef SWAG_BENCH_BLAKE2_REFERENCES
#include <blake2.h>
#include <sodium.h>
#endif

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
static const unsigned char aes_ctr_iv[] = "0123456789abcdef";
static const unsigned char chacha_iv[] = "\1\0\0\0" "0123456789ab";
static const unsigned char associated_data[] = "swag-crypto-1";

static EVP_MD *digest;
static EVP_MD_CTX *digest_context;
static EVP_CIPHER *cipher;
static EVP_CIPHER_CTX *cipher_context;
static EVP_MAC *mac;
static EVP_MAC_CTX *mac_context;
static size_t mac_size;
static int authenticated;
static int use_aes_ctr;
static EC_GROUP *p256_group;
static EC_POINT *p256_point;
static BN_CTX *p256_context;
static BIGNUM *p256_scalar;
static EVP_PKEY_CTX *p256_import_context;
static OSSL_PARAM *p256_key_parameters;

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

#ifdef SWAG_BENCH_BLAKE2_REFERENCES
static void blake2b_libb2(const unsigned char *p, size_t n, unsigned char *out)
{
    require(blake2b(out, p, NULL, 64, n, 0) == 0, "libb2 BLAKE2b failed");
}

static void blake2s_libb2(const unsigned char *p, size_t n, unsigned char *out)
{
    require(blake2s(out, p, NULL, 32, n, 0) == 0, "libb2 BLAKE2s failed");
}

static void blake2b_sodium(const unsigned char *p, size_t n, unsigned char *out)
{
    require(crypto_generichash_blake2b(out, 64, p, n, NULL, 0) == 0, "libsodium BLAKE2b failed");
}
#endif

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
            EVP_MAC_final(mac_context, out, &length, mac_size) && length == mac_size,
            "OpenSSL MAC failed");
}

static void encrypt_evp(const unsigned char *p, size_t n, unsigned char *out)
{
    const unsigned char *iv = use_aes_ctr ? aes_ctr_iv : (authenticated ? nonce : chacha_iv);
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

static void authenticate_aad_evp(const unsigned char *p, size_t n, unsigned char *out)
{
    int used = 0;
    require(EVP_EncryptInit_ex2(cipher_context, cipher, key, nonce, NULL) &&
            EVP_EncryptUpdate(cipher_context, NULL, &used, p, (int)n) &&
            EVP_EncryptFinal_ex(cipher_context, out, &used) && used == 0 &&
            EVP_CIPHER_CTX_ctrl(cipher_context, EVP_CTRL_AEAD_GET_TAG, 16, out),
            "OpenSSL AAD authentication failed");
}

static EVP_PKEY *import_private(const char *name, const unsigned char *bytes, size_t size)
{
    EVP_PKEY *private_key = EVP_PKEY_new_raw_private_key_ex(NULL, name, NULL, bytes, size);
    require(private_key != NULL, "OpenSSL could not import private key");
    return private_key;
}

static void export_raw_public(const char *name, const unsigned char *p, size_t n,
                              unsigned char *out)
{
    EVP_PKEY *private_key = import_private(name, p, n);
    size_t used = 32;
    require(EVP_PKEY_get_raw_public_key(private_key, out, &used) && used == 32,
            "OpenSSL could not derive raw public key");
    EVP_PKEY_free(private_key);
}

static void x25519_public(const unsigned char *p, size_t n, unsigned char *out)
{
    export_raw_public("X25519", p, n, out);
}

static void x25519_shared(const unsigned char *p, size_t n, unsigned char *out)
{
    EVP_PKEY *private_key = import_private("X25519", key, sizeof(key) - 1);
    EVP_PKEY *peer = EVP_PKEY_new_raw_public_key_ex(NULL, "X25519", NULL, p, n);
    EVP_PKEY_CTX *context = EVP_PKEY_CTX_new_from_pkey(NULL, private_key, NULL);
    size_t used = 32;
    require(peer && context && EVP_PKEY_derive_init(context) &&
            EVP_PKEY_derive_set_peer(context, peer) &&
            EVP_PKEY_derive(context, out, &used) && used == 32,
            "OpenSSL could not derive X25519 shared key");
    EVP_PKEY_CTX_free(context);
    EVP_PKEY_free(peer);
    EVP_PKEY_free(private_key);
}

static void ed25519_public(const unsigned char *p, size_t n, unsigned char *out)
{
    export_raw_public("ED25519", p, n, out);
}

static void ed25519_sign(const unsigned char *p, size_t n, unsigned char *out)
{
    EVP_PKEY *private_key = import_private("ED25519", key, sizeof(key) - 1);
    size_t used = 64;
    require(EVP_DigestSignInit(digest_context, NULL, NULL, NULL, private_key) &&
            EVP_DigestSign(digest_context, out, &used, p, n) && used == 64,
            "OpenSSL could not sign with Ed25519");
    EVP_PKEY_free(private_key);
}

static void p256_public(const unsigned char *p, size_t n, unsigned char *out)
{
    require(n == 32 && BN_bin2bn(p, (int)n, p256_scalar) &&
            EC_POINT_mul(p256_group, p256_point, p256_scalar, NULL, NULL, p256_context) &&
            EC_POINT_point2oct(p256_group, p256_point, POINT_CONVERSION_UNCOMPRESSED,
                               out, 65, p256_context) == 65,
            "OpenSSL could not derive P-256 public key");
}

static void prepare_p256_sign(void)
{
    p256_import_context = EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL);
    digest_context = EVP_MD_CTX_new();
    require(p256_import_context && digest_context &&
            EVP_PKEY_fromdata_init(p256_import_context), "OpenSSL P-256 signing setup failed");

    OSSL_PARAM_BLD *builder = OSSL_PARAM_BLD_new();
    BIGNUM *scalar = BN_bin2bn(key, sizeof(key) - 1, NULL);
    require(builder && scalar &&
            OSSL_PARAM_BLD_push_utf8_string(builder, OSSL_PKEY_PARAM_GROUP_NAME, "prime256v1", 0) &&
            OSSL_PARAM_BLD_push_BN(builder, OSSL_PKEY_PARAM_PRIV_KEY, scalar),
            "OpenSSL could not build P-256 key parameters");
    p256_key_parameters = OSSL_PARAM_BLD_to_param(builder);
    require(p256_key_parameters != NULL, "OpenSSL could not encode P-256 key parameters");
    BN_clear_free(scalar);
    OSSL_PARAM_BLD_free(builder);
}

static void p256_sign(const unsigned char *p, size_t n, unsigned char *out)
{
    EVP_PKEY *private_key = NULL;
    require(EVP_PKEY_fromdata(p256_import_context, &private_key, EVP_PKEY_KEYPAIR,
                              p256_key_parameters) && private_key, "OpenSSL P-256 key import failed");
    unsigned int deterministic_nonce = 1;
    OSSL_PARAM params[] = {
        OSSL_PARAM_construct_uint(OSSL_SIGNATURE_PARAM_NONCE_TYPE, &deterministic_nonce),
        OSSL_PARAM_construct_end(),
    };
    unsigned char der[80];
    size_t used = sizeof(der);
    require(EVP_DigestSignInit_ex(digest_context, NULL, "SHA256", NULL, NULL, private_key, params) &&
            EVP_DigestSign(digest_context, der, &used, p, n), "OpenSSL P-256 signing failed");

    const unsigned char *cursor = der;
    ECDSA_SIG *signature = d2i_ECDSA_SIG(NULL, &cursor, (long)used);
    require(signature && cursor == der + used &&
            BN_bn2binpad(ECDSA_SIG_get0_r(signature), out, 32) == 32 &&
            BN_bn2binpad(ECDSA_SIG_get0_s(signature), out + 32, 32) == 32,
            "OpenSSL could not serialize the P-256 signature");
    ECDSA_SIG_free(signature);
    EVP_PKEY_free(private_key);
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
        {"x25519-public", x25519_public, 32},
        {"x25519-shared", x25519_shared, 32},
        {"ed25519-public", ed25519_public, 32},
    };
    for (size_t index = 0; index < sizeof(direct) / sizeof(direct[0]); ++index) {
        if (!strcmp(name, direct[index].name)) {
            *result_size = direct[index].size;
            return direct[index].run;
        }
    }

    if (!strcmp(name, "ed25519-sign")) {
        digest_context = EVP_MD_CTX_new();
        require(digest_context != NULL, "OpenSSL could not allocate a signing context");
        *result_size = 64;
        return ed25519_sign;
    }

    if (!strcmp(name, "p256-public")) {
        p256_group = EC_GROUP_new_by_curve_name(NID_X9_62_prime256v1);
        require(p256_group != NULL, "OpenSSL could not create the P-256 group");
        p256_point = EC_POINT_new(p256_group);
        p256_context = BN_CTX_new();
        p256_scalar = BN_new();
        require(p256_point && p256_context && p256_scalar,
                "OpenSSL could not allocate P-256 state");
        BN_set_flags(p256_scalar, BN_FLG_CONSTTIME);
        *result_size = 65;
        return p256_public;
    }

    if (!strcmp(name, "p256-sign")) {
        prepare_p256_sign();
        *result_size = 64;
        return p256_sign;
    }

    const int poly1305 = !strcmp(name, "poly1305");
    const int hmac384 = !strcmp(name, "hmac-sha384");
    const int hmac512 = !strcmp(name, "hmac-sha512");
    if (poly1305 || hmac384 || hmac512) {
        mac = EVP_MAC_fetch(NULL, poly1305 ? "POLY1305" : "HMAC", NULL);
        require(mac != NULL, "OpenSSL could not fetch MAC");
        mac_context = EVP_MAC_CTX_new(mac);
        require(mac_context != NULL, "OpenSSL could not allocate a MAC context");
        if (!poly1305) {
            char sha384[] = "SHA384";
            char sha512[] = "SHA512";
            OSSL_PARAM params[] = {
                OSSL_PARAM_construct_utf8_string(OSSL_MAC_PARAM_DIGEST, hmac384 ? sha384 : sha512, 0),
                OSSL_PARAM_construct_end(),
            };
            require(EVP_MAC_CTX_set_params(mac_context, params), "OpenSSL could not set HMAC digest");
        }
        mac_size = poly1305 ? 16 : hmac384 ? 48 : 64;
        *result_size = mac_size;
        return mac_evp;
    }

    if (!strcmp(name, "aes-256-gcm-aad")) {
        cipher = EVP_CIPHER_fetch(NULL, "aes-256-gcm", NULL);
        require(cipher != NULL, "OpenSSL could not fetch AES-256-GCM");
        cipher_context = EVP_CIPHER_CTX_new();
        require(cipher_context != NULL, "OpenSSL could not allocate a cipher context");
        *result_size = 16;
        return authenticate_aad_evp;
    }

    if (!strcmp(name, "chacha20") || !strcmp(name, "chacha20-poly1305") ||
        !strcmp(name, "aes-256-gcm") || !strcmp(name, "aes-256-ctr")) {
        use_aes_ctr = !strcmp(name, "aes-256-ctr");
        authenticated = !use_aes_ctr && strcmp(name, "chacha20") != 0;
        cipher = EVP_CIPHER_fetch(NULL, name, NULL);
        require(cipher != NULL, "OpenSSL could not fetch cipher");
        cipher_context = EVP_CIPHER_CTX_new();
        require(cipher_context != NULL, "OpenSSL could not allocate a cipher context");
        *result_size = input_size + (authenticated ? 16 : 0);
        return encrypt_evp;
    }

#ifdef SWAG_BENCH_BLAKE2_REFERENCES
    if (!strcmp(name, "blake2b-libb2")) {
        *result_size = 64;
        return blake2b_libb2;
    }

    if (!strcmp(name, "blake2s-libb2")) {
        *result_size = 32;
        return blake2s_libb2;
    }

    if (!strcmp(name, "blake2b-libsodium")) {
        require(sodium_init() >= 0, "libsodium initialization failed");
        *result_size = 64;
        return blake2b_sodium;
    }
#endif

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
        printf("%s | zlib %s | BLAKE3 %s | libdeflate %s | ISA-L %s | liblzma %s",
               OpenSSL_version(OPENSSL_VERSION), zlibVersion(), blake3_version(),
               LIBDEFLATE_VERSION_STRING, isal_get_version_str(), lzma_version_string());
#ifdef SWAG_BENCH_BLAKE2_REFERENCES
        printf(" | libb2 | libsodium %s", sodium_version_string());
#endif
        putchar('\n');
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
    EVP_PKEY_CTX_free(p256_import_context);
    OSSL_PARAM_free(p256_key_parameters);
    BN_clear_free(p256_scalar);
    BN_CTX_free(p256_context);
    EC_POINT_free(p256_point);
    EC_GROUP_free(p256_group);
    free(input);
    free(result);
    return EXIT_SUCCESS;
}

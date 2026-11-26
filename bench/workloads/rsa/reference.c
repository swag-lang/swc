#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/param_build.h>
#include <openssl/rsa.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum operation {
    PSS_VERIFY,
    OAEP_DECRYPT,
    OAEP_DECRYPT_D_ONLY
};

struct fixture {
    unsigned char *storage;
    size_t width;
    size_t message_len;
    size_t exponent_len;
    const unsigned char *n;
    const unsigned char *d;
    const unsigned char *e;
    const unsigned char *signature;
    const unsigned char *ciphertext;
    const unsigned char *message;
    const unsigned char *crt[5];
};

static void require(int success, const char *description)
{
    if (success)
        return;

    fprintf(stderr, "%s\n", description);
    ERR_print_errors_fp(stderr);
    exit(EXIT_FAILURE);
}

static uint64_t parse_count(const char *value)
{
    char *end;
    require(value[0] >= '0' && value[0] <= '9', "invalid process argument");
    errno = 0;
    const unsigned long long count = strtoull(value, &end, 10);
    require(errno == 0 && *end == '\0' && count <= UINT64_MAX, "invalid process argument");
    return (uint64_t)count;
}

static enum operation parse_operation(const char *value)
{
    if (strcmp(value, "rsa-pss-verify") == 0)
        return PSS_VERIFY;
    if (strcmp(value, "rsa-oaep-decrypt") == 0)
        return OAEP_DECRYPT;

    require(strcmp(value, "rsa-oaep-decrypt-d-only") == 0, "invalid operation");
    return OAEP_DECRYPT_D_ONLY;
}

static uint32_t load32le(const unsigned char *value)
{
    return (uint32_t)value[0] | (uint32_t)value[1] << 8 |
           (uint32_t)value[2] << 16 | (uint32_t)value[3] << 24;
}

static struct fixture load_fixture(const char *path, size_t offset)
{
    FILE *input = fopen(path, "rb");
    require(input != NULL, "cannot open fixture");
    require(fseek(input, 0, SEEK_END) == 0, "cannot seek fixture");
    const long file_size = ftell(input);
    require(file_size >= 12 && file_size <= 4096, "invalid fixture size");
    require(fseek(input, 0, SEEK_SET) == 0, "cannot rewind fixture");

    struct fixture fixture;
    const size_t size = (size_t)file_size;
    fixture.storage = malloc(size + offset);
    require(fixture.storage != NULL, "cannot allocate fixture");
    unsigned char *bytes = fixture.storage + offset;
    require(fread(bytes, 1, size, input) == size, "cannot read fixture");
    require(fclose(input) == 0, "cannot close fixture");

    fixture.width = load32le(bytes);
    fixture.message_len = load32le(bytes + 4);
    fixture.exponent_len = load32le(bytes + 8);
    require(fixture.width >= 256 && fixture.width <= 512 && fixture.width % 4 == 0,
            "invalid modulus width");
    require(fixture.message_len <= fixture.width - 66, "invalid message width");
    require(fixture.exponent_len != 0 && fixture.exponent_len <= fixture.width,
            "invalid public exponent width");
    require(size == 12 + 4 * fixture.width + fixture.exponent_len + fixture.message_len +
                    5 * (fixture.width / 2),
            "invalid fixture layout");

    fixture.n = bytes + 12;
    fixture.d = fixture.n + fixture.width;
    fixture.e = fixture.d + fixture.width;
    fixture.signature = fixture.e + fixture.exponent_len;
    fixture.ciphertext = fixture.signature + fixture.width;
    fixture.message = fixture.ciphertext + fixture.width;
    for (size_t i = 0; i < 5; ++i)
        fixture.crt[i] = fixture.message + fixture.message_len + i * (fixture.width / 2);
    return fixture;
}

static EVP_PKEY *import_key(const struct fixture *fixture, enum operation operation)
{
    struct rsa_parameter {
        const char *name;
        const unsigned char *bytes;
        size_t width;
    } values[] = {
        {OSSL_PKEY_PARAM_RSA_N, fixture->n, fixture->width},
        {OSSL_PKEY_PARAM_RSA_E, fixture->e, fixture->exponent_len},
        {OSSL_PKEY_PARAM_RSA_D, fixture->d, fixture->width},
        {OSSL_PKEY_PARAM_RSA_FACTOR1, fixture->crt[0], fixture->width / 2},
        {OSSL_PKEY_PARAM_RSA_FACTOR2, fixture->crt[1], fixture->width / 2},
        {OSSL_PKEY_PARAM_RSA_EXPONENT1, fixture->crt[2], fixture->width / 2},
        {OSSL_PKEY_PARAM_RSA_EXPONENT2, fixture->crt[3], fixture->width / 2},
        {OSSL_PKEY_PARAM_RSA_COEFFICIENT1, fixture->crt[4], fixture->width / 2}
    };
    size_t value_count = sizeof(values) / sizeof(values[0]);
    if (operation == PSS_VERIFY)
        value_count = 2;
    if (operation == OAEP_DECRYPT_D_ONLY)
        value_count = 3;

    OSSL_PARAM_BLD *builder = OSSL_PARAM_BLD_new();
    require(builder != NULL, "cannot allocate RSA parameter builder");
    BIGNUM *integers[sizeof(values) / sizeof(values[0])];
    for (size_t i = 0; i < value_count; ++i) {
        integers[i] = BN_bin2bn(values[i].bytes, (int)values[i].width, NULL);
        require(integers[i] != NULL, "cannot parse RSA key component");
        require(OSSL_PARAM_BLD_push_BN(builder, values[i].name, integers[i]) == 1,
                "cannot add RSA key component");
    }

    OSSL_PARAM *parameters = OSSL_PARAM_BLD_to_param(builder);
    require(parameters != NULL, "cannot materialize RSA key parameters");
    EVP_PKEY_CTX *context = EVP_PKEY_CTX_new_from_name(NULL, "RSA", NULL);
    require(context != NULL, "cannot allocate RSA key context");
    require(EVP_PKEY_fromdata_init(context) == 1, "cannot initialize RSA key import");
    EVP_PKEY *key = NULL;
    const int selection = operation == PSS_VERIFY ? EVP_PKEY_PUBLIC_KEY : EVP_PKEY_KEYPAIR;
    require(EVP_PKEY_fromdata(context, &key, selection, parameters) == 1,
            "cannot import RSA key");
    require(EVP_PKEY_get_size(key) == (int)fixture->width, "wrong imported RSA key size");

    BIGNUM *factor = NULL;
    const int has_factor = EVP_PKEY_get_bn_param(key, OSSL_PKEY_PARAM_RSA_FACTOR1, &factor);
    require(has_factor == (operation == OAEP_DECRYPT), "unexpected imported RSA factors");
    BN_clear_free(factor);

    EVP_PKEY_CTX_free(context);
    OSSL_PARAM_free(parameters);
    OSSL_PARAM_BLD_free(builder);
    for (size_t i = 0; i < value_count; ++i)
        BN_clear_free(integers[i]);
    return key;
}

static uint64_t timestamp(clockid_t clock)
{
    struct timespec value;
    require(clock_gettime(clock, &value) == 0, "cannot read benchmark clock");
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

static void run_pss(EVP_PKEY_CTX *key_context, EVP_MD_CTX *digest_context, const EVP_MD *sha256,
                    const struct fixture *fixture)
{
    unsigned char digest[32];
    unsigned int digest_len;
    require(EVP_DigestInit_ex2(digest_context, sha256, NULL) == 1, "cannot initialize SHA256");
    require(EVP_DigestUpdate(digest_context, fixture->message, fixture->message_len) == 1,
            "cannot hash PSS message");
    require(EVP_DigestFinal_ex(digest_context, digest, &digest_len) == 1 && digest_len == sizeof(digest),
            "cannot finalize PSS digest");
    require(EVP_PKEY_verify(key_context, fixture->signature, fixture->width, digest, digest_len) == 1,
            "RSA PSS verification failed");
}

static size_t run_oaep(EVP_PKEY_CTX *context, const struct fixture *fixture, unsigned char *output)
{
    size_t length = fixture->width;
    require(EVP_PKEY_decrypt(context, output, &length, fixture->ciphertext, fixture->width) == 1,
            "RSA OAEP decryption failed");
    return length;
}

static void check_plaintext(const struct fixture *fixture, const unsigned char *output, size_t length)
{
    require(length == fixture->message_len && memcmp(output, fixture->message, length) == 0,
            "RSA OAEP plaintext mismatch");
}

static void save_output(const char *path, const unsigned char *output, size_t length)
{
    FILE *file = fopen(path, "wb");
    require(file != NULL, "cannot open output");
    require(fwrite(output, 1, length, file) == length, "cannot write output");
    require(fclose(file) == 0, "cannot close output");
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts(OpenSSL_version(OPENSSL_VERSION));
        return EXIT_SUCCESS;
    }

    require(argc == 6, "usage: openssl-rsa OPERATION FIXTURE OUT ITERATIONS OFFSET");
    const enum operation operation = parse_operation(argv[1]);
    const uint64_t iterations = parse_count(argv[4]);
    const uint64_t offset = parse_count(argv[5]);
    require(iterations != 0 && offset <= 4096, "iterations or offset out of range");
    const struct fixture fixture = load_fixture(argv[2], (size_t)offset);

    EVP_PKEY *key = import_key(&fixture, operation);
    EVP_PKEY_CTX *key_context = EVP_PKEY_CTX_new_from_pkey(NULL, key, NULL);
    require(key_context != NULL, "cannot allocate operation context");
    EVP_MD *sha256 = EVP_MD_fetch(NULL, "SHA256", NULL);
    require(sha256 != NULL, "cannot fetch SHA256");

    unsigned char output[512];
    size_t output_len = 1;
    uint64_t wall_start;
    uint64_t cpu_start;
    uint64_t wall_elapsed;
    uint64_t cpu_elapsed;
    if (operation == PSS_VERIFY) {
        require(EVP_PKEY_verify_init(key_context) == 1, "cannot initialize RSA verification");
        require(EVP_PKEY_CTX_set_rsa_padding(key_context, RSA_PKCS1_PSS_PADDING) == 1,
                "cannot set PSS padding");
        require(EVP_PKEY_CTX_set_signature_md(key_context, sha256) == 1,
                "cannot set PSS message digest");
        require(EVP_PKEY_CTX_set_rsa_mgf1_md(key_context, sha256) == 1, "cannot set PSS MGF1 digest");
        require(EVP_PKEY_CTX_set_rsa_pss_saltlen(key_context, 32) == 1, "cannot set PSS salt width");
        EVP_MD_CTX *digest_context = EVP_MD_CTX_new();
        require(digest_context != NULL, "cannot allocate digest context");

        run_pss(key_context, digest_context, sha256, &fixture);
        wall_start = timestamp(CLOCK_MONOTONIC);
        cpu_start = timestamp(CLOCK_PROCESS_CPUTIME_ID);
        for (uint64_t i = 0; i < iterations; ++i)
            run_pss(key_context, digest_context, sha256, &fixture);
        cpu_elapsed = timestamp(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
        wall_elapsed = timestamp(CLOCK_MONOTONIC) - wall_start;

        EVP_MD_CTX_free(digest_context);
        output[0] = 1;
    }
    else {
        require(EVP_PKEY_decrypt_init(key_context) == 1, "cannot initialize RSA decryption");
        require(EVP_PKEY_CTX_set_rsa_padding(key_context, RSA_PKCS1_OAEP_PADDING) == 1,
                "cannot set OAEP padding");
        require(EVP_PKEY_CTX_set_rsa_oaep_md(key_context, sha256) == 1, "cannot set OAEP digest");
        require(EVP_PKEY_CTX_set_rsa_mgf1_md(key_context, sha256) == 1, "cannot set OAEP MGF1 digest");

        output_len = run_oaep(key_context, &fixture, output);
        check_plaintext(&fixture, output, output_len);
        wall_start = timestamp(CLOCK_MONOTONIC);
        cpu_start = timestamp(CLOCK_PROCESS_CPUTIME_ID);
        for (uint64_t i = 0; i < iterations; ++i)
            output_len = run_oaep(key_context, &fixture, output);
        cpu_elapsed = timestamp(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
        wall_elapsed = timestamp(CLOCK_MONOTONIC) - wall_start;
        check_plaintext(&fixture, output, output_len);
    }

    save_output(argv[3], output, output_len);
    printf("%" PRIu64 " %" PRIu64 " 1000000000\n", wall_elapsed, cpu_elapsed);

    EVP_MD_free(sha256);
    EVP_PKEY_CTX_free(key_context);
    EVP_PKEY_free(key);
    free(fixture.storage);
    return EXIT_SUCCESS;
}

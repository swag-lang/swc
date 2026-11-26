#define _POSIX_C_SOURCE 200809L

#include <openssl/crypto.h>
#include <openssl/evp.h>

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void require(int ok, const char *message)
{
    if (!ok) {
        fprintf(stderr, "%s\n", message);
        exit(EXIT_FAILURE);
    }
}

static uint64_t microseconds(clockid_t clock)
{
    struct timespec now;
    require(clock_gettime(clock, &now) == 0, "could not read clock");
    return (uint64_t)now.tv_sec * UINT64_C(1000000) + (uint64_t)now.tv_nsec / 1000;
}

struct profile {
    const EVP_MD *digest;
    const unsigned char *password;
    const unsigned char *salt;
    size_t password_size;
    size_t salt_size;
    size_t key_size;
    uint64_t cost;
    uint64_t block;
};

static int derive(const struct profile *p, unsigned char *key)
{
    if (p->digest) {
        return PKCS5_PBKDF2_HMAC((const char *)p->password, (int)p->password_size,
                                p->salt, (int)p->salt_size, (int)p->cost,
                                p->digest, (int)p->key_size, key);
    }
    return EVP_PBE_scrypt((const char *)p->password, p->password_size,
                          p->salt, p->salt_size, p->cost, p->block, 1,
                          UINT64_C(1024) * 1024 * 1024, key, p->key_size);
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts(OpenSSL_version(OPENSSL_VERSION));
        return EXIT_SUCCESS;
    }

    struct profile p = {0};
    unsigned char *password = NULL;
    unsigned char *salt = NULL;
    if (argc == 4 && !strcmp(argv[1], "scrypt")) {
        p.password = (const unsigned char *)"parallel benchmark";
        p.salt = (const unsigned char *)"benchmark salt!!";
        p.password_size = strlen((const char *)p.password);
        p.salt_size = strlen((const char *)p.salt);
        p.key_size = 32;
        p.cost = strtoull(argv[2], NULL, 10);
        p.block = strtoull(argv[3], NULL, 10);
    } else {
        require(argc == 7 && !strcmp(argv[1], "pbkdf2"), "invalid profile");
        p.digest = EVP_get_digestbyname(argv[2]);
        p.cost = strtoull(argv[3], NULL, 10);
        p.password_size = strtoull(argv[4], NULL, 10);
        p.salt_size = strtoull(argv[5], NULL, 10);
        p.key_size = strtoull(argv[6], NULL, 10);
        require(p.digest && p.cost && p.cost <= INT_MAX && p.password_size <= INT_MAX &&
                p.salt_size <= INT_MAX && p.key_size && p.key_size <= INT_MAX, "invalid PBKDF2 profile");
        password = malloc(p.password_size ? p.password_size : 1);
        salt = malloc(p.salt_size ? p.salt_size : 1);
        require(password && salt, "could not allocate input");
        for (size_t i = 0; i < p.password_size; ++i)
            password[i] = (unsigned char)(i * 31 + 17);
        for (size_t i = 0; i < p.salt_size; ++i)
            salt[i] = (unsigned char)(i * 47 + 29);
        p.password = password;
        p.salt = salt;
    }

    unsigned char *key = malloc(p.key_size);
    unsigned char *warmup = malloc(p.key_size);
    require(key && warmup, "could not allocate output");
    require(derive(&p, warmup), "OpenSSL warm-up failed");
    const uint64_t wall_start = microseconds(CLOCK_MONOTONIC);
    const uint64_t cpu_start = microseconds(CLOCK_PROCESS_CPUTIME_ID);
    const int success = derive(&p, key);
    const uint64_t cpu = microseconds(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const uint64_t wall = microseconds(CLOCK_MONOTONIC) - wall_start;
    require(success && !memcmp(warmup, key, p.key_size), "OpenSSL output mismatch");
    printf("%llu %llu ", (unsigned long long)wall, (unsigned long long)cpu);
    for (size_t i = 0; i < p.key_size; ++i)
        printf("%02x", key[i]);
    putchar('\n');

    OPENSSL_cleanse(warmup, p.key_size);
    OPENSSL_cleanse(key, p.key_size);
    free(warmup);
    free(key);
    free(password);
    free(salt);
    return EXIT_SUCCESS;
}

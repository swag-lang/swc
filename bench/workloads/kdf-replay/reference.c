#include <nettle/hmac.h>
#include <nettle/pbkdf2.h>
#include <sodium.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

int kdf_scrypt(const uint8_t *password, size_t password_size, const uint8_t *salt,
               size_t salt_size, uint64_t cost, uint32_t block, uint32_t parallel,
               uint8_t *key, size_t key_size)
{
    return crypto_pwhash_scryptsalsa208sha256_ll(password, password_size, salt, salt_size,
                                                cost, block, parallel, key, key_size);
}

int kdf_pbkdf2(const char *algorithm, const uint8_t *password, size_t password_size,
               const uint8_t *salt, size_t salt_size, unsigned iterations,
               uint8_t *key, size_t key_size)
{
    if (strcmp(algorithm, "sha224") == 0) {
        struct hmac_sha224_ctx hmac;
        hmac_sha224_set_key(&hmac, password_size, password);
        PBKDF2(&hmac, hmac_sha224_update, hmac_sha224_digest, SHA224_DIGEST_SIZE,
               iterations, salt_size, salt, key_size, key);
        sodium_memzero(&hmac, sizeof(hmac));
    } else if (strcmp(algorithm, "sha256") == 0) {
        pbkdf2_hmac_sha256(password_size, password, iterations, salt_size, salt, key_size, key);
    } else if (strcmp(algorithm, "sha384") == 0) {
        pbkdf2_hmac_sha384(password_size, password, iterations, salt_size, salt, key_size, key);
    } else if (strcmp(algorithm, "sha512") == 0) {
        pbkdf2_hmac_sha512(password_size, password, iterations, salt_size, salt, key_size, key);
    } else {
        return -1;
    }
    return 0;
}

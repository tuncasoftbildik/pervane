#ifndef CSMC_H
#define CSMC_H
#include <stdint.h>
#include <IOKit/IOKitLib.h>

// AppleSMC kullanıcı istemcisiyle konuşan ince katman.
// Okuma yetkisiz çalışır; yazma root ister.

typedef struct {
    char     key[5];
    char     type[5];
    uint32_t size;
    uint8_t  bytes[32];
} smc_val_t;

kern_return_t smc_open(io_connect_t *conn);
void          smc_close(io_connect_t conn);
kern_return_t smc_read(io_connect_t conn, const char *key, smc_val_t *out);
kern_return_t smc_write(io_connect_t conn, const char *key, const uint8_t *bytes, uint32_t size);
kern_return_t smc_key_count(io_connect_t conn, uint32_t *count);
kern_return_t smc_key_at(io_connect_t conn, uint32_t index, char key[5]);

#endif

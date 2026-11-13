#include "csmc.h"
#include <string.h>

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_INDEX    8
#define SMC_CMD_READ_KEYINFO  9

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } smc_vers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } smc_plimit_t;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } smc_keyinfo_t;

typedef struct {
    uint32_t      key;
    smc_vers_t    vers;
    smc_plimit_t  pLimitData;
    smc_keyinfo_t keyInfo;
    uint8_t       result;
    uint8_t       status;
    uint8_t       data8;
    uint32_t      data32;
    uint8_t       bytes[32];
} smc_param_t;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8)  |  (uint32_t)(uint8_t)s[3];
}

static void unfourcc(uint32_t v, char out[5]) {
    out[0] = (char)(v >> 24); out[1] = (char)(v >> 16);
    out[2] = (char)(v >> 8);  out[3] = (char)v; out[4] = 0;
}

static kern_return_t smc_call(io_connect_t conn, smc_param_t *in, smc_param_t *out) {
    size_t outSize = sizeof(smc_param_t);
    kern_return_t kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(smc_param_t), out, &outSize);
    if (kr != KERN_SUCCESS) return kr;
    // SMC kendi hata kodunu result alanında döndürür (0x84 = anahtar yok).
    if (out->result != 0) return kIOReturnError;
    return KERN_SUCCESS;
}

kern_return_t smc_open(io_connect_t *conn) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return kIOReturnNoDevice;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, conn);
    IOObjectRelease(svc);
    return kr;
}

void smc_close(io_connect_t conn) { IOServiceClose(conn); }

static kern_return_t smc_keyinfo(io_connect_t conn, uint32_t key, smc_keyinfo_t *info) {
    smc_param_t in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t kr = smc_call(conn, &in, &out);
    if (kr == KERN_SUCCESS) *info = out.keyInfo;
    return kr;
}

kern_return_t smc_read(io_connect_t conn, const char *key, smc_val_t *val) {
    memset(val, 0, sizeof *val);
    if (strlen(key) != 4) return kIOReturnBadArgument;
    smc_keyinfo_t info;
    kern_return_t kr = smc_keyinfo(conn, fourcc(key), &info);
    if (kr != KERN_SUCCESS) return kr;
    if (info.dataSize > 32) return kIOReturnOverrun;

    smc_param_t in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    kr = smc_call(conn, &in, &out);
    if (kr != KERN_SUCCESS) return kr;

    memcpy(val->key, key, 4);
    unfourcc(info.dataType, val->type);
    val->size = info.dataSize;
    memcpy(val->bytes, out.bytes, info.dataSize);
    return KERN_SUCCESS;
}

kern_return_t smc_write(io_connect_t conn, const char *key, const uint8_t *bytes, uint32_t size) {
    if (strlen(key) != 4 || size > 32) return kIOReturnBadArgument;
    smc_keyinfo_t info;
    kern_return_t kr = smc_keyinfo(conn, fourcc(key), &info);
    if (kr != KERN_SUCCESS) return kr;
    if (info.dataSize != size) return kIOReturnBadArgument;

    smc_param_t in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.keyInfo.dataSize = size;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, bytes, size);
    return smc_call(conn, &in, &out);
}

kern_return_t smc_key_count(io_connect_t conn, uint32_t *count) {
    smc_val_t v;
    kern_return_t kr = smc_read(conn, "#KEY", &v);
    if (kr != KERN_SUCCESS) return kr;
    *count = ((uint32_t)v.bytes[0] << 24) | ((uint32_t)v.bytes[1] << 16) | ((uint32_t)v.bytes[2] << 8) | v.bytes[3];
    return KERN_SUCCESS;
}

kern_return_t smc_key_at(io_connect_t conn, uint32_t index, char key[5]) {
    smc_param_t in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = index;
    kern_return_t kr = smc_call(conn, &in, &out);
    if (kr != KERN_SUCCESS) return kr;
    unfourcc(out.key, key);
    return KERN_SUCCESS;
}

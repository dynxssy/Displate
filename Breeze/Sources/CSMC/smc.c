#include "smc.h"
#include <string.h>

#define KERNEL_INDEX_SMC 2

enum {
    kSMCReadBytes = 5,
    kSMCWriteBytes = 6,
    kSMCReadIndex = 8,
    kSMCReadKeyInfo = 9,
};

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCKeyDataVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} SMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    SMCKeyDataVersion vers;
    SMCKeyDataPLimit pLimitData;
    SMCKeyDataKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

kern_return_t SMCOpen(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}

void SMCClose(io_connect_t connection) {
    IOServiceClose(connection);
}

static kern_return_t SMCCall(io_connect_t connection, SMCKeyData *input, SMCKeyData *output) {
    size_t outputSize = sizeof(SMCKeyData);
    kern_return_t result = IOConnectCallStructMethod(connection, KERNEL_INDEX_SMC, input, sizeof(SMCKeyData), output, &outputSize);
    if (result != KERN_SUCCESS) return result;
    return output->result == 0 ? KERN_SUCCESS : kIOReturnError;
}

kern_return_t SMCGetKeyInfo(io_connect_t connection, uint32_t key, uint32_t *dataSize, uint32_t *dataType) {
    SMCKeyData input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = kSMCReadKeyInfo;
    kern_return_t result = SMCCall(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    *dataSize = output.keyInfo.dataSize;
    *dataType = output.keyInfo.dataType;
    return KERN_SUCCESS;
}

kern_return_t SMCReadKey(io_connect_t connection, uint32_t key, uint32_t dataSize, uint8_t *bytes) {
    if (dataSize > 32) return kIOReturnBadArgument;
    SMCKeyData input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = dataSize;
    input.data8 = kSMCReadBytes;
    kern_return_t result = SMCCall(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    memcpy(bytes, output.bytes, dataSize);
    return KERN_SUCCESS;
}

kern_return_t SMCWriteKey(io_connect_t connection, uint32_t key, uint32_t dataSize, const uint8_t *bytes) {
    if (dataSize > 32) return kIOReturnBadArgument;
    SMCKeyData input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = dataSize;
    input.data8 = kSMCWriteBytes;
    memcpy(input.bytes, bytes, dataSize);
    return SMCCall(connection, &input, &output);
}

kern_return_t SMCKeyAtIndex(io_connect_t connection, uint32_t index, uint32_t *key) {
    SMCKeyData input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = kSMCReadIndex;
    input.data32 = index;
    kern_return_t result = SMCCall(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    *key = output.key;
    return KERN_SUCCESS;
}

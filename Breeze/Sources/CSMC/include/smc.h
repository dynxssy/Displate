#ifndef CSMC_H
#define CSMC_H

#include <IOKit/IOKitLib.h>
#include <stdint.h>

/// Opens a connection to the AppleSMC user client. Returns KERN_SUCCESS on success.
kern_return_t SMCOpen(io_connect_t *connection);
void SMCClose(io_connect_t connection);

/// Size and type (four-character code, e.g. 'flt ') of a key.
kern_return_t SMCGetKeyInfo(io_connect_t connection, uint32_t key, uint32_t *dataSize, uint32_t *dataType);

/// Reads up to 32 bytes of a key whose size is already known.
kern_return_t SMCReadKey(io_connect_t connection, uint32_t key, uint32_t dataSize, uint8_t *bytes);

/// Writes a key. Requires root.
kern_return_t SMCWriteKey(io_connect_t connection, uint32_t key, uint32_t dataSize, const uint8_t *bytes);

/// The key at an index, for enumerating every key ('#KEY' holds the count).
kern_return_t SMCKeyAtIndex(io_connect_t connection, uint32_t index, uint32_t *key);

#endif

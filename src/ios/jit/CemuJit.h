#pragma once
// JIT memory for the iOS port.
//
// iOS never allows a page to be writable and executable at the same time. Cemu's
// ARM64 recompiler generates code into normal heap memory and then calls
// CemuJit_Commit(), which copies it into a region that is mapped twice:
//   - an RX view that the CPU executes from
//   - an RW alias of the same physical pages that we write through
//
// The RX region is obtained in one of two ways:
//   - TXM devices (iOS 26+, e.g. iPhone 17): StikDebug "universal" protocol.
//     After the debugger attached (CS_DEBUGGED) the app executes `brk #0xf00d`
//     with x16=1 (prepare region) and x16=0 (detach).
//   - Older devices/iOS versions: while debugged, an anonymous mapping can be
//     remapped and protected RX directly.
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
	CemuJitMode_Auto = 0,
	CemuJitMode_TXM = 1,    // StikDebug brk #0xf00d protocol
	CemuJitMode_Legacy = 2, // debugged process, mprotect RX alias
} CemuJitMode;

// true if a debugger has attached and marked the process CS_DEBUGGED (required for JIT)
bool CemuJit_IsProcessDebugged(void);
// true if this device/OS needs the TXM protocol (iOS 26 or newer)
bool CemuJit_DeviceUsesTXM(void);
// sets up the JIT arena. Must be called after CemuJit_IsProcessDebugged() returned true.
// For the TXM protocol this also detaches the debugger again.
bool CemuJit_Initialize(CemuJitMode mode, size_t arenaSize);
bool CemuJit_IsReady(void);
// short description of the last error (empty if none)
const char* CemuJit_LastError(void);
size_t CemuJit_ArenaSize(void);
size_t CemuJit_ArenaUsed(void);

// copies code into the arena and returns the executable address, or NULL if the arena is full
void* CemuJit_Commit(const void* code, size_t size);
// releases a block previously returned by CemuJit_Commit
void CemuJit_Free(void* executableCode, size_t size);

#ifdef __cplusplus
}
#endif

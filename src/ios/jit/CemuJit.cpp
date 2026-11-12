#include "CemuJit.h"

#include <atomic>
#include <cstdint>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <unistd.h>

extern "C" int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);
#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000

// ---------------------------------------------------------------------------
// StikDebug universal JIT protocol (iOS 26 / TXM)
// x16 selects the operation, x0/x1 carry address and size, x0 returns the RX address.

extern "C" __attribute__((noinline, optnone, naked)) void* CemuJit26PrepareRegion(void* addr, size_t len)
{
	__asm__ volatile(
		"mov x16, #1\n"
		"brk #0xf00d\n"
		"ret\n");
}

extern "C" __attribute__((noinline, optnone, naked)) void CemuJit26Detach(void)
{
	__asm__ volatile(
		"mov x16, #0\n"
		"brk #0xf00d\n"
		"ret\n");
}

// ---------------------------------------------------------------------------

namespace
{
	std::mutex s_mutex;
	std::atomic_bool s_ready{false};
	std::string s_lastError;

	uint8_t* s_rx = nullptr;   // executable view
	uint8_t* s_rw = nullptr;   // writable alias
	size_t s_size = 0;
	size_t s_used = 0;

	// free list: offset -> size, coalesced on insert
	std::map<size_t, size_t> s_free;

	constexpr size_t kAlign = 16;

	size_t AlignUp(size_t v) { return (v + (kAlign - 1)) & ~(kAlign - 1); }

	bool CreateRWAlias(uint8_t* rx, size_t size, uint8_t** rwOut)
	{
		vm_address_t rw = 0;
		vm_prot_t cur = 0, max = 0;
		kern_return_t kr = vm_remap(mach_task_self(), &rw, size, 0, VM_FLAGS_ANYWHERE, mach_task_self(),
									(vm_address_t)rx, FALSE, &cur, &max, VM_INHERIT_NONE);
		if (kr != KERN_SUCCESS)
		{
			s_lastError = "vm_remap failed (" + std::to_string(kr) + ")";
			return false;
		}
		kr = vm_protect(mach_task_self(), rw, size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
		if (kr != KERN_SUCCESS)
		{
			s_lastError = "vm_protect RW alias failed (" + std::to_string(kr) + ")";
			vm_deallocate(mach_task_self(), rw, size);
			return false;
		}
		*rwOut = (uint8_t*)rw;
		return true;
	}

	bool InitTXM(size_t size)
	{
		void* rx = CemuJit26PrepareRegion(nullptr, size);
		if (!rx || rx == (void*)-1)
		{
			s_lastError = "StikDebug did not prepare a JIT region";
			CemuJit26Detach();
			return false;
		}
		uint8_t* rw = nullptr;
		if (!CreateRWAlias((uint8_t*)rx, size, &rw))
		{
			CemuJit26Detach();
			return false;
		}
		CemuJit26Detach();
		s_rx = (uint8_t*)rx;
		s_rw = rw;
		return true;
	}

	bool InitLegacy(size_t size)
	{
		void* base = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
		if (base == MAP_FAILED)
		{
			s_lastError = "mmap of JIT arena failed";
			return false;
		}
		uint8_t* rw = nullptr;
		// the original mapping becomes the RX view, the remapped alias stays RW
		if (!CreateRWAlias((uint8_t*)base, size, &rw))
		{
			munmap(base, size);
			return false;
		}
		if (mprotect(base, size, PROT_READ | PROT_EXEC) != 0)
		{
			s_lastError = "mprotect RX failed, JIT is not enabled for this process";
			vm_deallocate(mach_task_self(), (vm_address_t)rw, size);
			munmap(base, size);
			return false;
		}
		s_rx = (uint8_t*)base;
		s_rw = rw;
		return true;
	}

	int IOSMajorVersion()
	{
		char buf[32]{};
		size_t len = sizeof(buf);
		if (sysctlbyname("kern.osproductversion", buf, &len, nullptr, 0) != 0)
			return 0;
		return atoi(buf);
	}
}

extern "C" bool CemuJit_IsProcessDebugged(void)
{
	uint32_t flags = 0;
	if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0)
		return false;
	return (flags & CS_DEBUGGED) != 0;
}

extern "C" bool CemuJit_DeviceUsesTXM(void)
{
	return IOSMajorVersion() >= 26;
}

extern "C" bool CemuJit_Initialize(CemuJitMode mode, size_t arenaSize)
{
	std::lock_guard _l(s_mutex);
	if (s_ready)
		return true;
	s_lastError.clear();
	if (!CemuJit_IsProcessDebugged())
	{
		s_lastError = "process is not debugged, enable JIT first";
		return false;
	}
	const size_t page = (size_t)getpagesize();
	arenaSize = (arenaSize + page - 1) & ~(page - 1);
	if (mode == CemuJitMode_Auto)
		mode = CemuJit_DeviceUsesTXM() ? CemuJitMode_TXM : CemuJitMode_Legacy;

	bool ok = (mode == CemuJitMode_TXM) ? InitTXM(arenaSize) : InitLegacy(arenaSize);
	if (!ok)
		return false;
	s_size = arenaSize;
	s_used = 0;
	s_free.clear();
	s_free.emplace(0, arenaSize);
	s_ready = true;
	return true;
}

extern "C" bool CemuJit_IsReady(void)
{
	return s_ready;
}

extern "C" const char* CemuJit_LastError(void)
{
	return s_lastError.c_str();
}

extern "C" size_t CemuJit_ArenaSize(void)
{
	return s_size;
}

extern "C" size_t CemuJit_ArenaUsed(void)
{
	return s_used;
}

extern "C" void* CemuJit_Commit(const void* code, size_t size)
{
	if (!s_ready || size == 0)
		return nullptr;
	const size_t need = AlignUp(size);
	size_t offset = 0;
	{
		std::lock_guard _l(s_mutex);
		auto it = s_free.begin();
		for (; it != s_free.end(); ++it)
			if (it->second >= need)
				break;
		if (it == s_free.end())
			return nullptr;
		offset = it->first;
		const size_t remaining = it->second - need;
		s_free.erase(it);
		if (remaining)
			s_free.emplace(offset + need, remaining);
		s_used += need;
	}
	memcpy(s_rw + offset, code, size);
	sys_icache_invalidate(s_rx + offset, size);
	return s_rx + offset;
}

extern "C" void CemuJit_Free(void* executableCode, size_t size)
{
	if (!s_ready || !executableCode || size == 0)
		return;
	uint8_t* p = (uint8_t*)executableCode;
	if (p < s_rx || p >= s_rx + s_size)
		return;
	size_t offset = (size_t)(p - s_rx);
	size_t len = AlignUp(size);
	std::lock_guard _l(s_mutex);
	s_used -= std::min(s_used, len);
	auto next = s_free.lower_bound(offset);
	// merge with previous block
	if (next != s_free.begin())
	{
		auto prev = std::prev(next);
		if (prev->first + prev->second == offset)
		{
			offset = prev->first;
			len += prev->second;
			s_free.erase(prev);
		}
	}
	// merge with next block
	if (next != s_free.end() && offset + len == next->first)
	{
		len += next->second;
		s_free.erase(next);
	}
	s_free.emplace(offset, len);
}

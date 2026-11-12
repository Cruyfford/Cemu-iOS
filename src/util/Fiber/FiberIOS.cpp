// Fiber implementation for iOS (arm64).
// The ucontext API is not usable on iOS, so this switches stacks with a small
// hand written context switch that saves the AAPCS64 callee-saved registers.
#include "Fiber.h"
#include <atomic>
#include <cstdlib>

thread_local Fiber* sCurrentFiber{};

struct FiberContextIOS
{
	void* sp; // saved stack pointer of a suspended fiber
};

extern "C" void cemu_fiber_switch(void** saveSp, void* newSp);
extern "C" void cemu_fiber_trampoline();

// frame layout (176 bytes): x19..x30 (12 regs, 96 bytes), d8..d15 (8 regs, 64 bytes), 16 bytes padding
__asm__(
	".text\n"
	".p2align 2\n"
	".globl _cemu_fiber_switch\n"
	"_cemu_fiber_switch:\n"
	"	sub sp, sp, #176\n"
	"	stp x19, x20, [sp, #0]\n"
	"	stp x21, x22, [sp, #16]\n"
	"	stp x23, x24, [sp, #32]\n"
	"	stp x25, x26, [sp, #48]\n"
	"	stp x27, x28, [sp, #64]\n"
	"	stp x29, x30, [sp, #80]\n"
	"	stp d8, d9, [sp, #96]\n"
	"	stp d10, d11, [sp, #112]\n"
	"	stp d12, d13, [sp, #128]\n"
	"	stp d14, d15, [sp, #144]\n"
	"	mov x2, sp\n"
	"	str x2, [x0]\n"
	"	mov sp, x1\n"
	"	ldp x19, x20, [sp, #0]\n"
	"	ldp x21, x22, [sp, #16]\n"
	"	ldp x23, x24, [sp, #32]\n"
	"	ldp x25, x26, [sp, #48]\n"
	"	ldp x27, x28, [sp, #64]\n"
	"	ldp x29, x30, [sp, #80]\n"
	"	ldp d8, d9, [sp, #96]\n"
	"	ldp d10, d11, [sp, #112]\n"
	"	ldp d12, d13, [sp, #128]\n"
	"	ldp d14, d15, [sp, #144]\n"
	"	add sp, sp, #176\n"
	"	ret\n"
	".p2align 2\n"
	".globl _cemu_fiber_trampoline\n"
	"_cemu_fiber_trampoline:\n"
	"	mov x0, x20\n"
	"	mov x29, #0\n"
	"	blr x19\n"
	"	brk #0x1\n" // fiber entry points must never return
);

Fiber::Fiber(void(*FiberEntryPoint)(void* userParam), void* userParam, void* privateData) : m_privateData(privateData)
{
	auto* ctx = (FiberContextIOS*)malloc(sizeof(FiberContextIOS));
	const size_t stackSize = 2 * 1024 * 1024;
	m_stackPtr = malloc(stackSize);
	uintptr_t top = ((uintptr_t)m_stackPtr + stackSize) & ~(uintptr_t)15;
	uint64* frame = (uint64*)(top - 176);
	memset(frame, 0, 176);
	frame[0] = (uint64)FiberEntryPoint; // x19
	frame[1] = (uint64)userParam;       // x20
	frame[11] = (uint64)&cemu_fiber_trampoline; // x30 (lr)
	ctx->sp = frame;
	m_implData = ctx;
}

Fiber::Fiber(void* privateData) : m_privateData(privateData)
{
	auto* ctx = (FiberContextIOS*)malloc(sizeof(FiberContextIOS));
	ctx->sp = nullptr;
	m_implData = ctx;
	m_stackPtr = nullptr;
}

Fiber::~Fiber()
{
	if (m_stackPtr)
		free(m_stackPtr);
	free(m_implData);
}

Fiber* Fiber::PrepareCurrentThread(void* privateData)
{
	cemu_assert_debug(sCurrentFiber == nullptr);
	sCurrentFiber = new Fiber(privateData);
	return sCurrentFiber;
}

void Fiber::Switch(Fiber& targetFiber)
{
	Fiber* leavingFiber = sCurrentFiber;
	sCurrentFiber = &targetFiber;
	std::atomic_thread_fence(std::memory_order_seq_cst);
	auto* from = (FiberContextIOS*)leavingFiber->m_implData;
	auto* to = (FiberContextIOS*)targetFiber.m_implData;
	cemu_fiber_switch(&from->sp, to->sp);
	std::atomic_thread_fence(std::memory_order_seq_cst);
}

void* Fiber::GetFiberPrivateData()
{
	return sCurrentFiber->m_privateData;
}

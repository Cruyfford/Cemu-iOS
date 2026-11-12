#pragma once
#include <atomic>
#include <mutex>
#include <string>

namespace iosState
{
	extern std::mutex g_errorMutex;
	extern std::string g_lastError;
	extern std::atomic<double> g_fps;
	extern std::atomic_bool g_gameLoaded;
}

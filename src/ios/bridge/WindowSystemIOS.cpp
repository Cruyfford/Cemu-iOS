// WindowSystem implementation for the iOS frontend.
// The SwiftUI app owns the views; this file only stores the state Cemu queries.
#include "Common/precompiled.h"
#include "gui/interface/WindowSystem.h"
#include "IOSState.h"

WindowSystem::WindowInfo g_window_info{};

namespace iosState
{
	std::mutex g_errorMutex;
	std::string g_lastError;
	std::atomic<double> g_fps{0.0};
	std::atomic_bool g_gameLoaded{false};
}

void WindowSystem::Create()
{
	// the iOS app drives initialization through CemuBridge_Initialize()
}

void WindowSystem::ShowErrorDialog(std::string_view message, std::string_view title, std::optional<WindowSystem::ErrorCategory> /*errorCategory*/)
{
	cemuLog_log(LogType::Force, "Error dialog: {} {}", title, message);
	std::lock_guard _l(iosState::g_errorMutex);
	if (!iosState::g_lastError.empty())
		iosState::g_lastError.append("\n\n");
	if (!title.empty())
	{
		iosState::g_lastError.append(title);
		iosState::g_lastError.append(": ");
	}
	iosState::g_lastError.append(message);
}

WindowSystem::WindowInfo& WindowSystem::GetWindowInfo()
{
	return g_window_info;
}

void WindowSystem::UpdateWindowTitles(bool isIdle, bool isLoading, double fps)
{
	iosState::g_fps = (isIdle || isLoading) ? 0.0 : fps;
}

void WindowSystem::GetWindowSize(int& w, int& h)
{
	w = g_window_info.width;
	h = g_window_info.height;
}

void WindowSystem::GetPadWindowSize(int& w, int& h)
{
	if (g_window_info.pad_open)
	{
		w = g_window_info.pad_width;
		h = g_window_info.pad_height;
	}
	else
	{
		w = 0;
		h = 0;
	}
}

void WindowSystem::GetWindowPhysSize(int& w, int& h)
{
	w = g_window_info.phys_width;
	h = g_window_info.phys_height;
}

void WindowSystem::GetPadWindowPhysSize(int& w, int& h)
{
	if (g_window_info.pad_open)
	{
		w = g_window_info.phys_pad_width;
		h = g_window_info.phys_pad_height;
	}
	else
	{
		w = 0;
		h = 0;
	}
}

double WindowSystem::GetWindowDPIScale()
{
	return g_window_info.dpi_scale;
}

double WindowSystem::GetPadDPIScale()
{
	return g_window_info.pad_open ? g_window_info.pad_dpi_scale.load() : 1.0;
}

bool WindowSystem::IsPadWindowOpen()
{
	return g_window_info.pad_open;
}

bool WindowSystem::IsKeyDown(uint32 key)
{
	return g_window_info.get_keystate(key);
}

bool WindowSystem::IsKeyDown(PlatformKeyCodes /*platformKey*/)
{
	// no keyboard shortcuts on iOS (TAB/CTRL screen swapping is exposed through the frontend instead)
	return false;
}

std::string WindowSystem::GetKeyCodeName(uint32 button)
{
	static const char* names[] = {"A", "B", "X", "Y", "L", "R", "ZL", "ZR", "+", "-", "Up", "Down", "Left", "Right", "L-Stick", "R-Stick", "Home", "Screen", "Mic"};
	if (button < std::size(names))
		return names[button];
	return fmt::format("button_{}", button);
}

bool WindowSystem::InputConfigWindowHasFocus()
{
	return false;
}

void WindowSystem::NotifyGameLoaded()
{
	iosState::g_gameLoaded = true;
}

void WindowSystem::NotifyGameExited()
{
	iosState::g_gameLoaded = false;
}

void WindowSystem::RefreshGameList()
{
}

void WindowSystem::CaptureInput(const ControllerState& /*currentState*/, const ControllerState& /*lastState*/)
{
}

bool WindowSystem::IsFullScreen()
{
	return true;
}

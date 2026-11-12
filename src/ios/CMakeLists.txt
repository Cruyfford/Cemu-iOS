# Cemu core packaged as a static library for the native iOS app (ios/ at the repository root).
add_library(CemuIOSCore STATIC
	../main.cpp
	../mainLLE.cpp
	bridge/CemuBridge.h
	bridge/CemuBridge.mm
	bridge/IOSState.h
	bridge/WindowSystemIOS.cpp
	jit/CemuJit.h
	jit/CemuJit.cpp
)

cemu_use_precompiled_header(CemuIOSCore)

target_include_directories(CemuIOSCore PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/.." "${CMAKE_CURRENT_SOURCE_DIR}/bridge")

target_link_libraries(CemuIOSCore PUBLIC
	CemuAudio
	CemuCafe
	CemuCommon
	CemuComponents
	CemuConfig
	CemuGui
	CemuInput
	CemuUtil
	CemuResource
	imguiImpl
)

target_link_libraries(CemuIOSCore PUBLIC
	"-framework Foundation"
	"-framework UIKit"
	"-framework Metal"
	"-framework QuartzCore"
	"-framework AudioToolbox"
	"-framework AVFoundation"
	"-framework CoreAudio"
	"-framework CoreServices"
	"-framework Security"
	"-framework SystemConfiguration"
)

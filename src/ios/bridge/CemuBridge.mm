// Glue between the SwiftUI frontend and the Cemu core (replaces the wxWidgets CemuApp/MainWindow).
#include "Common/precompiled.h"
#include "Common/version.h"
#include "CemuBridge.h"
#include "IOSState.h"
#include "ios/jit/CemuJit.h"

#include "gui/interface/WindowSystem.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"
#include "config/NetworkSettings.h"
#include "config/LaunchSettings.h"
#include "Cafe/CafeSystem.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cafe/TitleList/TitleInfo.h"
#include "Cafe/Filesystem/fsc.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Core/LatteOverlay.h"
#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cemu/ncrypto/ncrypto.h"
#include "input/InputManager.h"
#include "input/api/Keyboard/KeyboardControllerProvider.h"
#include "input/api/Keyboard/KeyboardController.h"
#include "input/emulated/VPADController.h"
#include "util/helpers/helpers.h"

#include <rapidjson/document.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

void CemuCommonInit(); // main.cpp
void HandlePostUpdate();

extern WindowSystem::WindowInfo g_window_info;

namespace
{
	std::atomic_bool s_initialized{false};
	std::atomic_bool s_exitRequested{false};
	std::atomic_bool s_running{false};

	void* s_tvLayer = nullptr;
	void* s_padLayer = nullptr;
	bool s_renderersCreated = false;
	bool s_padLayerCreated = false;

	// analog input written by the UI thread, read by the input thread
	std::mutex s_analogMutex;
	glm::vec2 s_axis{}, s_rotation{}, s_trigger{};

	char* DupString(const std::string& s)
	{
		char* r = (char*)malloc(s.size() + 1);
		memcpy(r, s.c_str(), s.size() + 1);
		return r;
	}

	std::string ToJSON(const rapidjson::Document& d)
	{
		rapidjson::StringBuffer buf;
		rapidjson::Writer<rapidjson::StringBuffer> w(buf);
		d.Accept(w);
		return buf.GetString();
	}

	const char* RegionToString(CafeConsoleRegion r)
	{
		switch (r)
		{
		case CafeConsoleRegion::JPN: return "JPN";
		case CafeConsoleRegion::USA: return "USA";
		case CafeConsoleRegion::EUR: return "EUR";
		case CafeConsoleRegion::CHN: return "CHN";
		case CafeConsoleRegion::KOR: return "KOR";
		case CafeConsoleRegion::TWN: return "TWN";
		default: break;
		}
		if (HAS_FLAG(r, CafeConsoleRegion::USA) && HAS_FLAG(r, CafeConsoleRegion::EUR))
			return "ALL";
		return "UNK";
	}

	const char* FormatToString(TitleInfo::TitleDataFormat f)
	{
		switch (f)
		{
		case TitleInfo::TitleDataFormat::HOST_FS: return "Folder";
		case TitleInfo::TitleDataFormat::WUD: return "WUD";
		case TitleInfo::TitleDataFormat::WIIU_ARCHIVE: return "WUA";
		case TitleInfo::TitleDataFormat::NUS: return "NUS";
		case TitleInfo::TitleDataFormat::WUHB: return "WUHB";
		default: return "Other";
		}
	}

	// ported from CemuApp::CreateDefaultMLCFiles
	bool CreateDefaultMLCFiles(const fs::path& mlc)
	{
		const fs::path directories[] = {
			mlc,
			mlc / "sys",
			mlc / "usr",
			mlc / "usr/title/00050000",
			mlc / "usr/title/0005000c",
			mlc / "usr/title/0005000e",
			mlc / "usr/save/00050010/1004a000/user/common/db",
			mlc / "usr/save/00050010/1004a100/user/common/db",
			mlc / "usr/save/00050010/1004a200/user/common/db",
			mlc / "sys/title/0005001b/1005c000/content"
		};
		std::error_code ec;
		for (auto& path : directories)
		{
			if (!fs::exists(path, ec) && !fs::create_directories(path, ec))
				return false;
		}
		try
		{
			const auto langDir = fs::path(mlc).append("sys/title/0005001b/1005c000/content");
			auto langFile = fs::path(langDir).append("language.txt");
			if (!fs::exists(langFile))
			{
				std::ofstream file(langFile);
				const char* langStrings[] = {"ja", "en", "fr", "de", "it", "es", "zh", "ko", "nl", "pt", "ru", "zh"};
				for (const char* lang : langStrings)
					file << fmt::format(R"("{}",)", lang) << std::endl;
			}
			auto countryFile = fs::path(langDir).append("country.txt");
			if (!fs::exists(countryFile))
			{
				std::ofstream file(countryFile);
				for (sint32 i = 0; i < NCrypto::GetCountryCount(); i++)
				{
					const char* countryCode = NCrypto::GetCountryAsString(i);
					if (boost::iequals(countryCode, "NN"))
						file << "NULL," << std::endl;
					else
						file << fmt::format(R"("{}",)", countryCode) << std::endl;
				}
			}
		}
		catch (const std::exception&)
		{
			return false;
		}
		return true;
	}

	// GamePad (VPAD) on player slot 0, fed by the touch overlay / external controllers
	void SetupDefaultInput()
	{
		auto& im = InputManager::instance();
		auto existing = im.get_vpad_controller(0);
		if (existing && !existing->get_controllers().empty())
			return; // user profile already present
		auto keyboard = std::make_shared<KeyboardController>();
		auto vpad = im.set_controller(0, EmulatedController::Type::VPAD, keyboard);
		if (!vpad)
			return;
		auto map = [&](uint64 mapping, uint64 button) { vpad->set_mapping(mapping, keyboard, button); };
		map(VPADController::kButtonId_A, CemuButton_A);
		map(VPADController::kButtonId_B, CemuButton_B);
		map(VPADController::kButtonId_X, CemuButton_X);
		map(VPADController::kButtonId_Y, CemuButton_Y);
		map(VPADController::kButtonId_L, CemuButton_L);
		map(VPADController::kButtonId_R, CemuButton_R);
		map(VPADController::kButtonId_ZL, CemuButton_ZL);
		map(VPADController::kButtonId_ZR, CemuButton_ZR);
		map(VPADController::kButtonId_Plus, CemuButton_Plus);
		map(VPADController::kButtonId_Minus, CemuButton_Minus);
		map(VPADController::kButtonId_Up, CemuButton_Up);
		map(VPADController::kButtonId_Down, CemuButton_Down);
		map(VPADController::kButtonId_Left, CemuButton_Left);
		map(VPADController::kButtonId_Right, CemuButton_Right);
		map(VPADController::kButtonId_StickL, CemuButton_StickL);
		map(VPADController::kButtonId_StickR, CemuButton_StickR);
		map(VPADController::kButtonId_Home, CemuButton_Home);
		map(VPADController::kButtonId_Screen, CemuButton_Screen);
		map(VPADController::kButtonId_Mic, CemuButton_Mic);
		map(VPADController::kButtonId_StickL_Up, kAxisYP);
		map(VPADController::kButtonId_StickL_Down, kAxisYN);
		map(VPADController::kButtonId_StickL_Left, kAxisXN);
		map(VPADController::kButtonId_StickL_Right, kAxisXP);
		map(VPADController::kButtonId_StickR_Up, kRotationYP);
		map(VPADController::kButtonId_StickR_Down, kRotationYN);
		map(VPADController::kButtonId_StickR_Left, kRotationXN);
		map(VPADController::kButtonId_StickR_Right, kRotationXP);
		im.save(0);
	}

	class IOSSystemImplementation : public CafeSystem::SystemImplementation
	{
	public:
		void CafeRecreateCanvas() override
		{
			// layers are owned by the frontend and survive title restarts, nothing to do
		}
		void CafePPCProcessExit() override
		{
			s_exitRequested = true;
		}
	} s_systemImpl;

	void UpdateSurfaceInfo(bool pad, int w, int h, double scale)
	{
		if (pad)
		{
			g_window_info.pad_width = w;
			g_window_info.pad_height = h;
			g_window_info.phys_pad_width = (int)(w * scale);
			g_window_info.phys_pad_height = (int)(h * scale);
			g_window_info.pad_dpi_scale = scale;
		}
		else
		{
			g_window_info.width = w;
			g_window_info.height = h;
			g_window_info.phys_width = (int)(w * scale);
			g_window_info.phys_height = (int)(h * scale);
			g_window_info.dpi_scale = scale;
		}
	}

	bool CreateRenderer()
	{
		if (s_renderersCreated)
			return true;
		if (!s_tvLayer)
			return false;
		try
		{
			g_renderer = std::make_unique<MetalRenderer>();
			auto* mtl = MetalRenderer::GetInstance();
			mtl->InitializeLayer({g_window_info.width.load(), g_window_info.height.load()}, true);
			if (s_padLayer)
			{
				g_window_info.pad_open = true;
				mtl->InitializeLayer({g_window_info.pad_width.load(), g_window_info.pad_height.load()}, false);
				s_padLayerCreated = true;
			}
		}
		catch (const std::exception& ex)
		{
			WindowSystem::ShowErrorDialog(fmt::format("Error when initializing Metal renderer:\n{}", ex.what()), "Error");
			return false;
		}
		s_renderersCreated = true;
		return true;
	}
}

// used by KeyboardController on iOS
void CemuIOS_GetAnalogState(glm::vec2& axis, glm::vec2& rotation, glm::vec2& trigger)
{
	std::lock_guard _l(s_analogMutex);
	axis = s_axis;
	rotation = s_rotation;
	trigger = s_trigger;
}

extern "C" bool CemuBridge_Initialize(const char* documentsDir, const char* cachesDir, const char* resourcesDir)
{
	if (s_initialized)
		return true;
	SetThreadName("cemu");
	fs::path userData = _utf8ToPath(documentsDir);
	fs::path cache = _utf8ToPath(cachesDir);
	fs::path data = _utf8ToPath(resourcesDir);

	std::set<fs::path> failedWriteAccess;
	ActiveSettings::SetPaths(false, data / "Cemu", userData, userData, cache, data, failedWriteAccess);
	for (auto& p : failedWriteAccess)
		WindowSystem::ShowErrorDialog(fmt::format("Cemu can't write to {}", _pathToUtf8(p)), "Warning");

	std::error_code ec;
	fs::create_directories(ActiveSettings::GetConfigPath("controllerProfiles"), ec);
	fs::create_directories(ActiveSettings::GetUserDataPath("games"), ec);

	GetConfigHandle().SetFilename(ActiveSettings::GetConfigPath("settings.xml").generic_wstring());
	const bool firstStart = !fs::exists(ActiveSettings::GetConfigPath("settings.xml"), ec);
	NetworkConfig::LoadOnce();
	if (!firstStart)
		GetConfigHandle().Load();

	auto& config = GetConfig();
	// iOS defaults: Metal + cubeb, games folder inside Documents
	config.graphic_api = kMetal;
	config.audio_api = 3; // IAudioAPI::Cubeb
	if (config.tv_device.empty())
		config.tv_device = L"default";
	if (firstStart)
		config.notification.position = ScreenPosition::kTopLeft;
	// iOS can move the app's data container (new UUID in the path) when the app is updated or
	// re-signed, so stored absolute game paths go stale. Drop missing paths and always scan the
	// current Documents/games folder.
	{
		const std::string gamesDir = _pathToUtf8(ActiveSettings::GetUserDataPath("games"));
		std::vector<std::string> paths;
		paths.emplace_back(gamesDir);
		for (auto& p : config.game_paths)
		{
			std::error_code pec;
			if (p != gamesDir && fs::exists(_utf8ToPath(p), pec) && std::find(paths.begin(), paths.end(), p) == paths.end())
				paths.emplace_back(p);
		}
		config.game_paths = paths;
	}
	GetConfigHandle().Save();

	if (!CreateDefaultMLCFiles(ActiveSettings::GetMlcPath()))
	{
		WindowSystem::ShowErrorDialog(fmt::format("Cemu failed to write to the mlc directory:\n{}", _pathToUtf8(ActiveSettings::GetMlcPath())), "Error");
		return false;
	}

	ActiveSettings::Init();
	LatteOverlay_init();
	CemuCommonInit();
	SetupDefaultInput();

	CafeSystem::SetImplementation(&s_systemImpl);
	g_window_info.app_active = true;
	s_initialized = true;
	return true;
}

extern "C" bool CemuBridge_IsInitialized(void)
{
	return s_initialized;
}

extern "C" const char* CemuBridge_Version(void)
{
	return BUILD_VERSION_WITH_NAME_STRING;
}

extern "C" void CemuBridge_Tick(void)
{
	// keyboard-api controllers are polled by the input thread, nothing to pump on iOS
}

extern "C" char* CemuBridge_GetKeysPath(void)
{
	return DupString(_pathToUtf8(ActiveSettings::GetUserDataPath("keys.txt")));
}

extern "C" char* CemuBridge_GetMLCPath(void)
{
	return DupString(_pathToUtf8(ActiveSettings::GetMlcPath()));
}

extern "C" char* CemuBridge_GetUserDataPath(void)
{
	return DupString(_pathToUtf8(ActiveSettings::GetUserDataPath()));
}

// ---- game list ----

extern "C" void CemuBridge_AddGamePath(const char* path)
{
	auto& config = GetConfig();
	std::string p = path;
	if (std::find(config.game_paths.begin(), config.game_paths.end(), p) == config.game_paths.end())
	{
		config.game_paths.emplace_back(p);
		GetConfigHandle().Save();
	}
	CafeTitleList::AddScanPath(_utf8ToPath(p));
	CafeTitleList::Refresh();
}

extern "C" void CemuBridge_RemoveGamePath(const char* path)
{
	auto& config = GetConfig();
	std::erase(config.game_paths, std::string(path));
	GetConfigHandle().Save();
	CafeTitleList::ClearScanPaths();
	for (auto& it : config.game_paths)
		CafeTitleList::AddScanPath(_utf8ToPath(it));
	CafeTitleList::Refresh();
}

extern "C" char* CemuBridge_GetGamePathsJSON(void)
{
	rapidjson::Document d;
	d.SetArray();
	for (auto& p : GetConfig().game_paths)
		d.PushBack(rapidjson::Value(p.c_str(), d.GetAllocator()), d.GetAllocator());
	return DupString(ToJSON(d));
}

extern "C" void CemuBridge_RefreshGameList(void)
{
	CafeTitleList::Refresh();
}

extern "C" bool CemuBridge_IsScanning(void)
{
	return CafeTitleList::IsScanning();
}

extern "C" char* CemuBridge_GetGameListJSON(void)
{
	rapidjson::Document d;
	d.SetArray();
	auto& alloc = d.GetAllocator();
	const auto language = GetConfig().console_language.GetValue();
	for (TitleId titleId : CafeTitleList::GetAllTitleIds())
	{
		GameInfo2 gameInfo = CafeTitleList::GetGameInfo(titleId);
		if (!gameInfo.IsValid() || gameInfo.IsSystemDataTitle())
			continue;
		TitleInfo& base = gameInfo.GetBase();
		if (!base.IsValid())
			continue; // update or DLC without base game
		if (base.GetAppTitleId() != titleId)
			continue;
		std::string name = base.GetMetaTitleName();
		if (auto* meta = base.GetMetaInfo())
		{
			std::string localized = meta->GetShortName(language);
			if (!localized.empty())
				name = localized;
		}
		boost::replace_all(name, "\n", " ");
		rapidjson::Value e(rapidjson::kObjectType);
		e.AddMember("titleId", rapidjson::Value(fmt::format("{:016x}", titleId).c_str(), alloc), alloc);
		e.AddMember("name", rapidjson::Value(name.c_str(), alloc), alloc);
		e.AddMember("path", rapidjson::Value(_pathToUtf8(base.GetPath()).c_str(), alloc), alloc);
		uint16 version = gameInfo.HasUpdate() ? gameInfo.GetUpdate().GetAppTitleVersion() : base.GetAppTitleVersion();
		e.AddMember("version", (int)version, alloc);
		e.AddMember("region", rapidjson::Value(RegionToString(base.GetMetaRegion()), alloc), alloc);
		e.AddMember("format", rapidjson::Value(FormatToString(base.GetFormat()), alloc), alloc);
		e.AddMember("hasUpdate", gameInfo.HasUpdate(), alloc);
		e.AddMember("hasDLC", gameInfo.HasAOC(), alloc);
		d.PushBack(e, alloc);
	}
	return DupString(ToJSON(d));
}

extern "C" bool CemuBridge_ExtractIcon(uint64_t titleId, const char* outPath)
{
	TitleInfo titleInfo;
	if (!CafeTitleList::GetFirstByTitleId(titleId, titleInfo))
		return false;
	std::string tempMountPath = TitleInfo::GetUniqueTempMountingPath();
	if (!titleInfo.Mount(tempMountPath, "", FSC_PRIORITY_BASE))
		return false;
	auto tgaData = fsc_extractFile((tempMountPath + "/meta/iconTex.tga").c_str());
	if (!tgaData)
	{
		tgaData = fsc_extractFile((tempMountPath + "/meta/iconTex.tga.gz").c_str());
		if (tgaData)
		{
			auto decompressed = zlibDecompress(*tgaData, 70 * 1024);
			std::swap(tgaData, decompressed);
		}
	}
	titleInfo.Unmount(tempMountPath);
	if (!tgaData || tgaData->size() <= 16)
		return false;
	std::ofstream f(_utf8ToPath(outPath), std::ios::binary);
	if (!f.is_open())
		return false;
	f.write((const char*)tgaData->data(), tgaData->size());
	return true;
}

// ---- emulation ----

extern "C" void CemuBridge_SetRenderSurfaces(void* tvLayer, void* padLayer)
{
	s_tvLayer = tvLayer;
	s_padLayer = padLayer;
	g_window_info.window_main.backend = WindowSystem::WindowHandleInfo::Backend::Cocoa;
	g_window_info.window_main.surface = tvLayer;
	g_window_info.canvas_main = g_window_info.window_main;
	g_window_info.window_pad.backend = WindowSystem::WindowHandleInfo::Backend::Cocoa;
	g_window_info.window_pad.surface = padLayer;
	g_window_info.canvas_pad = g_window_info.window_pad;
}

extern "C" void CemuBridge_SetSurfaceSize(bool pad, int widthPoints, int heightPoints, double scale)
{
	if (widthPoints <= 0 || heightPoints <= 0)
		return;
	UpdateSurfaceInfo(pad, widthPoints, heightPoints, scale);
	if (s_renderersCreated && g_renderer)
	{
		if (pad && !s_padLayerCreated)
			return;
		MetalRenderer::GetInstance()->ResizeLayer({widthPoints, heightPoints}, !pad);
	}
}

extern "C" CemuLaunchResult CemuBridge_LaunchGame(const char* path)
{
	if (s_running)
		return CemuLaunch_AlreadyRunning;
	if (!s_tvLayer)
		return CemuLaunch_NoRenderSurface;

	// no JIT -> the recompiler can't run, fall back to the interpreter
	LaunchSettings::SetForceInterpreter(!CemuJit_IsReady());

	fs::path launchPath = _utf8ToPath(path);
	TitleInfo launchTitle{launchPath};
	if (launchTitle.IsValid())
	{
		CafeTitleList::AddTitleFromPath(launchPath);
		TitleId baseTitleId;
		if (!CafeTitleList::FindBaseTitleId(launchTitle.GetAppTitleId(), baseTitleId))
			return CemuLaunch_BaseNotFound;
		auto r = CafeSystem::PrepareForegroundTitle(baseTitleId);
		if (r == CafeSystem::PREPARE_STATUS_CODE::INVALID_RPX)
			return CemuLaunch_InvalidRPX;
		if (r == CafeSystem::PREPARE_STATUS_CODE::UNABLE_TO_MOUNT)
			return CemuLaunch_UnableToMount;
		if (r != CafeSystem::PREPARE_STATUS_CODE::SUCCESS)
			return CemuLaunch_Failed;
	}
	else
	{
		CafeTitleFileType fileType = DetermineCafeSystemFileType(launchPath);
		if (fileType == CafeTitleFileType::RPX || fileType == CafeTitleFileType::ELF)
		{
			if (CafeSystem::PrepareForegroundTitleFromStandaloneRPX(launchPath) != CafeSystem::PREPARE_STATUS_CODE::SUCCESS)
				return CemuLaunch_InvalidRPX;
		}
		else
		{
			if (launchTitle.GetInvalidReason() == TitleInfo::InvalidReason::NO_DISC_KEY)
				return CemuLaunch_NoDiscKey;
			if (launchTitle.GetInvalidReason() == TitleInfo::InvalidReason::NO_TITLE_TIK)
				return CemuLaunch_NoTitleTik;
			return CemuLaunch_UnableToMount;
		}
	}

	if (!CreateRenderer())
		return CemuLaunch_Failed;

	s_exitRequested = false;
	s_running = true;
	CafeSystem::LaunchForegroundTitle();
	return CemuLaunch_OK;
}

extern "C" bool CemuBridge_IsGameRunning(void)
{
	return s_running && CafeSystem::IsTitleRunning();
}

extern "C" void CemuBridge_StopGame(void)
{
	if (!s_running)
		return;
	CafeSystem::ShutdownTitle();
	if (s_renderersCreated && g_renderer)
	{
		auto* mtl = MetalRenderer::GetInstance();
		if (s_padLayerCreated)
			mtl->ShutdownLayer(false);
		mtl->ShutdownLayer(true);
	}
	g_window_info.pad_open = false;
	s_padLayerCreated = false;
	s_renderersCreated = false;
	s_running = false;
	iosState::g_fps = 0.0;
}

extern "C" bool CemuBridge_ConsumeGameExitRequest(void)
{
	return s_exitRequested.exchange(false);
}

extern "C" double CemuBridge_GetFPS(void)
{
	return iosState::g_fps;
}

extern "C" char* CemuBridge_GetRunningTitleName(void)
{
	if (!s_running)
		return DupString("");
	return DupString(CafeSystem::GetForegroundTitleName());
}

extern "C" uint64_t CemuBridge_GetRunningTitleId(void)
{
	return s_running ? CafeSystem::GetForegroundTitleId() : 0;
}

extern "C" void CemuBridge_SetShowGamePadOnTV(bool enabled)
{
	LatteGPUState.isDRCPrimary = enabled;
}

extern "C" bool CemuBridge_GetShowGamePadOnTV(void)
{
	return LatteGPUState.isDRCPrimary;
}

extern "C" char* CemuBridge_ConsumeErrorMessage(void)
{
	std::lock_guard _l(iosState::g_errorMutex);
	std::string msg;
	std::swap(msg, iosState::g_lastError);
	return DupString(msg);
}

// ---- input ----

extern "C" void CemuBridge_SetButton(CemuButton button, bool pressed)
{
	if ((int)button < 0 || button >= CemuButton_Count)
		return;
	g_window_info.set_keystate((uint32)button, pressed);
}

extern "C" void CemuBridge_SetSticks(float lx, float ly, float rx, float ry)
{
	std::lock_guard _l(s_analogMutex);
	s_axis = {std::clamp(lx, -1.0f, 1.0f), std::clamp(ly, -1.0f, 1.0f)};
	s_rotation = {std::clamp(rx, -1.0f, 1.0f), std::clamp(ry, -1.0f, 1.0f)};
}

extern "C" void CemuBridge_SetTouch(bool pad, bool down, float x, float y)
{
	auto& im = InputManager::instance();
	auto& info = pad ? im.m_pad_touch : im.m_main_touch;
	const double scale = pad ? g_window_info.pad_dpi_scale.load() : g_window_info.dpi_scale.load();
	std::unique_lock lock(info.m_mutex);
	info.position = {(int)(x * scale), (int)(y * scale)};
	if (down && !info.left_down)
		info.left_down_toggle = true;
	info.left_down = down;
}

extern "C" void CemuBridge_SetMotion(float gx, float gy, float gz, float ax, float ay, float az)
{
	// motion is optional; kept for a future motion provider
	(void)gx; (void)gy; (void)gz; (void)ax; (void)ay; (void)az;
}

// ---- settings ----

extern "C" char* CemuBridge_GetSettingsJSON(void)
{
	auto& c = GetConfig();
	rapidjson::Document d;
	d.SetObject();
	auto& a = d.GetAllocator();
	d.AddMember("consoleLanguage", (int)c.console_language.GetValue(), a);
	d.AddMember("vsync", c.vsync.GetValue(), a);
	d.AddMember("asyncCompile", c.async_compile.GetValue(), a);
	d.AddMember("gx2DrawdoneSync", c.gx2drawdone_sync.GetValue(), a);
	d.AddMember("upscaleFilter", c.upscale_filter.GetValue(), a);
	d.AddMember("downscaleFilter", c.downscale_filter.GetValue(), a);
	d.AddMember("scaling", c.fullscreen_scaling.GetValue(), a);
	d.AddMember("framebufferFetch", c.framebuffer_fetch.GetValue(), a);
	d.AddMember("forceMeshShaders", c.force_mesh_shaders.GetValue(), a);
	d.AddMember("overlayFPS", c.overlay.position != ScreenPosition::kDisabled, a);
	d.AddMember("notifications", c.notification.position != ScreenPosition::kDisabled, a);
	d.AddMember("tvVolume", c.tv_volume, a);
	d.AddMember("padVolume", c.pad_volume, a);
	d.AddMember("audioDelay", c.audio_delay, a);
	d.AddMember("tvChannels", (int)c.tv_channels, a);
	d.AddMember("onlineEnabled", c.account.legacy_online_enabled.GetValue(), a);
	d.AddMember("persistentId", (uint64)c.account.m_persistent_id.GetValue(), a);
	return DupString(ToJSON(d));
}

extern "C" bool CemuBridge_SetSettingsJSON(const char* json)
{
	rapidjson::Document d;
	d.Parse(json);
	if (d.HasParseError() || !d.IsObject())
		return false;
	auto& c = GetConfig();
	auto getInt = [&](const char* k, auto setter) { if (d.HasMember(k) && d[k].IsInt()) setter(d[k].GetInt()); };
	auto getBool = [&](const char* k, auto setter) { if (d.HasMember(k) && d[k].IsBool()) setter(d[k].GetBool()); };
	getInt("consoleLanguage", [&](int v) { c.console_language = (CafeConsoleLanguage)std::clamp(v, 0, 11); });
	getInt("vsync", [&](int v) { c.vsync = v; });
	getBool("asyncCompile", [&](bool v) { c.async_compile = v; });
	getBool("gx2DrawdoneSync", [&](bool v) { c.gx2drawdone_sync = v; });
	getInt("upscaleFilter", [&](int v) { c.upscale_filter = v; });
	getInt("downscaleFilter", [&](int v) { c.downscale_filter = v; });
	getInt("scaling", [&](int v) { c.fullscreen_scaling = v; });
	getBool("framebufferFetch", [&](bool v) { c.framebuffer_fetch = v; });
	getBool("forceMeshShaders", [&](bool v) { c.force_mesh_shaders = v; });
	getBool("overlayFPS", [&](bool v) { c.overlay.position = v ? ScreenPosition::kTopRight : ScreenPosition::kDisabled; c.overlay.fps = v; });
	getBool("notifications", [&](bool v) { c.notification.position = v ? ScreenPosition::kTopLeft : ScreenPosition::kDisabled; });
	getInt("tvVolume", [&](int v) { c.tv_volume = std::clamp(v, 0, 100); });
	getInt("padVolume", [&](int v) { c.pad_volume = std::clamp(v, 0, 100); });
	getInt("audioDelay", [&](int v) { c.audio_delay = std::clamp(v, 1, 8); });
	getInt("tvChannels", [&](int v) { c.tv_channels = (AudioChannels)std::clamp(v, 0, 2); });
	getBool("onlineEnabled", [&](bool v) { c.account.legacy_online_enabled = v; });
	return GetConfigHandle().Save();
}

// ---- JIT ----

extern "C" bool CemuBridge_JitIsDebugged(void)
{
	return CemuJit_IsProcessDebugged();
}

extern "C" bool CemuBridge_JitUsesTXM(void)
{
	return CemuJit_DeviceUsesTXM();
}

extern "C" bool CemuBridge_JitInitialize(int mode, int arenaMB)
{
	return CemuJit_Initialize((CemuJitMode)mode, (size_t)std::max(arenaMB, 64) * 1024 * 1024);
}

extern "C" bool CemuBridge_JitIsReady(void)
{
	return CemuJit_IsReady();
}

extern "C" char* CemuBridge_JitLastError(void)
{
	return DupString(CemuJit_LastError());
}

extern "C" void CemuBridge_FreeString(char* str)
{
	free(str);
}

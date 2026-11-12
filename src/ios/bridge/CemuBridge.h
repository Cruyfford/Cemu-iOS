#pragma once
// Plain C interface between the Swift frontend and the Cemu core.
// All strings are UTF-8. Strings returned as `char*` must be released with CemuBridge_FreeString.
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- lifecycle ----
// documentsDir: writable root (config, mlc01, keys.txt, caches)
// resourcesDir: read-only bundled data (gameProfiles/, resources/)
bool CemuBridge_Initialize(const char* documentsDir, const char* cachesDir, const char* resourcesDir);
bool CemuBridge_IsInitialized(void);
const char* CemuBridge_Version(void);
// pumps work that must run on the UI thread, call once per display frame
void CemuBridge_Tick(void);

// ---- paths ----
char* CemuBridge_GetKeysPath(void);
char* CemuBridge_GetMLCPath(void);
char* CemuBridge_GetUserDataPath(void);

// ---- game list ----
void CemuBridge_AddGamePath(const char* path);
void CemuBridge_RemoveGamePath(const char* path);
char* CemuBridge_GetGamePathsJSON(void);
void CemuBridge_RefreshGameList(void);
bool CemuBridge_IsScanning(void);
// [{ "titleId": "0005000010101c00", "name": "...", "path": "...", "version": 0, "region": "EUR",
//    "format": "WUA", "hasUpdate": true, "hasDLC": false }]
char* CemuBridge_GetGameListJSON(void);
// writes the title's icon (TGA) to outPath, returns false if the title has none
bool CemuBridge_ExtractIcon(uint64_t titleId, const char* outPath);

// ---- emulation ----
typedef enum
{
	CemuLaunch_OK = 0,
	CemuLaunch_AlreadyRunning = 1,
	CemuLaunch_BaseNotFound = 2,
	CemuLaunch_UnableToMount = 3,
	CemuLaunch_InvalidRPX = 4,
	CemuLaunch_NoDiscKey = 5,
	CemuLaunch_NoTitleTik = 6,
	CemuLaunch_Failed = 7,
	CemuLaunch_NoRenderSurface = 8,
} CemuLaunchResult;

// metalLayer: CAMetalLayer* for the TV screen (required). padLayer: CAMetalLayer* for the GamePad screen (optional)
void CemuBridge_SetRenderSurfaces(void* tvLayer, void* padLayer);
// sizes in points; scale = contentsScale
void CemuBridge_SetSurfaceSize(bool pad, int widthPoints, int heightPoints, double scale);
CemuLaunchResult CemuBridge_LaunchGame(const char* path);
bool CemuBridge_IsGameRunning(void);
void CemuBridge_StopGame(void);
// true once the game asked to exit by itself (returning to the Wii U menu)
bool CemuBridge_ConsumeGameExitRequest(void);
double CemuBridge_GetFPS(void);
char* CemuBridge_GetRunningTitleName(void);
uint64_t CemuBridge_GetRunningTitleId(void);
// shows the GamePad image on the main (TV) surface
void CemuBridge_SetShowGamePadOnTV(bool enabled);
bool CemuBridge_GetShowGamePadOnTV(void);
// last error message reported by the core (dialogs), empty if none. Clears it.
char* CemuBridge_ConsumeErrorMessage(void);

// ---- input ----
// buttons use Cemu's generic controller button ids (see CemuButton below)
typedef enum
{
	CemuButton_A = 0,
	CemuButton_B,
	CemuButton_X,
	CemuButton_Y,
	CemuButton_L,
	CemuButton_R,
	CemuButton_ZL,
	CemuButton_ZR,
	CemuButton_Plus,
	CemuButton_Minus,
	CemuButton_Up,
	CemuButton_Down,
	CemuButton_Left,
	CemuButton_Right,
	CemuButton_StickL,
	CemuButton_StickR,
	CemuButton_Home,
	CemuButton_Screen,
	CemuButton_Mic,
	CemuButton_Count
} CemuButton;

void CemuBridge_SetButton(CemuButton button, bool pressed);
// stick values in [-1, 1], y up is positive
void CemuBridge_SetSticks(float lx, float ly, float rx, float ry);
// touch position in points relative to the surface, pad = true when touching the GamePad surface
void CemuBridge_SetTouch(bool pad, bool down, float x, float y);
// device motion for gyro (rad/s) and gravity (g), optional
void CemuBridge_SetMotion(float gx, float gy, float gz, float ax, float ay, float az);

// ---- settings ----
// returns the editable settings as JSON, see CemuBridge.mm for the keys
char* CemuBridge_GetSettingsJSON(void);
// applies the keys present in json, unknown keys are ignored. Saves settings.xml.
bool CemuBridge_SetSettingsJSON(const char* json);

// ---- JIT ----
// arenaMB: executable memory for recompiled code
bool CemuBridge_JitIsDebugged(void);
bool CemuBridge_JitUsesTXM(void);
bool CemuBridge_JitInitialize(int mode, int arenaMB);
bool CemuBridge_JitIsReady(void);
char* CemuBridge_JitLastError(void);

void CemuBridge_FreeString(char* str);

#ifdef __cplusplus
}
#endif

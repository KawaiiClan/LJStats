#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <sdkhooks>
#include <shavit>

#pragma newdecls required

#define MIN(%0,%1) (%0 > %1 ? %1 : %0)
#define MAX(%0,%1) (%0 < %1 ? %1 : %0)

#define LJSTATS_VERSION "3.0"

#define LJSOUND_NUM 5
#define MAX_STRAFES 50
#define BHOP_TIME 0.3
#define STAMINA_RECHARGE_TIME 0.58579
#define SW_ANGLE_THRESHOLD 20.0
#define LJ_HEIGHT_DELTA_MIN -0.01	// Dropjump limit
#define LJ_HEIGHT_DELTA_MAX 1.5		// Upjump limit
#define CJ_HEIGHT_DELTA_MIN -0.01
#define CJ_HEIGHT_DELTA_MAX 1.5
#define WJ_HEIGHT_DELTA_MIN -0.01
#define WJ_HEIGHT_DELTA_MAX 1.5
#define BJ_HEIGHT_DELTA_MIN -2.0 // dynamic pls
#define BJ_HEIGHT_DELTA_MAX 2.0
#define LAJ_HEIGHT_DELTA_MIN -6.0
#define LAJ_HEIGHT_DELTA_MAX 0.0

#define LJ_DISTANCE_MAX 280.0
#define CJ_DISTANCE_MAX 280.0
#define WJ_DISTANCE_MAX 400.0
#define BJ_DISTANCE_MAX 350.0
#define LAJ_DISTANCE_MAX 250.0

chatstrings_t gS_ChatStrings;

public Plugin myinfo = 
{
	name = "Kawaii-LJStats",
	author = "Miu, olivia",
	description = "Longjump statistics improved for KawaiiClan servers",
	version = "c:",
	url = "https://forums.alliedmods.net/showthread.php?p=2060983"
}

enum ILLEGAL_JUMP_FLAGS
{
	IJF_NONE = 0,
	IJF_WORLD = 1 << 0,
	IJF_BOOSTER = 1 << 1,
	IJF_GRAVITY = 1 << 2,
	IJF_TELEPORT = 1 << 3,
	IJF_LAGGEDMOVEMENTVALUE = 1 << 4,
	IJF_PRESTRAFE = 1 << 5,
	IJF_NOCLIP = 1 << 6,
	IJF_WATER = 1 << 7,
}

enum JUMP_TYPE
{
	JT_LONGJUMP,
	JT_COUNTJUMP,
	JT_WEIRDJUMP,
	JT_BHOPJUMP,
	JT_LADDERJUMP,
	JT_BHOP,
	JT_DROP,
	JT_END,
}

enum JUMP_DIRECTION
{
	JD_NONE,		// Indeterminate
	JD_NORMAL,
	JD_FORWARDS = JD_NORMAL,
	JD_SIDEWAYS,
	JD_BACKWARDS,
	JD_END,
}

enum STRAFE_DIRECTION
{
	SD_NONE,
	SD_W,
	SD_D,
	SD_A,
	SD_S,
	SD_WA,
	SD_WD,
	SD_SA,
	SD_SD,
	SD_END,
}

static char g_strJumpType[JT_END][] =
{
	"Longjump",
	"Countjump",
	"Weirdjump",
	"Bhopjump",
	"Ladderjump",
	"Bhop",
	"Drop"
};

static char g_strJumpTypeLwr[JT_END][] =
{
	"longjump",
	"countjump",
	"weirdjump",
	"bhopjump",
	"ladderjump",
	"bhop",
	"drop"
};

static char g_strJumpTypeShort[JT_END][] =
{
	"LJ",
	"CJ",
	"WJ",
	"BJ",
	"LAJ",
	"Bhop",
	"Drop"
};

enum struct PlayerState
{
	bool bLJEnabled;
	bool bShowPanel;
	bool bShowBhopStats;
	bool bBeam;
	bool bBeamZ;
	bool bSound;
	bool bShowAllJumps;
	bool bHideChat;
	float fMinStepper;
	float fLJMin;
	float fLJNoDuckMin;
	float fWJMin;
	float fBJMin;
	float fLAJMin;
	
	float fBlockDistance;
	float vBlockNormal[2];
	float vBlockEndPos[3];
	bool bFailedBlock;
	
	bool bDuck;
	bool bLastDuckState;
	bool bSecondLastDuckState;
	
	JUMP_DIRECTION JumpDir;
	ILLEGAL_JUMP_FLAGS IllegalJumpFlags;
	
	JUMP_TYPE LastJumpType;
	JUMP_TYPE JumpType;
	float fLandTime;
	float fLastJumpHeightDelta;
	int nBhops;
	
	bool bOnGround;
	bool bOnLadder;
	
	float fEdge;
	float vJumpOrigin[3];
	float fWJDropPre;
	float fPrestrafe;
	float fJumpDistance;
	float fHeightDelta;
	float fJumpHeight;
	float fSync;
	float fMaxSpeed;
	float fFinalSpeed;
	float fTrajectory;
	float fGain;
	float fLoss;
	
	STRAFE_DIRECTION CurStrafeDir;
	int nStrafes;
	STRAFE_DIRECTION StrafeDir[MAX_STRAFES];
	float fStrafeGain[MAX_STRAFES];
	float fStrafeLoss[MAX_STRAFES];
	float fStrafeSync[MAX_STRAFES];
	int nStrafeTicks[MAX_STRAFES];
	int nStrafeTicksSynced[MAX_STRAFES];
	int nTotalTicks;
	float fTotalAngle;
	float fSyncedAngle;
	
	float fStyleAA;
	float fStyleRunSpeed;
	bool bStyleAuto;
	
	bool bStamina;
	int nJumpTick;
	int nLastAerialTick;
	
	float vLastOrigin[3];
	float vLastAngles[3];
	float vLastVelocity[3];
	
	int nSpectators;
	int nSpectatorTarget;
	
	int LastButtons;
}

static const float g_fHeightDeltaMin[JT_END] =
{
	LJ_HEIGHT_DELTA_MIN,
	LJ_HEIGHT_DELTA_MIN,
	WJ_HEIGHT_DELTA_MIN,
	BJ_HEIGHT_DELTA_MIN,
	LAJ_HEIGHT_DELTA_MIN,
	-3.402823466e38,
	-3.402823466e38
};

static const float g_fHeightDeltaMax[JT_END] =
{
	LJ_HEIGHT_DELTA_MAX,
	LJ_HEIGHT_DELTA_MAX,
	WJ_HEIGHT_DELTA_MAX,
	BJ_HEIGHT_DELTA_MAX,
	LAJ_HEIGHT_DELTA_MAX,
	3.402823466e38,
	3.402823466e38
};

static const float g_fDistanceMax[JT_END] =
{
	LJ_DISTANCE_MAX,
	LJ_DISTANCE_MAX,
	WJ_DISTANCE_MAX,
	BJ_DISTANCE_MAX,
	LAJ_DISTANCE_MAX,
	99999999999.0,
	99999999999.0
};

// SourcePawn is silly
#define HEIGHT_DELTA_MIN(%0) (view_as<float>(g_fHeightDeltaMin[%0]))
#define HEIGHT_DELTA_MAX(%0) (view_as<float>(g_fHeightDeltaMax[%0]))
#define DISTANCE_MAX(%0) (view_as<float>(g_fDistanceMax[%0]))

PlayerState g_PlayerStates[MAXPLAYERS + 1];

int g_BeamModel;

Handle g_hCookieDefaultsSet = INVALID_HANDLE;
Handle g_hCookieLJEnabled = INVALID_HANDLE;
Handle g_hCookieShowPanel = INVALID_HANDLE;
Handle g_hCookieShowBhopStats = INVALID_HANDLE;
Handle g_hCookieBeam = INVALID_HANDLE;
Handle g_hCookieBeamZ = INVALID_HANDLE;
Handle g_hCookieSound = INVALID_HANDLE;
Handle g_hCookieShowAllJumps = INVALID_HANDLE;
Handle g_hCookieHideChat = INVALID_HANDLE;
Handle g_hCookieLJMin = INVALID_HANDLE;
Handle g_hCookieLJNoDuckMin = INVALID_HANDLE;
Handle g_hCookieWJMin = INVALID_HANDLE;
Handle g_hCookieBJMin = INVALID_HANDLE;
Handle g_hCookieLAJMin = INVALID_HANDLE;

float g_fLJMaxPrestrafe = 30.0;
float g_fWJDropMax = 30.0;
float g_fLJSound[5] = {260.0, 262.0, 264.0, 266.0, 268.0};
char g_strLJSoundFile[5][64] = {"kawaii/lj/nyaa1.wav", "kawaii/lj/nyaa2.wav", "kawaii/lj/nyaa3.wav", "kawaii/lj/nyaa4.wav", "kawaii/lj/nyaa5.wav"};

float g_fLJMinMin = 240.0;
float g_fLJMinMax = 275.0;
float g_fLJNoDuckMinMin = 230.0;
float g_fLJNoDuckMinMax = 265.0;
float g_fWJMinMin = 250.0;
float g_fWJMinMax = 295.0;
float g_fBJMinMin = 250.0;
float g_fBJMinMax = 295.0;
float g_fLAJMinMin = 110.0;
float g_fLAJMinMax = 160.0;

public void OnPluginStart()
{
	CreateNative("LJStats_CancelJump", Native_CancelJump);
	
	HookEvent("player_jump", Event_PlayerJump);
	HookEvent("player_spawn", Player_Spawn);
	
	RegConsoleCmd("sm_ljhelp", Command_LJHelp);
	RegConsoleCmd("sm_lj", Command_LJ);
	RegConsoleCmd("sm_longjump", Command_LJ);
	RegConsoleCmd("sm_ljsettings", Command_LJSettings);
	RegConsoleCmd("sm_ljs", Command_LJSettings);
	RegConsoleCmd("sm_ljpanel", Command_LJPanel);
	RegConsoleCmd("sm_ljbeam", Command_LJBeam);
	RegConsoleCmd("sm_ljsound", Command_LJSound);
	
	g_hCookieDefaultsSet = RegClientCookie("ljstats_defaultsset", "ljstats_defaultsset", CookieAccess_Public);
	g_hCookieLJEnabled = RegClientCookie("ljstats_ljenabled", "ljstats_ljenabled", CookieAccess_Public);
	g_hCookieBeam = RegClientCookie("ljstats_beam", "ljstats_beam", CookieAccess_Public);
	g_hCookieBeamZ = RegClientCookie("ljstats_beamz", "ljstats_beam (z-axis)", CookieAccess_Public);
	g_hCookieSound = RegClientCookie("ljstats_sound", "ljstats_sound", CookieAccess_Public);
	g_hCookieShowPanel = RegClientCookie("ljstats_showpanel", "ljstats_showpanel", CookieAccess_Public);
	g_hCookieShowBhopStats = RegClientCookie("ljstats_showbhopstats", "ljstats_showbhopstats", CookieAccess_Public);
	g_hCookieShowAllJumps = RegClientCookie("ljstats_showalljumps", "ljstats_showalljumps", CookieAccess_Public);
	g_hCookieHideChat = RegClientCookie("ljstats_hidechat", "ljstats_hidechat", CookieAccess_Public);
	g_hCookieLJMin = RegClientCookie("ljstats_ljmin", "ljstats_ljmin", CookieAccess_Public);
	g_hCookieLJNoDuckMin = RegClientCookie("ljstats_ljnoduckmin", "ljstats_ljnoduckmin", CookieAccess_Public);
	g_hCookieWJMin = RegClientCookie("ljstats_wjmin", "ljstats_wjmin", CookieAccess_Public);
	g_hCookieBJMin = RegClientCookie("ljstats_bjmin", "ljstats_bjmin", CookieAccess_Public);
	g_hCookieLAJMin = RegClientCookie("ljstats_lajmin", "ljstats_lajmin", CookieAccess_Public);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
			OnClientCookiesCached(i);
		}
	}
	
	Shavit_OnChatConfigLoaded();
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));
}

public void OnMapStart()
{
	g_BeamModel = PrecacheModel("materials/sprites/bluelaser1.vmt");
	
	for(int i; i < LJSOUND_NUM; i++)
	{
		if(g_strLJSoundFile[i][0] != 0)
		{
			char filePath[255];
			Format(filePath, sizeof(filePath), "sound/%s", g_strLJSoundFile[i]);
			AddFileToDownloadsTable(filePath);
			PrecacheSound(g_strLJSoundFile[i]);
		}
	}
}

public void OnClientPutInServer(int client)
{
	g_PlayerStates[client].bOnGround = true;
	g_PlayerStates[client].fBlockDistance = -1.0;
	g_PlayerStates[client].IllegalJumpFlags = IJF_NONE;
	g_PlayerStates[client].nSpectators = 0;
	g_PlayerStates[client].nSpectatorTarget = -1;
	g_PlayerStates[client].fMinStepper = 5.0;
	SDKHook(client, SDKHook_Touch, hkTouch);
}

public void OnClientDisconnect(int client)
{
	if(g_PlayerStates[client].nSpectatorTarget != -1)
	{
		g_PlayerStates[g_PlayerStates[client].nSpectatorTarget].nSpectators--;
	}
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_PlayerStates[client].fStyleRunSpeed = Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "runspeed");
	g_PlayerStates[client].bStyleAuto = Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "autobhop");
	g_PlayerStates[client].fStyleAA = Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "airaccelerate");
}

public Action hkTouch(int client, int other)
{
	float vOrigin[3];
	GetClientAbsOrigin(client, vOrigin);
	
	if(other == 0 && !(GetEntityFlags(client) & FL_ONGROUND))
	{
		if(g_PlayerStates[client].fBlockDistance != -1)
		{
			float distance = GetVectorDistance(g_PlayerStates[client].vJumpOrigin, vOrigin);
			
			if(g_PlayerStates[client].fBlockDistance - distance < 30.0 || distance - g_PlayerStates[client].fBlockDistance < 30.0 || g_PlayerStates[client].fBlockDistance - distance < 30.0 || distance - g_PlayerStates[client].fBlockDistance < 30.0)
			{
				GetJumpDistanceLastTick(client);
				PlayerLand(client);
				return Plugin_Handled;
			}
		}

		g_PlayerStates[client].IllegalJumpFlags |= IJF_WORLD;
	}
	else
	{
		char strClassname[64];
		GetEdictClassname(other, strClassname, sizeof(strClassname));
		
		if(!strcmp(strClassname, "trigger_push"))
		{
			g_PlayerStates[client].IllegalJumpFlags |= IJF_BOOSTER;
		}
	}
	return Plugin_Handled;
}

public Action Command_LJHelp(int client, int args)
{
	Handle hHelpPanel = CreatePanel();
	
	SetPanelTitle(hHelpPanel, "Longjump Stats \n ");
	DrawPanelText(hHelpPanel, "!lj");
	DrawPanelText(hHelpPanel, "!ljsettings, !ljs");
	DrawPanelText(hHelpPanel, "!ljpanel");
	DrawPanelText(hHelpPanel, "!ljbeam");
	DrawPanelText(hHelpPanel, "!ljsound \n ");
	DrawPanelText(hHelpPanel, "ex. !lj, /lj, or sm_lj \n ");
	
	SendPanelToClient(hHelpPanel, client, EmptyPanelHandler, 10);
	
	CloseHandle(hHelpPanel);
	
	return Plugin_Handled;
}

public Action Command_LJ(int client, int args)
{
	g_PlayerStates[client].bLJEnabled = !g_PlayerStates[client].bLJEnabled;
	SetCookie(client, g_hCookieLJEnabled, g_PlayerStates[client].bLJEnabled);
	Shavit_PrintToChat(client, "Longjump stats %s%s", gS_ChatStrings.sVariable, g_PlayerStates[client].bLJEnabled ? "enabled" : "disabled");
	
	return Plugin_Handled;
}

public Action Command_LJSettings(int client, int args)
{
	ShowSettingsPanel(client);
	
	return Plugin_Handled;
}

public void OnClientCookiesCached(int client)
{
	char strCookie[64];
	
	GetClientCookie(client, g_hCookieDefaultsSet, strCookie, sizeof(strCookie));
	
	if(StringToInt(strCookie) == 0)
	{
		SetCookie(client, g_hCookieLJEnabled, false);
		SetCookie(client, g_hCookieSound, true);
		SetCookie(client, g_hCookieBeam, false);
		SetCookie(client, g_hCookieBeamZ, false);
		SetCookie(client, g_hCookieShowPanel, false);
		SetCookie(client, g_hCookieShowBhopStats, false);
		SetCookie(client, g_hCookieShowAllJumps, false);
		SetCookie(client, g_hCookieHideChat, false);
		SetFloatCookie(client, g_hCookieLJMin, 260.00);
		SetFloatCookie(client, g_hCookieLJNoDuckMin, 256.00);
		SetFloatCookie(client, g_hCookieWJMin, 270.00);
		SetFloatCookie(client, g_hCookieBJMin, 270.00);
		SetFloatCookie(client, g_hCookieLAJMin, 140.00);
		SetCookie(client, g_hCookieDefaultsSet, true);
	}
	
	GetClientCookie(client, g_hCookieLJEnabled, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bLJEnabled = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieSound, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bSound = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieBeam, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bBeam = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieBeamZ, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bBeamZ = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieShowPanel, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bShowPanel = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieShowBhopStats, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bShowBhopStats = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieShowAllJumps, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bShowAllJumps = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieHideChat, strCookie, sizeof(strCookie));
	g_PlayerStates[client].bHideChat = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieLJMin, strCookie, sizeof(strCookie));
	g_PlayerStates[client].fLJMin = StringToFloat(strCookie);
	
	GetClientCookie(client, g_hCookieLJNoDuckMin, strCookie, sizeof(strCookie));
	g_PlayerStates[client].fLJNoDuckMin = StringToFloat(strCookie);
	
	GetClientCookie(client, g_hCookieWJMin, strCookie, sizeof(strCookie));
	g_PlayerStates[client].fWJMin = StringToFloat(strCookie);
	
	GetClientCookie(client, g_hCookieBJMin, strCookie, sizeof(strCookie));
	g_PlayerStates[client].fBJMin = StringToFloat(strCookie);
	
	GetClientCookie(client, g_hCookieLAJMin, strCookie, sizeof(strCookie));
	g_PlayerStates[client].fLAJMin = StringToFloat(strCookie);
}

public Action ShowSettingsPanel(int client)
{
	Handle hMenu = CreateMenu(SettingsMenuHandler);
	char buf[64];
	
	SetMenuTitle(hMenu, "Longjump Settings");
	
	Format(buf, sizeof(buf), "%s Enabled", g_PlayerStates[client].bLJEnabled ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "ljenabled", buf);
	
	Format(buf, sizeof(buf), "%s Beam  %s With Z", g_PlayerStates[client].bBeam ? "[X]" : "[  ]", g_PlayerStates[client].bBeamZ ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "beam", buf);
	
	Format(buf, sizeof(buf), "%s Sounds", g_PlayerStates[client].bSound ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "sound", buf);
	
	Format(buf, sizeof(buf), "%s Panel", g_PlayerStates[client].bShowPanel ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "panel", buf);
	
	Format(buf, sizeof(buf), "%s Bhop stats", g_PlayerStates[client].bShowBhopStats ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "bhopstats", buf);
	
	Format(buf, sizeof(buf), "%s Show all jumps", g_PlayerStates[client].bShowAllJumps ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "showalljumps", buf);
	
	Format(buf, sizeof(buf), "%s Show in chat", !g_PlayerStates[client].bHideChat ? "[X]" : "[  ]");
	AddMenuItem(hMenu, "hidechat", buf);
	
	Format(buf, sizeof(buf), "Set Jump Minimums...");
	AddMenuItem(hMenu, "setminimums", buf);
	
	DisplayMenu(hMenu, client, 0);
	
	return Plugin_Handled;
}

public int SettingsMenuHandler(Handle hMenu, MenuAction ma, int client, int nItem)
{
	switch(ma)
	{
		case MenuAction_Select:
		{
			char strInfo[16];
			
			if(!GetMenuItem(hMenu, nItem, strInfo, sizeof(strInfo)))
			{
				LogError("rip menu...");
				return Plugin_Handled;
			}
			
			if(!strcmp(strInfo, "ljenabled"))
			{
				g_PlayerStates[client].bLJEnabled = !g_PlayerStates[client].bLJEnabled;
				SetCookie(client, g_hCookieLJEnabled, g_PlayerStates[client].bLJEnabled);
				ShowSettingsPanel(client);
			}
			else if(!strcmp(strInfo, "beam"))
			{
				if(!g_PlayerStates[client].bBeam)
				{
					g_PlayerStates[client].bBeam = !g_PlayerStates[client].bBeam;
					SetCookie(client, g_hCookieBeam, g_PlayerStates[client].bBeam);
					g_PlayerStates[client].bBeamZ = false;
					SetCookie(client, g_hCookieBeamZ, g_PlayerStates[client].bBeamZ);
					ShowSettingsPanel(client);
				}
				else if(g_PlayerStates[client].bBeam && !g_PlayerStates[client].bBeamZ)
				{
					g_PlayerStates[client].bBeamZ = !g_PlayerStates[client].bBeamZ;
					SetCookie(client, g_hCookieBeamZ, g_PlayerStates[client].bBeamZ);
					ShowSettingsPanel(client);
				}
				else
				{
					g_PlayerStates[client].bBeam = !g_PlayerStates[client].bBeam;
					g_PlayerStates[client].bBeamZ = !g_PlayerStates[client].bBeamZ;
					SetCookie(client, g_hCookieBeam, g_PlayerStates[client].bBeam);
					SetCookie(client, g_hCookieBeamZ, g_PlayerStates[client].bBeamZ);
					ShowSettingsPanel(client);
				}
			}
			else if(!strcmp(strInfo, "sound"))
			{
				g_PlayerStates[client].bSound = !g_PlayerStates[client].bSound;
				SetCookie(client, g_hCookieSound, g_PlayerStates[client].bSound);
				ShowSettingsPanel(client);
			}
			else if(!strcmp(strInfo, "panel"))
			{
				g_PlayerStates[client].bShowPanel = !g_PlayerStates[client].bShowPanel;
				SetCookie(client, g_hCookieShowPanel, g_PlayerStates[client].bShowPanel);
				ShowSettingsPanel(client);
			}
			else if(!strcmp(strInfo, "bhopstats"))
			{
				g_PlayerStates[client].bShowBhopStats = !g_PlayerStates[client].bShowBhopStats;
				SetCookie(client, g_hCookieShowBhopStats, g_PlayerStates[client].bShowBhopStats);
				ShowSettingsPanel(client);
			}
			else if(!strcmp(strInfo, "showalljumps"))
			{
				g_PlayerStates[client].bShowAllJumps = !g_PlayerStates[client].bShowAllJumps;
				SetCookie(client, g_hCookieShowAllJumps, g_PlayerStates[client].bShowAllJumps);
				ShowSettingsPanel(client);
			}
			else if(!strcmp(strInfo, "hidechat"))
			{
				g_PlayerStates[client].bHideChat = !g_PlayerStates[client].bHideChat;
				SetCookie(client, g_hCookieHideChat, g_PlayerStates[client].bHideChat);
				ShowSettingsPanel(client);
			}
			else if(!strcmp(strInfo, "setminimums"))
			{
				ShowSetMinimumsPanel(client);
			}
		}
	}
	return Plugin_Handled;
}

public Action ShowSetMinimumsPanel(int client)
{
	Handle hMinMenu = CreateMenu(SetMinimumsMenuHandler);
	
	char buf[64];
	
	Format(buf, sizeof(buf), "Editing Values By + %s", g_PlayerStates[client].fMinStepper == 1 ? "[1] 5" : "1 [5]");
	AddMenuItem(hMinMenu, "stepper", buf);
	
	Format(buf, sizeof(buf), "[%.1f] LongJump Minimum", g_PlayerStates[client].fLJMin);
	AddMenuItem(hMinMenu, "ljmin", buf);
	
	Format(buf, sizeof(buf), "[%.1f] LJ NoDuck Minimum", g_PlayerStates[client].fLJNoDuckMin);
	AddMenuItem(hMinMenu, "ljnoduckmin", buf);
	
	Format(buf, sizeof(buf), "[%.1f] WeirdJump Minimum", g_PlayerStates[client].fWJMin);
	AddMenuItem(hMinMenu, "wjmin", buf);
	
	Format(buf, sizeof(buf), "[%.1f] BhopJump Minimum", g_PlayerStates[client].fBJMin);
	AddMenuItem(hMinMenu, "bjmin", buf);
	
	Format(buf, sizeof(buf), "[%.1f] LadderJump Minimum", g_PlayerStates[client].fLAJMin);
	AddMenuItem(hMinMenu, "lajmin", buf);
	
	Format(buf, sizeof(buf), "Reset Defaults");
	AddMenuItem(hMinMenu, "reset", buf);
	
	SetMenuExitBackButton(hMinMenu, true);
	
	SetMenuExitButton(hMinMenu, false);
	
	DisplayMenu(hMinMenu, client, 0);
	
	return Plugin_Handled;
}

public int SetMinimumsMenuHandler(Handle hMinMenu, MenuAction ma, int client, int nItem)
{
	switch(ma)
	{
		case MenuAction_Select:
		{
			char strInfo[16];
			
			if(!GetMenuItem(hMinMenu, nItem, strInfo, sizeof(strInfo)))
			{
				LogError("rip menu...");
				return Plugin_Handled;
			}
			
			if(!strcmp(strInfo, "stepper"))
			{
				g_PlayerStates[client].fMinStepper = g_PlayerStates[client].fMinStepper == 1.0 ? 5.0 : 1.0;
				ShowSetMinimumsPanel(client);
			}
			else if(!strcmp(strInfo, "ljmin"))
			{
				g_PlayerStates[client].fLJMin = g_PlayerStates[client].fLJMin <= 0.0 ? g_fLJMinMin : g_PlayerStates[client].fLJMin + g_PlayerStates[client].fMinStepper < g_fLJMinMax ? g_PlayerStates[client].fLJMin + g_PlayerStates[client].fMinStepper : g_PlayerStates[client].fLJMin == g_fLJMinMax ? 0.0 : g_fLJMinMax;
				SetFloatCookie(client, g_hCookieLJMin, g_PlayerStates[client].fLJMin);
				ShowSetMinimumsPanel(client);
			}
			else if(!strcmp(strInfo, "ljnoduckmin"))
			{
				g_PlayerStates[client].fLJNoDuckMin = g_PlayerStates[client].fLJNoDuckMin <= 0.0 ? g_fLJNoDuckMinMin : g_PlayerStates[client].fLJNoDuckMin + g_PlayerStates[client].fMinStepper < g_fLJNoDuckMinMax ? g_PlayerStates[client].fLJNoDuckMin + g_PlayerStates[client].fMinStepper : g_PlayerStates[client].fLJNoDuckMin == g_fLJNoDuckMinMax ? 0.0 : g_fLJNoDuckMinMax;
				SetFloatCookie(client, g_hCookieLJNoDuckMin, g_PlayerStates[client].fLJNoDuckMin);
				ShowSetMinimumsPanel(client);
			}
			else if(!strcmp(strInfo, "wjmin"))
			{
				g_PlayerStates[client].fWJMin = g_PlayerStates[client].fWJMin <= 0.0 ? g_fWJMinMin : g_PlayerStates[client].fWJMin + g_PlayerStates[client].fMinStepper < g_fWJMinMax ? g_PlayerStates[client].fWJMin + g_PlayerStates[client].fMinStepper : g_PlayerStates[client].fWJMin == g_fWJMinMax ? 0.0 : g_fWJMinMax;
				SetFloatCookie(client, g_hCookieWJMin, g_PlayerStates[client].fWJMin);
				ShowSetMinimumsPanel(client);
			}
			else if(!strcmp(strInfo, "bjmin"))
			{
				g_PlayerStates[client].fBJMin = g_PlayerStates[client].fBJMin <= 0.0 ? g_fBJMinMin : g_PlayerStates[client].fBJMin + g_PlayerStates[client].fMinStepper < g_fBJMinMax ? g_PlayerStates[client].fBJMin + g_PlayerStates[client].fMinStepper : g_PlayerStates[client].fBJMin == g_fBJMinMax ? 0.0 : g_fBJMinMax;
				SetFloatCookie(client, g_hCookieBJMin, g_PlayerStates[client].fBJMin);
				ShowSetMinimumsPanel(client);
			}
			else if(!strcmp(strInfo, "lajmin"))
			{
				g_PlayerStates[client].fLAJMin = g_PlayerStates[client].fLAJMin <= 0.0 ? g_fLAJMinMin : g_PlayerStates[client].fLAJMin + g_PlayerStates[client].fMinStepper < g_fLAJMinMax ? g_PlayerStates[client].fLAJMin + g_PlayerStates[client].fMinStepper : g_PlayerStates[client].fLAJMin == g_fLAJMinMax ? 0.0 : g_fLAJMinMax;
				SetFloatCookie(client, g_hCookieLAJMin, g_PlayerStates[client].fLAJMin);
				ShowSetMinimumsPanel(client);
			}
			else if(!strcmp(strInfo, "reset"))
			{
				SetFloatCookie(client, g_hCookieLJMin, 260.00);
				g_PlayerStates[client].fLJMin = 260.00;
				SetFloatCookie(client, g_hCookieLJNoDuckMin, 256.00);
				g_PlayerStates[client].fLJNoDuckMin = 256.00;
				SetFloatCookie(client, g_hCookieWJMin, 270.00);
				g_PlayerStates[client].fWJMin = 270.00;
				SetFloatCookie(client, g_hCookieBJMin, 270.00);
				g_PlayerStates[client].fBJMin = 270.00;
				SetFloatCookie(client, g_hCookieLAJMin, 140.00);
				g_PlayerStates[client].fLAJMin = 140.00;
				ShowSetMinimumsPanel(client);
			}
		}
		
		case(MenuAction_Cancel):
		{
			if(nItem == MenuCancel_ExitBack)
			{
				ShowSettingsPanel(client)
			}
		}
	}
	return Plugin_Handled;
}

public void SetFloatCookie(int client, Handle hCookie, float n)
{
	char strCookie[64];
	
	FloatToString(n, strCookie, sizeof(strCookie));

	SetClientCookie(client, hCookie, strCookie);
}

public void SetCookie(int client, Handle hCookie, int n)
{
	char strCookie[64];
	
	IntToString(n, strCookie, sizeof(strCookie));

	SetClientCookie(client, hCookie, strCookie);
}

public Action Command_LJPanel(int client, int args)
{
	g_PlayerStates[client].bShowPanel = !g_PlayerStates[client].bShowPanel;
	SetCookie(client, g_hCookieShowPanel, g_PlayerStates[client].bShowPanel);
	Shavit_PrintToChat(client, "Longjump panel %s%s", gS_ChatStrings.sVariable, g_PlayerStates[client].bShowPanel ? "enabled" : "disabled");
	
	return Plugin_Handled;
}

public Action Command_LJBeam(int client, int args)
{
	if(g_PlayerStates[client].bBeam)
	{
		g_PlayerStates[client].bBeamZ = false;
		SetCookie(client, g_hCookieBeamZ, g_PlayerStates[client].bBeamZ);
	}
	g_PlayerStates[client].bBeam = !g_PlayerStates[client].bBeam;
	SetCookie(client, g_hCookieBeam, g_PlayerStates[client].bBeam);
	Shavit_PrintToChat(client, "Longjump beam %s%s", gS_ChatStrings.sVariable, g_PlayerStates[client].bBeam ? "enabled" : "disabled");
	
	return Plugin_Handled;
}

public Action Command_LJSound(int client, int args)
{
	g_PlayerStates[client].bSound = !g_PlayerStates[client].bSound;
	SetCookie(client, g_hCookieSound, g_PlayerStates[client].bSound);
	Shavit_PrintToChat(client, "Longjump sounds %s%s", gS_ChatStrings.sVariable, g_PlayerStates[client].bSound ? "enabled" : "disabled");
	
	return Plugin_Handled;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	g_PlayerStates[client].fStyleRunSpeed = Shavit_GetStyleSettingFloat(newstyle, "runspeed");
	g_PlayerStates[client].bStyleAuto = Shavit_GetStyleSettingBool(newstyle, "autobhop");
	g_PlayerStates[client].fStyleAA = Shavit_GetStyleSettingFloat(newstyle, "airaccelerate");
}

public void GetStrafeKey(char[] str, STRAFE_DIRECTION Dir)
{
	if(Dir == SD_W)
	{
		strcopy(str, 3, "W");
	}
	else if(Dir == SD_A)
	{
		strcopy(str, 3, "A");
	}
	else if(Dir == SD_S)
	{
		strcopy(str, 3, "S");
	}
	else if(Dir == SD_D)
	{
		strcopy(str, 3, "D");
	}
	else if(Dir == SD_WA)
	{
		strcopy(str, 3, "WA");
	}
	else if(Dir == SD_WD)
	{
		strcopy(str, 3, "WD");
	}
	else if(Dir == SD_SA)
	{
		strcopy(str, 3, "SA");
	}
	else if(Dir == SD_SD)
	{
		strcopy(str, 3, "SD");
	}
}

public void Native_CancelJump(Handle hPlugin, int nParams)
{
	CancelJump(GetNativeCell(1));
}

public void CancelJump(int client)
{
	g_PlayerStates[client].bOnGround = true;
}

public Action Event_PlayerJump(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	PlayerJump(client, JT_LONGJUMP);
	
	return Plugin_Handled;
}

// cba with another enum so JT_LONGJUMP = jump, JT_DROP = slide off edge, JT_LADDERJUMP = ladder
public Action PlayerJump(int client, JUMP_TYPE JumpType2)
{
	if(!g_PlayerStates[client].bLJEnabled && g_PlayerStates[client].nSpectators < 1)
	{
		return Plugin_Handled;
	}
	
	g_PlayerStates[client].bOnGround = false;
	
	float fTime = GetGameTime();
	if(fTime - g_PlayerStates[client].fLandTime < BHOP_TIME)
	{
		g_PlayerStates[client].nBhops++;
	}
	else
	{
		g_PlayerStates[client].nBhops = 0;
		
		g_PlayerStates[client].IllegalJumpFlags = IJF_NONE;
	}
	
	g_PlayerStates[client].fLastJumpHeightDelta = g_PlayerStates[client].fHeightDelta;
	
	for(int i = 0; i < g_PlayerStates[client].nStrafes && i < MAX_STRAFES; i++)
	{
		g_PlayerStates[client].fStrafeGain[i] = 0.0;
		g_PlayerStates[client].fStrafeLoss[i] = 0.0;
		g_PlayerStates[client].fStrafeSync[i] = 0.0;
		g_PlayerStates[client].nStrafeTicks[i] = 0;
		g_PlayerStates[client].nStrafeTicksSynced[i] = 0;
	}
	
	// Reset stuff
	g_PlayerStates[client].JumpDir = JD_NONE;
	g_PlayerStates[client].CurStrafeDir = SD_NONE;
	g_PlayerStates[client].nStrafes = 0;
	g_PlayerStates[client].fSync = 0.0;
	g_PlayerStates[client].fMaxSpeed = 0.0;
	g_PlayerStates[client].fJumpHeight = 0.0;
	g_PlayerStates[client].nTotalTicks = 0;
	g_PlayerStates[client].fTotalAngle = 0.0;
	g_PlayerStates[client].fSyncedAngle = 0.0;
	g_PlayerStates[client].fEdge = -1.0;
	g_PlayerStates[client].fBlockDistance = -1.0;
	g_PlayerStates[client].bStamina = !GetEntPropFloat(client, Prop_Send, "m_flStamina");
	g_PlayerStates[client].bFailedBlock = false;
	g_PlayerStates[client].fTrajectory = 0.0;
	g_PlayerStates[client].fGain = 0.0;
	g_PlayerStates[client].fLoss = 0.0;
	g_PlayerStates[client].nJumpTick = GetGameTickCount();
	
	if(JumpType2 == JT_LONGJUMP)
	{
		g_PlayerStates[client].fBlockDistance = GetBlockDistance(client);
	}
	
	
	g_PlayerStates[client].LastJumpType = g_PlayerStates[client].JumpType;
	
	// Determine jump type
	if(JumpType2 == JT_DROP || JumpType2 == JT_LADDERJUMP)
	{
		g_PlayerStates[client].JumpType = JumpType2;
	}
	else
	{
		if(g_PlayerStates[client].nBhops > 1)
		{
			g_PlayerStates[client].JumpType = JT_BHOP;
		}
		else if(g_PlayerStates[client].nBhops == 1)
		{
			if(g_PlayerStates[client].LastJumpType == JT_DROP)
			{
				g_PlayerStates[client].fWJDropPre = g_PlayerStates[client].fPrestrafe;
				g_PlayerStates[client].JumpType = JT_WEIRDJUMP;
			}
			else if(g_PlayerStates[client].fLastJumpHeightDelta > HEIGHT_DELTA_MIN(JT_LONGJUMP))
			{
				g_PlayerStates[client].JumpType = JT_BHOPJUMP;
			}
			else
			{
				g_PlayerStates[client].JumpType = JT_BHOP;
			}
		}
		else
		{
			if(GetEntProp(client, Prop_Send, "m_bDucking", 1))
			{
				g_PlayerStates[client].JumpType = JT_COUNTJUMP;
			}
			else
			{
				g_PlayerStates[client].JumpType = JT_LONGJUMP;
			}
		}
	}
	
	// Jumpoff origin
	float vOrigin[3];
	GetClientAbsOrigin(client, vOrigin);
	Array_Copy(vOrigin, g_PlayerStates[client].vJumpOrigin, 3);
	
	// Prestrafe
	g_PlayerStates[client].fPrestrafe = GetSpeed(client);
	
	if(g_PlayerStates[client].JumpType == JT_LONGJUMP)
	{
		if(g_PlayerStates[client].fPrestrafe > g_fLJMaxPrestrafe + g_PlayerStates[client].fStyleRunSpeed)
		{
			g_PlayerStates[client].IllegalJumpFlags |= IJF_PRESTRAFE;
		}
	}
	
	if(JumpType2 == JT_LONGJUMP)
	{
		g_PlayerStates[client].fEdge = GetEdge(client);
	}
	
	//Beam
	if(g_PlayerStates[client].bBeam)
	{
		StopBeam(client);
		g_PlayerStates[client].bBeam = true;
	}
	
	//Beam (spectators)
	if(g_PlayerStates[client].nSpectators > 0)
	{
		for(int s = 1; s <= MaxClients; s++)
		{
			if(IsClientInGame(s) && !IsClientSourceTV(s) && !IsClientReplay(s) && !IsFakeClient(s) && g_PlayerStates[s].nSpectatorTarget == client)
			{
				if(g_PlayerStates[s].bLJEnabled && g_PlayerStates[s].bBeam)
				{
					StopBeam(s);
					g_PlayerStates[s].bBeam = true;
				}
			}
		}
	}
	return Plugin_Handled;
}

public void StopBeam(int client)
{
	g_PlayerStates[client].bBeam = false;
}

public void GetJumpDistance(int client)
{
	float vCurOrigin[3];
	GetClientAbsOrigin(client, vCurOrigin);
	
	g_PlayerStates[client].fHeightDelta = vCurOrigin[2] - g_PlayerStates[client].vJumpOrigin[2];
	
	vCurOrigin[2] = 0.0;
	
	float v[3];
	Array_Copy(g_PlayerStates[client].vJumpOrigin, v, 3);
	
	v[2] = 0.0;
	
	if(g_PlayerStates[client].JumpType == JT_LADDERJUMP)
	{
		g_PlayerStates[client].fJumpDistance = GetVectorDistance(v, vCurOrigin);
	}
	else
	{
		g_PlayerStates[client].fJumpDistance = GetVectorDistance(v, vCurOrigin) + 32;
	}
	
	g_PlayerStates[client].bDuck = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked", 1));
	//g_PlayerStates[client].nTotalTicks = GetGameTickCount() - g_PlayerStates[client].nJumpTick;
}

public void GetJumpDistanceLastTick(int client)
{
	float vCurOrigin[3];
	Array_Copy(g_PlayerStates[client].vLastOrigin, vCurOrigin, 3);
	
	g_PlayerStates[client].fHeightDelta = vCurOrigin[2] - g_PlayerStates[client].vJumpOrigin[2];
	
	vCurOrigin[2] = 0.0;
	
	float v[3];
	Array_Copy(g_PlayerStates[client].vJumpOrigin, v, 3);
	
	v[2] = 0.0;
	
	if(g_PlayerStates[client].JumpType == JT_LADDERJUMP)
	{
		g_PlayerStates[client].fJumpDistance = GetVectorDistance(v, vCurOrigin);
	}
	else
	{
		g_PlayerStates[client].fJumpDistance = GetVectorDistance(v, vCurOrigin) + 32;
	}
	
	g_PlayerStates[client].bDuck = g_PlayerStates[client].bSecondLastDuckState;
	//g_PlayerStates[client].nTotalTicks = GetGameTickCount() - g_PlayerStates[client].nJumpTick;
	//g_PlayerStates[client].nTotalTicks -= 1;
}

public void CheckValidJump(int client)
{
	float vOrigin[3];
	GetClientAbsOrigin(client, vOrigin);
	
	// Check gravity
	float fGravity = GetEntPropFloat(client, Prop_Data, "m_flGravity");
	if(fGravity != 1.0 && fGravity != 0.0)
	{
		g_PlayerStates[client].IllegalJumpFlags |= IJF_GRAVITY;
	}
	
	// Check speed
	if(GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue") != 1.0)
	{
		g_PlayerStates[client].IllegalJumpFlags |= IJF_LAGGEDMOVEMENTVALUE;
	}
	
	// Check noclip
	if(GetEntityMoveType(client) & MOVETYPE_NOCLIP)
	{
		g_PlayerStates[client].IllegalJumpFlags |= IJF_NOCLIP;
	}
	
	// Check water
	if(GetEntProp(client, Prop_Data, "m_nWaterLevel") > 0)
	{
		g_PlayerStates[client].IllegalJumpFlags |= IJF_WATER;
	}
	
	if(g_PlayerStates[client].JumpType != JT_WEIRDJUMP && vOrigin[2] < g_PlayerStates[client].vJumpOrigin[2] + HEIGHT_DELTA_MIN(g_PlayerStates[client].JumpType))
	{
		GetJumpDistanceLastTick(client);
		if(g_PlayerStates[client].fBlockDistance != -1)
			g_PlayerStates[client].bFailedBlock = true;
		PlayerLand(client);
		return;
	}
	
	// Teleport check
	float vLastOrig[3];
	float vLastVel[3];
	float vVel[3];
	
	Array_Copy(g_PlayerStates[client].vLastOrigin, vLastOrig, 3);
	Array_Copy(g_PlayerStates[client].vLastVelocity, vLastVel, 3);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVel);
	
	vLastOrig[2] = 0.0;
	vOrigin[2] = 0.0;
	vLastVel[2] = 0.0;
	vVel[2] = 0.0;
	
	if(GetVectorDistance(vLastOrig, vOrigin) > GetVectorLength(vVel) / (1.0 / GetTickInterval()) + 0.001)
	{
		g_PlayerStates[client].IllegalJumpFlags |= IJF_TELEPORT;
	}
}

public void TBAnglesToUV(float vOut[3], const float vAngles[3])
{
	vOut[0] = Cosine(vAngles[1] * FLOAT_PI / 180.0) * Cosine(vAngles[0] * FLOAT_PI / 180.0);
	vOut[1] = Sine(vAngles[1] * FLOAT_PI / 180.0) * Cosine(vAngles[0] * FLOAT_PI / 180.0);
	vOut[2] = -Sine(vAngles[0] * FLOAT_PI / 180.0);
}

public void _OnPlayerRunCmd(int client, int buttons, const float vOrigin[3], const float vAngles[3], const float vVelocity[3], bool bDucked, bool bGround)
{
	if(!g_PlayerStates[client].bOnGround)
	{
		CheckValidJump(client);
	}

	//Beam
	if(!bGround && GetEntityMoveType(client) == MOVETYPE_WALK)
	{
		if(g_PlayerStates[client].bBeam || g_PlayerStates[client].nSpectators > 0)
		{
			float v1[3];
			float v2[3];
			v1[0] = vOrigin[0];
			v1[1] = vOrigin[1];
			v2[0] = g_PlayerStates[client].vLastOrigin[0];
			v2[1] = g_PlayerStates[client].vLastOrigin[1];
				
			if(g_PlayerStates[client].IllegalJumpFlags != IJF_TELEPORT && GetVectorDistance(g_PlayerStates[client].vLastOrigin, vOrigin) < 64.00)
			{
				
				
				int color[4] = {255, 0, 50, 255};
				
				if(g_PlayerStates[client].CurStrafeDir % view_as<STRAFE_DIRECTION>(2))
				{
					//color[0] = 100;
					color[2] = 100;
				}
				
				if(g_PlayerStates[client].bBeam && (g_PlayerStates[client].bShowBhopStats || g_PlayerStates[client].nBhops < 2))
				{
					if(g_PlayerStates[client].bBeamZ || g_PlayerStates[client].JumpType == JT_DROP)
					{
						v1[2] = vOrigin[2];
						v2[2] = g_PlayerStates[client].vLastOrigin[2];
					}
					else
					{
						v1[2] = g_PlayerStates[client].vJumpOrigin[2];
						v2[2] = g_PlayerStates[client].vJumpOrigin[2];
					}
					TE_SetupBeamPoints(v1, v2, g_BeamModel, 0, 0, 0, 5.0, 3.0, 3.0, 10, 0.0, color, 0);
					TE_SendToClient(client);
				}
				
				if(g_PlayerStates[client].nSpectators > 0)
				{
					for(int s = 1; s <= MaxClients; s++)
					{
						if(IsClientInGame(s) && !IsClientSourceTV(s) && !IsClientReplay(s) && !IsFakeClient(s) && g_PlayerStates[s].nSpectatorTarget == client)
						{
							if(g_PlayerStates[s].bBeam && (g_PlayerStates[s].bShowBhopStats || g_PlayerStates[client].nBhops < 2))
							{
								if(g_PlayerStates[s].bBeamZ || g_PlayerStates[client].JumpType == JT_DROP)
								{
									v1[2] = vOrigin[2];
									v2[2] = g_PlayerStates[client].vLastOrigin[2];
								}
								else
								{
									v1[2] = g_PlayerStates[client].vJumpOrigin[2];
									v2[2] = g_PlayerStates[client].vJumpOrigin[2];
								}
								TE_SetupBeamPoints(v1, v2, g_BeamModel, 0, 0, 0, 5.0, 3.0, 3.0, 10, 0.0, color, 0);
								TE_SendToClient(s);
							}
						}
					}
				}
			}
		}
	}
	
	
	// Call PlayerJump for ladder jumps or walking off the edge
	if(GetEntityMoveType(client) == MOVETYPE_LADDER)
	{
		g_PlayerStates[client].bOnLadder = true;
	}
	else
	{
		if(g_PlayerStates[client].bOnLadder)
		{
			PlayerJump(client, JT_LADDERJUMP);
		}
		
		g_PlayerStates[client].bOnLadder = false;
	}
	
	if(!bGround)
	{
		if(g_PlayerStates[client].bOnGround)
		{
			PlayerJump(client, JT_DROP);
		}
	}
	
	
	if(g_PlayerStates[client].bOnGround || g_PlayerStates[client].nStrafes >= MAX_STRAFES || g_PlayerStates[client].bFailedBlock)
	{
		// dumb language
		if((bGround || g_PlayerStates[client].bOnLadder) && !g_PlayerStates[client].bOnGround)
		{
			PlayerLand(client);
		}
		
		return;
	}
	
	
	if(!bGround)
	{
		g_PlayerStates[client].nLastAerialTick = GetGameTickCount();
		
		if(GetVSpeed(vVelocity) > g_PlayerStates[client].fMaxSpeed)
			g_PlayerStates[client].fMaxSpeed = GetVSpeed(vVelocity);
		
		if(vOrigin[2] - g_PlayerStates[client].vJumpOrigin[2] > g_PlayerStates[client].fJumpHeight)
			g_PlayerStates[client].fJumpHeight = vOrigin[2] - g_PlayerStates[client].vJumpOrigin[2];
		
		// Record the failed distance, but since it will trigger if you duck late, only save it if it's certain that the player will not land
		//original code has if(blockmode && !failedblock)
		if(g_PlayerStates[client].JumpType != JT_BHOP && g_PlayerStates[client].JumpType != JT_WEIRDJUMP &&
		(bDucked && vOrigin[2] <= g_PlayerStates[client].vJumpOrigin[2] + 1.0 ||
		!bDucked && vOrigin[2] <= g_PlayerStates[client].vJumpOrigin[2] + 1.5) &&
		vOrigin[2] >= g_PlayerStates[client].vJumpOrigin[2] + HEIGHT_DELTA_MIN(JT_LONGJUMP))
		{
			GetJumpDistance(client);
		}
		
		// Check if the player is still capable of landing
		//original code has if(blockmode && !failedblock)
		if(g_PlayerStates[client].JumpType != JT_BHOP && g_PlayerStates[client].JumpType != JT_WEIRDJUMP &&
		(bDucked && vOrigin[2] <= g_PlayerStates[client].vJumpOrigin[2] + HEIGHT_DELTA_MIN(JT_LONGJUMP)/* + 1.0*/ || // You land at 0.79 elevation when ducking
		!bDucked && vOrigin[2] <= g_PlayerStates[client].vJumpOrigin[2] - 10.5))
		// Ducking increases your origin by 8.5; you land at 1.47 units elevation when ducking, so around 10.0; 10.5 for good measure
		{
			//uncommenting this will make beam turn off when doing certain things
			//like weirdjumping, and the beam will only show for the dropjump part
			//of a wj.. removing this all fixes it though so (^:
			//Beam
			//StopBeam(client);
			
			//if(g_PlayerStates[client].nSpectators > 0)
			//{
			//	for(int s = 1; s <= MaxClients; s++)
			//	{
			//		if(g_PlayerStates[s].nSpectatorTarget == client)
			//		{
						//StopBeam(s);
			//		}
			//	}
			//}
			
			g_PlayerStates[client].bDuck = bDucked;
			g_PlayerStates[client].bFailedBlock = true;
			
			if(bGround && !g_PlayerStates[client].bOnGround)
			{
				PlayerLand(client);
			}
			
			return;
		}
	}
	
	
	if(g_PlayerStates[client].JumpDir == JD_BACKWARDS)
	{
		float vAnglesUV[3];
		TBAnglesToUV(vAnglesUV, vAngles);
		
		float vVelocityDir[3];
		vVelocityDir = vVelocity;
		vVelocityDir[2] = 0.0;
		NormalizeVector(vVelocityDir, vVelocityDir);
		
		if(ArcCosine(GetVectorDotProduct(vAnglesUV, vVelocityDir)) < FLOAT_PI / 2)
		{
			g_PlayerStates[client].JumpDir = JD_NORMAL;
		}
	}
	
	// check for multiple keys -- it will spam strafes when multiple are held without this
	int nButtonCount;
	if(buttons & IN_MOVELEFT)
		nButtonCount++;
	if(buttons & IN_MOVERIGHT)
		nButtonCount++;
	if(buttons & IN_FORWARD)
		nButtonCount++;
	if(buttons & IN_BACK)
		nButtonCount++;
	
	if(nButtonCount == 1)
	{
		if(g_PlayerStates[client].CurStrafeDir != SD_A && buttons & IN_MOVELEFT)
		{
			if(g_PlayerStates[client].JumpDir == JD_NONE)
			{
				float vAnglesUV[3];
				TBAnglesToUV(vAnglesUV, vAngles);
				
				float vVelocityDir[3];
				vVelocityDir = vVelocity;
				vVelocityDir[2] = 0.0;
				NormalizeVector(vVelocityDir, vVelocityDir);
				
				if(ArcCosine(GetVectorDotProduct(vAnglesUV, vVelocityDir)) > FLOAT_PI / 2)
				{
					g_PlayerStates[client].JumpDir = JD_BACKWARDS;
				}
				else
				{
					g_PlayerStates[client].JumpDir = JD_NORMAL;
				}
			}
			
			if(g_PlayerStates[client].JumpDir == JD_SIDEWAYS)
			{
				g_PlayerStates[client].JumpDir = JD_NORMAL;
			}
			
			g_PlayerStates[client].StrafeDir[g_PlayerStates[client].nStrafes] = SD_A;
			g_PlayerStates[client].CurStrafeDir = SD_A;
			g_PlayerStates[client].nStrafes++;
		}
		else if(g_PlayerStates[client].CurStrafeDir != SD_D && buttons & IN_MOVERIGHT)
		{
			if(g_PlayerStates[client].JumpDir == JD_NONE)
			{
				float vAnglesUV[3];
				TBAnglesToUV(vAnglesUV, vAngles);
				
				float vVelocityDir[3];
				vVelocityDir = vVelocity;
				vVelocityDir[2] = 0.0;
				NormalizeVector(vVelocityDir, vVelocityDir);
				
				if(ArcCosine(GetVectorDotProduct(vAnglesUV, vVelocityDir)) > FLOAT_PI / 2)
				{
					g_PlayerStates[client].JumpDir = JD_BACKWARDS;
				}
				else
				{
					g_PlayerStates[client].JumpDir = JD_NORMAL;
				}
			}
			
			else if(g_PlayerStates[client].JumpDir == JD_SIDEWAYS)
			{
				g_PlayerStates[client].JumpDir = JD_NORMAL;
			}
			
			g_PlayerStates[client].StrafeDir[g_PlayerStates[client].nStrafes] = SD_D;
			g_PlayerStates[client].CurStrafeDir = SD_D;
			g_PlayerStates[client].nStrafes++;
		}
		else if(g_PlayerStates[client].CurStrafeDir != SD_W && buttons & IN_FORWARD)
		{
			if(g_PlayerStates[client].JumpDir == JD_NONE && (vVelocity[0] || vVelocity[1]))
			{
				float vAnglesUV[3];
				TBAnglesToUV(vAnglesUV, vAngles);
				
				float vVelocityDir[3];
				vVelocityDir = vVelocity;
				vVelocityDir[2] = 0.0;
				NormalizeVector(vVelocityDir, vVelocityDir);
				
				if(DegToRad(90.0 - SW_ANGLE_THRESHOLD) < ArcCosine(GetVectorDotProduct(vAnglesUV, vVelocityDir)) < DegToRad(90.0 + SW_ANGLE_THRESHOLD))
				{
					g_PlayerStates[client].JumpDir = JD_SIDEWAYS;
				}
			}
			
			g_PlayerStates[client].StrafeDir[g_PlayerStates[client].nStrafes] = SD_W;
			g_PlayerStates[client].CurStrafeDir = SD_W;
			g_PlayerStates[client].nStrafes++;
		}
		else if(g_PlayerStates[client].CurStrafeDir != SD_S && buttons & IN_BACK)
		{
			if(g_PlayerStates[client].JumpDir == JD_NONE && (vVelocity[0] || vVelocity[1]))
			{
				float vAnglesUV[3];
				TBAnglesToUV(vAnglesUV, vAngles);
				
				float vVelocityDir[3];
				vVelocityDir = vVelocity;
				vVelocityDir[2] = 0.0;
				NormalizeVector(vVelocityDir, vVelocityDir);
				
				if(DegToRad(90.0 - SW_ANGLE_THRESHOLD) < ArcCosine(GetVectorDotProduct(vAnglesUV, vVelocityDir)) < DegToRad(90.0 + SW_ANGLE_THRESHOLD))
				{
					g_PlayerStates[client].JumpDir = JD_SIDEWAYS;
				}
			}
			
			g_PlayerStates[client].StrafeDir[g_PlayerStates[client].nStrafes] = SD_S;
			g_PlayerStates[client].CurStrafeDir = SD_S;
			g_PlayerStates[client].nStrafes++;
		}
	}
	
	if(g_PlayerStates[client].nStrafes > 0)
	{
		float v[3];
		float v2[3];
		Array_Copy(g_PlayerStates[client].vLastVelocity, v, 3);
		Array_Copy(g_PlayerStates[client].vLastAngles, v2, 3);
		
		float fVelDelta = GetSpeed(client) - GetVSpeed(v);
		
		float fAngleDelta = fmod((FloatAbs(vAngles[1] - v2[1]) + 180.0), 360.0) - 180.0;
		
		g_PlayerStates[client].nStrafeTicks[g_PlayerStates[client].nStrafes - 1]++;
		
		g_PlayerStates[client].fTotalAngle += fAngleDelta;
		
		if(fVelDelta > 0.0)
		{
			g_PlayerStates[client].fStrafeGain[g_PlayerStates[client].nStrafes - 1] += fVelDelta;
			g_PlayerStates[client].fGain += fVelDelta;
			
			g_PlayerStates[client].nStrafeTicksSynced[g_PlayerStates[client].nStrafes - 1]++;
			
			g_PlayerStates[client].fSyncedAngle += fAngleDelta;
		}
		else
		{
			g_PlayerStates[client].fStrafeLoss[g_PlayerStates[client].nStrafes - 1] -= fVelDelta;
			g_PlayerStates[client].fLoss -= fVelDelta;
		}
	}
	
	g_PlayerStates[client].nTotalTicks++;
	g_PlayerStates[client].fTrajectory += GetSpeed(client) * GetTickInterval();
	
	if(bGround && !g_PlayerStates[client].bOnGround)
	{
		PlayerLand(client);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float vAngles[3], int &weapon)
{
	// Manage spectators
	if(IsClientObserver(client))
	{
		int nObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
		
		if(nObserverMode == 4 || nObserverMode == 3)
		{
			int nTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
			
			if(g_PlayerStates[client].nSpectatorTarget != nTarget)
			{
				if(nTarget > 0 && nTarget <= MaxClients)
				{
					if(g_PlayerStates[client].nSpectatorTarget != -1)
					{
						g_PlayerStates[g_PlayerStates[client].nSpectatorTarget].nSpectators--;
					}
					g_PlayerStates[nTarget].nSpectators++;
					g_PlayerStates[client].nSpectatorTarget = nTarget;
				}
			}
		}
		
		return;
	}
	else
	{
		if(g_PlayerStates[client].nSpectatorTarget != -1)
		{
			g_PlayerStates[g_PlayerStates[client].nSpectatorTarget].nSpectators--;
			g_PlayerStates[client].nSpectatorTarget = -1;
		}
	}
	
	if(!g_PlayerStates[client].bLJEnabled && g_PlayerStates[client].nSpectators < 1)
	{
		return;
	}
	
	float vOrigin[3];
	float vVelocity[3];
	bool bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked", 1));
	bool bGround = view_as<bool>(GetEntityFlags(client) & FL_ONGROUND);
	
	GetClientAbsOrigin(client, vOrigin);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	
	_OnPlayerRunCmd(client, buttons, vOrigin, vAngles, vVelocity, bDucked, bGround);
	
	Array_Copy(vOrigin, g_PlayerStates[client].vLastOrigin, 3);
	Array_Copy(vAngles, g_PlayerStates[client].vLastAngles, 3);
	Array_Copy(vVelocity, g_PlayerStates[client].vLastVelocity, 3);
	g_PlayerStates[client].bSecondLastDuckState = g_PlayerStates[client].bLastDuckState;
	g_PlayerStates[client].bLastDuckState = bDucked;
	g_PlayerStates[client].LastButtons = buttons;
	
	return;
}

public Action PlayerLand(int client)
{
	g_PlayerStates[client].bOnGround = true;
	g_PlayerStates[client].fLandTime = GetGameTime();
	bool clientsToSend[MAXPLAYERS+1];
	bool sendLJ = false;
	
	if(g_PlayerStates[client].bLJEnabled || g_PlayerStates[client].nSpectators > 0)
	{
		for(int s = 1; s <= MaxClients; s++)
		{
			if(IsClientInGame(s) && !IsClientSourceTV(s) && !IsClientReplay(s) && !IsFakeClient(s) && (g_PlayerStates[s].nSpectatorTarget == client || s == client))
			{
				if(g_PlayerStates[s].bLJEnabled)
				{
					clientsToSend[s] = true;
					sendLJ = true;
				}
			}
		}
	}
	
	// if nobody wants stats
	if(!sendLJ)
	{
		return Plugin_Handled;
	}

	// Final CheckValidJump
	//CheckValidJump(client);
	
	float vCurOrigin[3];
	GetClientAbsOrigin(client, vCurOrigin);
	g_PlayerStates[client].fFinalSpeed = GetSpeed(client);
	
	// Calculate distances
	if(!g_PlayerStates[client].bFailedBlock || // if block longjump failed, distances have already been written in mid-air.
	vCurOrigin[2] - g_PlayerStates[client].vJumpOrigin[2] >= HEIGHT_DELTA_MIN(JT_LONGJUMP)) // bugs sometimes if you land on last tick (I think) idk how else 2 fix
	{
		GetJumpDistance(client);
		
		g_PlayerStates[client].bFailedBlock = false;
	}
	
	// don't show drop stats
	if(g_PlayerStates[client].JumpType == JT_DROP)
		return Plugin_Handled;
	
	//don't show jumps with distance > DISTANCE_MAX
	if(g_PlayerStates[client].fJumpDistance > DISTANCE_MAX(g_PlayerStates[client].JumpType))
	{
		return Plugin_Handled;
	}
	
	// show jump check
	for(int s = 1; s < sizeof(clientsToSend); s++)
	{
		if(clientsToSend[s])
		{
			if(!g_PlayerStates[s].bShowAllJumps)
			{
				//don't show up/downjumps
				if(g_PlayerStates[client].fHeightDelta > HEIGHT_DELTA_MAX(g_PlayerStates[client].JumpType) || g_PlayerStates[client].fHeightDelta < HEIGHT_DELTA_MIN(g_PlayerStates[client].JumpType))
				{
					clientsToSend[s] = false;
				}
				
				if(g_PlayerStates[client].fHeightDelta < HEIGHT_DELTA_MIN(view_as<JUMP_TYPE>(g_PlayerStates[client].JumpType == JT_BHOP ? JT_BHOPJUMP : g_PlayerStates[client].JumpType)))
				{
					clientsToSend[s] = false;
				}
				
				if(g_PlayerStates[client].JumpType == JT_BHOPJUMP && g_PlayerStates[client].fLastJumpHeightDelta < HEIGHT_DELTA_MIN(JT_BHOPJUMP))
				{
					clientsToSend[s] = false;
				}
	
				switch(g_PlayerStates[client].JumpType)
				{
					case JT_LONGJUMP, JT_COUNTJUMP:
					{
						//noduck
						if(!g_PlayerStates[client].bDuck && !g_PlayerStates[client].bLastDuckState && g_PlayerStates[client].fJumpDistance < g_PlayerStates[s].fLJNoDuckMin)
						{
							clientsToSend[s] = false;
						}
						else if(g_PlayerStates[client].fJumpDistance < g_PlayerStates[s].fLJMin)
						{
							clientsToSend[s] = false;
						}
					}
					case JT_WEIRDJUMP:
					{
						if(g_PlayerStates[client].fJumpDistance < g_PlayerStates[s].fWJMin || (FloatAbs(g_PlayerStates[client].fLastJumpHeightDelta) > g_fWJDropMax))
						{
							clientsToSend[s] = false;
						}
					}
					case JT_BHOPJUMP:
					{
						if(g_PlayerStates[client].fJumpDistance < g_PlayerStates[s].fBJMin)
						{
							clientsToSend[s] = false;
						}
					}
					case JT_LADDERJUMP:
					{
						if(g_PlayerStates[client].fJumpDistance < g_PlayerStates[s].fLAJMin)
						{
							clientsToSend[s] = false;
						}
					}
					case JT_BHOP:
					{
						if(!g_PlayerStates[s].bShowBhopStats)
						{
							clientsToSend[s] = false;
						}
					}
				}
			}
			else
			{
				if(g_PlayerStates[client].JumpType == JT_BHOP)
				{
					if(!g_PlayerStates[s].bShowBhopStats)
					{
						clientsToSend[s] = false;
					}
				}
			}
		}
	}
	
	// Check whether the player actually moved past the block edge
	if(!g_PlayerStates[client].bFailedBlock)
	{
		if(!g_PlayerStates[client].vBlockNormal[0] || !g_PlayerStates[client].vBlockNormal[1])
		{
			// bools are not actually handled as 1 bit bools but 32 bit cells so n = normal.y gives out of bounds exception
			// !!normal.y or !normal.x rather
			// pawn good
			int n = !g_PlayerStates[client].vBlockNormal[0];
			
			if(g_PlayerStates[client].vBlockNormal[view_as<int>(n)] > 0.0)
			{
				if(vCurOrigin[n] + 16.0 * g_PlayerStates[client].vBlockNormal[n] < g_PlayerStates[client].vBlockEndPos[n])
				{
					g_PlayerStates[client].bFailedBlock = true;
				}
			}
			else
			{
				if(vCurOrigin[n] + 16.0 * g_PlayerStates[client].vBlockNormal[n] > g_PlayerStates[client].vBlockEndPos[n])
				{
					g_PlayerStates[client].bFailedBlock = true;
				}
			}
		}
		else
		{
			float vAdjCurOrigin[3];
			float vInvNormal[3];
			vAdjCurOrigin = vCurOrigin;
			Array_Copy(g_PlayerStates[client].vBlockNormal, vInvNormal, 2);
			ScaleVector(vInvNormal, -1.0);
			Adjust(vAdjCurOrigin, vInvNormal);
			
			
			// f(endpos.x) + (origin.x - endpos.x) * b = (f(endpos.x) - endpos.x * b) + origin.x * b = f(0) + origin.x * b
			// block normal is perpendicular to the edge direction, so b = 1 / (normal rot 90).x
			// dx and dy should have same sign so ccw rot if facing down, cw rot if up
			float b = 1 / (g_PlayerStates[client].vBlockNormal[0] < 0 ? g_PlayerStates[client].vBlockNormal[1] : -g_PlayerStates[client].vBlockNormal[1]);
			float fPos = g_PlayerStates[client].vBlockEndPos[1] + (vAdjCurOrigin[0] - g_PlayerStates[client].vBlockEndPos[0]) * b;
			
			if(g_PlayerStates[client].vBlockNormal[1] > 0.0 ? vAdjCurOrigin[1] < fPos : vAdjCurOrigin[1] > fPos)
			{
				g_PlayerStates[client].bFailedBlock = true;
			}
		}
	}
	
	
	// sum sync
	g_PlayerStates[client].fSync = 0.0;
	
	for(int i = 0; i < g_PlayerStates[client].nStrafes && i < MAX_STRAFES; i++)
	{
		g_PlayerStates[client].fSync += g_PlayerStates[client].nStrafeTicksSynced[i];
		g_PlayerStates[client].fStrafeSync[i] = float(g_PlayerStates[client].nStrafeTicksSynced[i]) / g_PlayerStates[client].nStrafeTicks[i] * 100;
	}
	
	g_PlayerStates[client].fSync /= g_PlayerStates[client].nTotalTicks;
	g_PlayerStates[client].fSync *= 100;
	
	//Jump type
	char strJump[32];
	
	if(g_PlayerStates[client].fHeightDelta > HEIGHT_DELTA_MAX(g_PlayerStates[client].JumpType))
	{
		if(g_PlayerStates[client].JumpType == JT_LONGJUMP)
		{
			strJump = "Upjump";
		}
		else
		{
			Format(strJump, sizeof(strJump), "Up%s", g_strJumpTypeLwr[g_PlayerStates[client].JumpType]);
		}
	}
	else if(g_PlayerStates[client].fHeightDelta < HEIGHT_DELTA_MIN(g_PlayerStates[client].JumpType))
	{
		if(g_PlayerStates[client].JumpType == JT_LONGJUMP)
		{
			strJump = "Dropjump";
		}
		else
		{
			Format(strJump, sizeof(strJump), "Drop%s", g_strJumpTypeLwr[g_PlayerStates[client].JumpType]);
		}
	}
	else
	{
		strcopy(strJump, sizeof(strJump), g_strJumpType[g_PlayerStates[client].JumpType]);
	}
	
	char strJumpDir[16];
	strJumpDir = g_PlayerStates[client].JumpDir == JD_SIDEWAYS ? " SW" : g_PlayerStates[client].JumpDir == JD_BACKWARDS ? " BW" : "";
	
	//Get style settings
	char strJumpStyle[32] = "";
	if(g_PlayerStates[client].JumpType == JT_BHOP || g_PlayerStates[client].JumpType == JT_BHOPJUMP || g_PlayerStates[client].JumpType == JT_WEIRDJUMP)
	{
		Append(strJumpStyle, sizeof(strJumpStyle), g_PlayerStates[client].bStyleAuto ? " (Autohop)" : "");
	}
	
	Append(strJumpStyle, sizeof(strJumpStyle), g_PlayerStates[client].fStyleRunSpeed == 250.00 ? "" : " (%.0f Vel)", g_PlayerStates[client].fStyleRunSpeed);
	Append(strJumpStyle, sizeof(strJumpStyle), g_PlayerStates[client].fStyleAA == 100.00 ? "" : " (%.0faa)", g_PlayerStates[client].fStyleAA);
	
	////
	// Console
	////
	
	char buf[1024];
	buf[0] = 0;
	
	Append(buf, sizeof(buf), "\n");

	if(g_PlayerStates[client].fBlockDistance != -1.0)
	{
		Append(buf, sizeof(buf), "%.01f block%s",
		g_PlayerStates[client].fBlockDistance,
		g_PlayerStates[client].bFailedBlock ? " (failed)" : "");
	}
	
	if(g_PlayerStates[client].fBlockDistance != -1.0 && g_PlayerStates[client].vBlockNormal[0] != 0.0 && g_PlayerStates[client].vBlockNormal[1] != 0.0)
	{
		float f = 32.0 * (FloatAbs(g_PlayerStates[client].vBlockNormal[0]) + FloatAbs(g_PlayerStates[client].vBlockNormal[1]) - 1.0);
		float fAngle = FloatAbs(RadToDeg(ArcSine(g_PlayerStates[client].vBlockNormal[0])));
		fAngle = fAngle <= 45.0 ? fAngle : 90 - fAngle;
		
		Append(buf, sizeof(buf), " (%.1f rotated by %.1f)",
		g_PlayerStates[client].fBlockDistance + f,
		fAngle);
	}
	
	if(g_PlayerStates[client].fBlockDistance != -1.0)
	{
		float vJumpAngle[3];
		float vJumpOrig[3];
		float vBlockN[3];
		
		vJumpAngle = vCurOrigin;
		Array_Copy(g_PlayerStates[client].vJumpOrigin, vJumpOrig, 3);
		
		vBlockN[0] = g_PlayerStates[client].vBlockNormal[0];
		vBlockN[1] = g_PlayerStates[client].vBlockNormal[1];
		
		vJumpAngle[2] = 0.0;
		vJumpOrig[2] = 0.0;
		
		SubtractVectors(vJumpAngle, vJumpOrig, vJumpAngle);
		NormalizeVector(vJumpAngle, vJumpAngle);
		
		Append(buf, sizeof(buf), " - %.2f degrees off block",
		RadToDeg(ArcCosine(GetVectorDotProduct(vJumpAngle, vBlockN))));
	}
	
	Append(buf, sizeof(buf), "\n");
	
	Append(buf, sizeof(buf), "%s%s%s%s\nDistance: %.2f",
	strJump, strJumpDir, strJumpStyle,
	g_PlayerStates[client].JumpType == JT_LONGJUMP &&
	g_PlayerStates[client].fHeightDelta > HEIGHT_DELTA_MIN(g_PlayerStates[client].JumpType)
	&& g_PlayerStates[client].nTotalTicks > 77 ? " (extended)" : "",
	g_PlayerStates[client].fJumpDistance);
	
	Append(buf, sizeof(buf), "; prestrafe: %.2f",
	g_PlayerStates[client].fPrestrafe);
	
	if(g_PlayerStates[client].JumpType == JT_WEIRDJUMP)
	{
		Append(buf, sizeof(buf), "; drop prestrafe: %.2f",
		g_PlayerStates[client].fWJDropPre);
	}
	
	if(g_PlayerStates[client].fEdge != -1.0)
	{
		Append(buf, sizeof(buf), "; edge: %.2f",
		g_PlayerStates[client].fEdge);
	}
	
	if(g_PlayerStates[client].nTotalTicks == 78)
	{
		float vCurOrigin2[3];
		Array_Copy(g_PlayerStates[client].vLastOrigin, vCurOrigin2, 3);
		
		vCurOrigin2[2] = 0.0;
		
		float v[3];
		Array_Copy(g_PlayerStates[client].vJumpOrigin, v, 3);
		
		v[2] = 0.0;
		
		float ProjDist = GetVectorDistance(v, vCurOrigin2) + 32.0;
		
		Append(buf, sizeof(buf), "; projected real distance: %.2f", ProjDist);
	}
	
	Append(buf, sizeof(buf), "\nStrafes: %d; sync: %.2f%%; maxspeed (gain): %.2f (%.2f)",
	g_PlayerStates[client].nStrafes,
	g_PlayerStates[client].fSync,
	g_PlayerStates[client].fMaxSpeed,
	g_PlayerStates[client].fMaxSpeed - g_PlayerStates[client].fPrestrafe);
	
	Append(buf, sizeof(buf), "\nHeight diff: %s%.2f; jump height: %.2f; efficiency: %.4f; ticks: %d; degrees synced/degrees turned: %.2f/%.2f",
	g_PlayerStates[client].fHeightDelta >= 0.0 ? "+" : "",
	g_PlayerStates[client].fHeightDelta,
	g_PlayerStates[client].fJumpHeight,
	(g_PlayerStates[client].fJumpDistance - 32.0) / g_PlayerStates[client].fTrajectory,
	g_PlayerStates[client].nTotalTicks, 
	g_PlayerStates[client].fSyncedAngle, g_PlayerStates[client].fTotalAngle);
	
	for(int s = 1; s < sizeof(clientsToSend); s++)
	{
		if(clientsToSend[s])
		{
			PrintToConsole(s, buf);
			PrintToConsole(s, "--------------------------------");
			PrintToConsole(s, "#  Key Gain   Loss   Time   Sync");
		}
	}
	
	for(int i = 0; i < g_PlayerStates[client].nStrafes && i < MAX_STRAFES; i++)
	{
		char strStrafeKey[3];
		GetStrafeKey(strStrafeKey, g_PlayerStates[client].StrafeDir[i]);
		Format(buf, sizeof(buf), "%d  %s %6.2f %6.2f %6.2f %6.2f", i + 1,
		strStrafeKey,
		g_PlayerStates[client].fStrafeGain[i], g_PlayerStates[client].fStrafeLoss[i],
		float(g_PlayerStates[client].nStrafeTicks[i]) / g_PlayerStates[client].nTotalTicks * 100,
		float(g_PlayerStates[client].nStrafeTicksSynced[i]) / g_PlayerStates[client].nStrafeTicks[i] * 100);
		for(int s = 1; s < sizeof(clientsToSend); s++)
		{
			if(clientsToSend[s])
			{
				PrintToConsole(s, buf);
			}
		}
	}
	
	for(int s = 1; s < sizeof(clientsToSend); s++)
	{
		if(clientsToSend[s])
		{
			PrintToConsole(s, "	%s", g_PlayerStates[client].bDuck ? "Duck" : g_PlayerStates[client].bLastDuckState ? "Partial Duck" : "No Duck");
			PrintToConsole(s, ""); // Newline

			if(g_PlayerStates[client].JumpType != JT_BHOP && g_PlayerStates[client].IllegalJumpFlags)
			{
				PrintToConsole(s, "Illegal jump: ");
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_WORLD)
				{
					PrintToConsole(s, "Lateral world collision (hit wall/surf)");
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_BOOSTER)
				{
					PrintToConsole(s, "Booster");
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_GRAVITY)
				{
					PrintToConsole(s, "Gravity");
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_TELEPORT)
				{
					PrintToConsole(s, "Teleport");
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_LAGGEDMOVEMENTVALUE)
				{
					PrintToConsole(s, "Lagged movement value");
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_PRESTRAFE)
				{
					PrintToConsole(s, "Prestrafe > %.0f", g_fLJMaxPrestrafe + g_PlayerStates[client].fStyleRunSpeed);
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_NOCLIP)
				{
					PrintToConsole(s, "Noclip");
				}
				
				if(g_PlayerStates[client].IllegalJumpFlags & IJF_WATER)
				{
					PrintToConsole(s, "Entered water");
				}
			}
			
			PrintToConsole(s, ""); // Newline
		}
	}
	
	////
	// Panel
	////
	
	Handle hStatsPanel = CreatePanel();
	
	
	Format(buf, 128, "%s %.2f %s%.2f",
	g_strJumpTypeShort[g_PlayerStates[client].JumpType],
	g_PlayerStates[client].fJumpDistance,
	g_PlayerStates[client].fHeightDelta > 0.01 ? "+" : "",
	g_PlayerStates[client].fHeightDelta);
	
	SetPanelTitle(hStatsPanel, buf);
	
	// Print first 16 strafes to panel
	for(int i = 0; i < g_PlayerStates[client].nStrafes && i < 16; i++)
	{
		char strStrafeKey[3];
		GetStrafeKey(strStrafeKey, g_PlayerStates[client].StrafeDir[i]);
		DrawPanelTextF(hStatsPanel, "%d   %s  %.2f  %.2f  %.2f  %.2f",
		i + 1,
		strStrafeKey,
		g_PlayerStates[client].fStrafeGain[i], g_PlayerStates[client].fStrafeLoss[i],
		float(g_PlayerStates[client].nStrafeTicks[i]) / g_PlayerStates[client].nTotalTicks * 100,
		float(g_PlayerStates[client].nStrafeTicksSynced[i]) / g_PlayerStates[client].nStrafeTicks[i] * 100);
	}
	
	DrawPanelTextF(hStatsPanel, "	%.2f%%", g_PlayerStates[client].fSync);
	
	DrawPanelTextF(hStatsPanel, "	%.2f/%.2f", g_PlayerStates[client].fSyncedAngle, g_PlayerStates[client].fTotalAngle);
	
	DrawPanelTextF(hStatsPanel, "	%s", g_PlayerStates[client].bDuck ? "Duck" : g_PlayerStates[client].bLastDuckState ? "Partial Duck" : "No Duck");
	
	for(int s = 1; s < sizeof(clientsToSend); s++)
	{
		if(clientsToSend[s])
		{
			if(g_PlayerStates[s].bShowPanel)
			{
				if(g_PlayerStates[client].nBhops <= 1)
				{
					SendPanelToClient(hStatsPanel, s, EmptyPanelHandler, 5);
				}
				else
				{
					if(g_PlayerStates[s].bShowBhopStats)
					{
						SendPanelToClient(hStatsPanel, s, EmptyPanelHandler, 5);
					}
				}
			}
		}
	}
	
	CloseHandle(hStatsPanel);
	
	if(g_PlayerStates[client].IllegalJumpFlags != IJF_NONE)
	{
		return Plugin_Handled;
	}
	
	////
	// Print chat message
	////
	
	switch(g_PlayerStates[client].JumpType)
	{
		case JT_LONGJUMP, JT_COUNTJUMP:
		{
			for(int s = 1; s < sizeof(clientsToSend); s++)
			{
				if(clientsToSend[s])
				{
					if(!g_PlayerStates[s].bHideChat)
					{
						OutputJump(client, s, buf);
					}
					
					if(g_PlayerStates[s].bSound)
					{
						for(int i = 0; i < LJSOUND_NUM; i++)
						{
							if(g_PlayerStates[client].fJumpDistance >= g_fLJSound[i])
							{
								if(i == LJSOUND_NUM - 1 || g_PlayerStates[client].fJumpDistance < g_fLJSound[i + 1] || g_fLJSound[i + 1] == 0.0)
								{
									EmitSoundToClient(s, g_strLJSoundFile[i]);
								}
							}
							else
							{
								break;
							}
						}
					}
				}
			}
		}

		case JT_WEIRDJUMP, JT_BHOPJUMP, JT_LADDERJUMP, JT_BHOP:
		{
			for(int s = 1; s < sizeof(clientsToSend); s++)
			{
				if(clientsToSend[s])
				{
					if(!g_PlayerStates[s].bHideChat)
					{
						OutputJump(client, s, buf);
					}
				}
			}
		}
	}
	return Plugin_Handled;
}

public int EmptyPanelHandler(Handle hPanel, MenuAction ma, int Param1, any Param2)
{
	return Plugin_Handled;
}

public void OutputJump(int client, int client2, char buf[1024])
{
	char strOutput[512];
	
	char strName[64];
	GetClientName(client, strName, sizeof(strName));
	
	Format(strOutput, sizeof(strOutput), "%s%s %s%s%s%s%sed ",
	gS_ChatStrings.sVariable,
	strName,
	gS_ChatStrings.sText,
	(g_PlayerStates[client].JumpType != JT_BHOPJUMP && g_PlayerStates[client].JumpType != JT_BHOP) && (g_PlayerStates[client].fStyleRunSpeed > 250.00 || g_PlayerStates[client].fStyleAA > 100.00) ? "easy" : "",
	(g_PlayerStates[client].JumpType == JT_BHOPJUMP || g_PlayerStates[client].JumpType == JT_BHOP) ? g_PlayerStates[client].bStyleAuto ? "auto" : g_PlayerStates[client].bStamina ? "easy" : "" : "",
	g_strJumpTypeLwr[g_PlayerStates[client].JumpType], g_PlayerStates[client].JumpType == JT_BHOP ? "p" : "");
	
	Format(buf, sizeof(buf), "%s%.2f%s", gS_ChatStrings.sVariable, g_PlayerStates[client].fJumpDistance, gS_ChatStrings.sText);
	
	StrCat(strOutput, sizeof(strOutput), buf);
	
	if(g_PlayerStates[client].JumpDir != JD_FORWARDS)
	{
		if(g_PlayerStates[client].JumpDir == JD_SIDEWAYS)
		{
			StrCat(strOutput, sizeof(strOutput), " SW");
		}
		else if(g_PlayerStates[client].JumpDir == JD_BACKWARDS)
		{
			StrCat(strOutput, sizeof(strOutput), " BW");
		}
	}
	
	if(!g_PlayerStates[client].bDuck && !g_PlayerStates[client].bLastDuckState)
	{
		StrCat(strOutput, sizeof(strOutput), " no duck");
	}

	if(g_PlayerStates[client].fBlockDistance >= 230)
	{
		Format(buf, sizeof(buf), " @ %.1f block%s%s%s%s%s",
		g_PlayerStates[client].fBlockDistance,
		g_PlayerStates[client].bFailedBlock ? " (" : "",
		g_PlayerStates[client].bFailedBlock ? gS_ChatStrings.sWarning : "",
		g_PlayerStates[client].bFailedBlock ? "failed" : "",
		g_PlayerStates[client].bFailedBlock ? gS_ChatStrings.sText : "",
	  	g_PlayerStates[client].bFailedBlock ? ")" : "");
		
		StrCat(strOutput, sizeof(strOutput), buf);
	}
	
	StrCat(strOutput, sizeof(strOutput), "!");
	
	Format(buf, sizeof(buf), " (%s%.2f%s, %s%d%s @ %s%d%%%s, %s%d%s",
	gS_ChatStrings.sVariable, g_PlayerStates[client].fPrestrafe, gS_ChatStrings.sText, gS_ChatStrings.sVariable, g_PlayerStates[client].nStrafes, gS_ChatStrings.sText, gS_ChatStrings.sVariable, RoundFloat(g_PlayerStates[client].fSync), gS_ChatStrings.sText, gS_ChatStrings.sVariable, RoundFloat(g_PlayerStates[client].fMaxSpeed), gS_ChatStrings.sText);
		
	StrCat(strOutput, sizeof(strOutput), buf);
	
	if(g_PlayerStates[client].fBlockDistance != -1.0 && g_PlayerStates[client].fEdge != -1.0)
	{
		Format(buf, sizeof(buf), ", edge: %s%.2f%s", gS_ChatStrings.sVariable, g_PlayerStates[client].fEdge, gS_ChatStrings.sText);
		
		StrCat(strOutput, sizeof(strOutput), buf);
	}
	
	StrCat(strOutput, sizeof(strOutput), ")");
	
	Shavit_PrintToChat(client2, "%s", strOutput);
}


///////////////////////////////////
///////////////////////////////////
////////				   ////////
////////  Trace functions  ////////
////////				   ////////
///////////////////////////////////
///////////////////////////////////

#define RAYTRACE_Z_DELTA -0.1
#define GAP_TRACE_LENGTH 10000.0

public bool WorldFilter(int entity, int mask)
{
	if (entity >= 1 && entity <= MaxClients)
		return false;
	
	return true;
}

bool TracePlayer(float vEndPos[3], float vNormal[3], const float vTraceOrigin[3], const float vEndPoint[3], bool bCorrectError = true)
{
	float vMins[3] = {-16.0, -16.0, 0.0};
	float vMaxs[3] = {16.0, 16.0, 0.0};
	
	TR_TraceHullFilter(vTraceOrigin, vEndPoint, vMins, vMaxs, MASK_PLAYERSOLID, WorldFilter);
	
	if(!TR_DidHit()) // although tracehull does not ever seem to not hit (merely returning a hit at the end of the line), I'm keeping this here just in case, I guess
	{
		return false;
	}
	
	TR_GetEndPosition(vEndPos);
	TR_GetPlaneNormal(INVALID_HANDLE, vNormal);
	
	// correct slopes
	if(vNormal[2])
	{
		vNormal[2] = 0.0;
		NormalizeVector(vNormal, vNormal);
	}
	
	Adjust(vEndPos, vNormal);
	
	// dunno where this error comes from
	if(bCorrectError)
	{
		vEndPos[0] -= vNormal[0] * 0.03125;
		vEndPos[1] -= vNormal[1] * 0.03125;
	}
	
	float fDist = GetVectorDistance(vTraceOrigin, vEndPos);
	return fDist != 0.0 && fDist < GetVectorDistance(vTraceOrigin, vEndPoint);
}

// no function overloading... @__@
bool TracePlayer2(float vEndPos[3], const float vTraceOrigin[3], const float vEndPoint[3], bool bCorrectError = true)
{
	float vNormal[3];
	
	return TracePlayer(vEndPos, vNormal, vTraceOrigin, vEndPoint, bCorrectError);
}

bool IsLeft(const float vDir[3], const float vNormal[3])
{
	if(vNormal[1] > 0)
	{
		if(vDir[0] > vNormal[0])
		{
			return true;
		}
		else
		{
			return false;
		}
	}
	else
	{
		if(vDir[0] > vNormal[0])
		{
			return false;
		}
		else
		{
			return true;
		}
	}
}

// align with normal
public Action Align(float vOut[3], const float v1[3], const float v2[3], const float vNormal[3])
{
	// cardinal
	if(!vNormal[0] || !vNormal[1])
	{
		if(vNormal[0])
		{
			vOut[0] = v2[0];
			vOut[1] = v1[1];
		}
		else
		{
			vOut[0] = v1[0];
			vOut[1] = v2[1];
		}
		
		return Plugin_Handled;
	}
	
	// noncardinal
	// rotate to cardinal, perform the same operation, rotate the result back
	
	//		[ cos(t) -sin(t)  0 ]
	// Rz = [ sin(t)  cos(t)  0 ]
	//		[ 0		  0	   1 ]
	
	float vTo[3] = {1.0, 0.0};
	float fAngle = ArcCosine(GetVectorDotProduct(vNormal, vTo));
	float fRotatedOriginY;
	float vRotatedEndPos[2];
	
	if(IsLeft(vTo, vNormal))
	{
		fAngle = -fAngle;
	}
	
	fRotatedOriginY = v1[0] * Sine(fAngle) + v1[1] * Cosine(fAngle);
	
	vRotatedEndPos[0] = v2[0] * Cosine(fAngle) - v2[1] * Sine(fAngle);
	vRotatedEndPos[1] = fRotatedOriginY;
	
	fAngle = -fAngle;
	
	vOut[0] = vRotatedEndPos[0] * Cosine(fAngle) - vRotatedEndPos[1] * Sine(fAngle);
	vOut[1] = vRotatedEndPos[0] * Sine(fAngle)   + vRotatedEndPos[1] * Cosine(fAngle);
	return Plugin_Handled;
}

// Adjust collision hitbox center to periphery (the furthest point you could be from the edge as inferred by the normal)
public Action Adjust(float vOrigin[3], const float vNormal[3])
{
	// cardinal
	if(!vNormal[0] || !vNormal[1])
	{
		vOrigin[0] -= vNormal[0] * 16.0;
		vOrigin[1] -= vNormal[1] * 16.0;
		
		return Plugin_Handled;
	}
	
	// noncardinal
	// since the corner will always be the furthest point, set it to the corner of the normal's quadrant
	if(vNormal[0] > 0.0)
	{
		vOrigin[0] -= 16.0;
	}
	else
	{
		vOrigin[0] += 16.0;
	}
	
	if(vNormal[1] > 0.0)
	{
		vOrigin[1] -= 16.0;
	}
	else
	{
		vOrigin[1] += 16.0;
	}
	return Plugin_Handled;
}

public float GetEdge(int client)
{
	float vOrigin[3];
	float vTraceOrigin[3];
	float vDir[3];
	
	GetClientAbsOrigin(client, vOrigin);
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vDir);
	
	NormalizeVector(vDir, vDir);
	
	vTraceOrigin = vOrigin;
	vTraceOrigin[0] += vDir[0] * 64.0;
	vTraceOrigin[1] += vDir[1] * 64.0;
	vTraceOrigin[2] += RAYTRACE_Z_DELTA;
	
	float vEndPoint[3];
	vEndPoint = vOrigin;
	vEndPoint[0] -= vDir[0] * 16.0 * 1.414214;
	vEndPoint[1] -= vDir[1] * 16.0 * 1.414214;
	vEndPoint[2] += RAYTRACE_Z_DELTA;
	
	float vEndPos[3];
	float vNormal[3];
	if(!TracePlayer(vEndPos, vNormal, vTraceOrigin, vEndPoint))
	{
		return -1.0;
	}
	
	Adjust(vOrigin, vNormal);
	
	Align(vEndPos, vOrigin, vEndPos, vNormal);
	
	// Correct Z -- the trace ray is a bit lower
	vEndPos[2] = vOrigin[2];
	
	return GetVectorDistance(vEndPos, vOrigin);
}

public float GetBlockDistance(int client)
{
	float vOrigin[3];
	float vTraceOrigin[3];
	float vDir[3];
	float vEndPoint[3];
	GetClientAbsOrigin(client, vOrigin);
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vDir);
	
	NormalizeVector(vDir, vDir);
	
	vTraceOrigin = vOrigin;
	vTraceOrigin[0] += vDir[0] * 64.0;
	vTraceOrigin[1] += vDir[1] * 64.0;
	vTraceOrigin[2] += RAYTRACE_Z_DELTA;
	
	vEndPoint = vOrigin;
	vEndPoint[0] -= vDir[0] * 16.0 * 1.414214;
	vEndPoint[1] -= vDir[1] * 16.0 * 1.414214;
	vEndPoint[2] += RAYTRACE_Z_DELTA;
	
	float vBlockStart[3];
	float vNormal[3];
	if(!TracePlayer(vBlockStart, vNormal, vTraceOrigin, vEndPoint))
	{
		return -1.0;
	}
	
	float vBlockEnd[3];
	
	Array_Copy(vNormal, g_PlayerStates[client].vBlockNormal, 2);
	
	vEndPoint = vBlockStart;
	vEndPoint[0] += vNormal[0] * 300.0;
	vEndPoint[1] += vNormal[1] * 300.0;
	
	if(TracePlayer2(vBlockEnd, vBlockStart, vEndPoint))
	{
		Array_Copy(vBlockEnd, g_PlayerStates[client].vBlockEndPos, 3);
		
		Align(vBlockEnd, vBlockStart, vBlockEnd, vNormal);
		
		if(vNormal[0] == 0.0 || vNormal[1] == 0.0)
		{
			return GetVectorDistance(vBlockStart, vBlockEnd);
		}
		else
		{
			return GetVectorDistance(vBlockStart, vBlockEnd) - 32.0 * (FloatAbs(vNormal[0]) + FloatAbs(vNormal[1]) - 1.0);
		}
	}
	else
	{
		// Trace the other direction
		
		// rotate normal da way opposite da direction
		bool bLeft = IsLeft(vDir, vNormal);
		
		vDir = vNormal;
		
		float fTempSwap = vDir[0];
		
		vDir[0] = vDir[1];
		vDir[1] = fTempSwap;
		
		if(bLeft)
		{
			vDir[0] = -vDir[0];
		}
		else
		{
			vDir[1] = -vDir[1];
		}
		
		vTraceOrigin = vOrigin;
		vTraceOrigin[0] += vDir[0] * 48.0;
		vTraceOrigin[1] += vDir[1] * 48.0;
		vTraceOrigin[2] += RAYTRACE_Z_DELTA;
		
		vEndPoint = vTraceOrigin;
		vEndPoint[0] += vNormal[0] * 300.0;
		vEndPoint[1] += vNormal[1] * 300.0;
		
		if(!TracePlayer2(vBlockEnd, vTraceOrigin, vEndPoint))
		{
			return -1.0;
		}
		
		Array_Copy(vBlockEnd, g_PlayerStates[client].vBlockEndPos, 3);
		
		// adjust vBlockStart -- the second trace was on a different axis
		Align(vBlockStart, vBlockStart, vBlockEnd, vNormal);
		
		if(vNormal[0] == 0.0 || vNormal[1] == 0.0)
		{
			return GetVectorDistance(vBlockStart, vBlockEnd);
		}
		else
		{
			return GetVectorDistance(vBlockStart, vBlockEnd) - 32.0 * (FloatAbs(vNormal[0]) + FloatAbs(vNormal[1]) - 1.0);
		}
	}
}

// generic utility functions

stock float GetSpeed(int client)
{
	float vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	vVelocity[2] = 0.0;
	
	return GetVectorLength(vVelocity); 
}

stock float GetVSpeed(const float v[3])
{
	float vVelocity[3];
	vVelocity = v;
	vVelocity[2] = 0.0;
	
	return GetVectorLength(vVelocity);
}

stock void DrawPanelTextF(Handle hPanel, const char[] strFormat, any ...)
{
	char buf[512];
	
	VFormat(buf, sizeof(buf), strFormat, 3);
	
	DrawPanelText(hPanel, buf);
}

stock void Append(char[] sOutput, int maxlen, const char[] sFormat, any ...)
{
	char buf[1024];
	
	VFormat(buf, sizeof(buf), sFormat, 4);
	
	StrCat(sOutput, maxlen, buf);
}

// undefined for negative numbers
stock float fmod(float a, float b)
{
	while(a > b)
		a -= b;
	
	return a;
}

stock float round(float a, int b, float Base = 10.0)
{
	float f = Pow(Base, float(b));
	return RoundFloat(a * f) / f;
}

//from smlib
stock void Array_Copy(const any[] array, any[] newArray, int size)
{
	for (int i=0; i < size; i++) {
		newArray[i] = array[i];
	}
}


#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <updater>
#include "advertisements/chatcolors.sp"
#include "advertisements/topcolors.sp"

#pragma newdecls required
#pragma semicolon 1

#define PL_VERSION	"2.0.4"
#define UPDATE_URL	"http://ErikMinekus.github.io/sm-advertisements/update.txt"

public Plugin myinfo =
{
    name        = "Advertisements",
    author      = "Tsunami",
    description = "Display advertisements",
    version     = PL_VERSION,
    url         = "http://www.tsunami-productions.nl"
};


/**
 * Globals
 */
KeyValues g_hAdvertisements;
ConVar g_hEnabled;
ConVar g_hFile;
ConVar g_hInterval;
Handle g_hTimer;


/**
 * Plugin Forwards
 */
public void OnPluginStart()
{
    CreateConVar("sm_advertisements_version", PL_VERSION, "Display advertisements", FCVAR_NOTIFY);
    g_hEnabled  = CreateConVar("sm_advertisements_enabled",  "1",                  "Enable/disable displaying advertisements.");
    g_hFile     = CreateConVar("sm_advertisements_file",     "advertisements.txt", "File to read the advertisements from.");
    g_hInterval = CreateConVar("sm_advertisements_interval", "30",                 "Amount of seconds between advertisements.");

    g_hFile.AddChangeHook(ConVarChange_File);
    g_hInterval.AddChangeHook(ConVarChange_Interval);

    RegServerCmd("sm_advertisements_reload", Command_ReloadAds, "Reload the advertisements");

    AddChatColors();
    AddTopColors();

    if (LibraryExists("updater")) {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnConfigsExecuted()
{
    ParseAds();
    RestartTimer();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater")) {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void ConVarChange_File(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ParseAds();
}

public void ConVarChange_Interval(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RestartTimer();
}


/**
 * Commands
 */
public Action Command_ReloadAds(int args)
{
    ParseAds();
    return Plugin_Handled;
}


/**
 * Menu Handlers
 */
public int Handler_DoNothing(Menu menu, MenuAction action, int param1, int param2) {}


/**
 * Timers
 */
public Action Timer_DisplayAd(Handle timer)
{
    if (!g_hEnabled.BoolValue) {
        return;
    }

    char sCenter[1024], sChat[1024], sHint[1024], sMenu[1024], sTop[1024], sFlags[22];
    g_hAdvertisements.GetString("center", sCenter, sizeof(sCenter));
    g_hAdvertisements.GetString("chat",   sChat,   sizeof(sChat));
    g_hAdvertisements.GetString("hint",   sHint,   sizeof(sHint));
    g_hAdvertisements.GetString("menu",   sMenu,   sizeof(sMenu));
    g_hAdvertisements.GetString("top",    sTop,    sizeof(sTop));
    g_hAdvertisements.GetString("flags",  sFlags,  sizeof(sFlags), "none");
    int iFlags   = ReadFlagString(sFlags);
    bool bAdmins = StrEqual(sFlags, ""),
         bFlags  = !StrEqual(sFlags, "none");
    char message[1024];

    if (sCenter[0]) {
        ProcessVariables(sCenter, message, sizeof(message));

        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i, bAdmins, bFlags, iFlags)) {
                PrintCenterText(i, "%s", message);

                DataPack hCenterAd;
                CreateDataTimer(1.0, Timer_CenterAd, hCenterAd, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
                hCenterAd.WriteCell(i);
                hCenterAd.WriteString(message);
            }
        }
    }
    if (sHint[0]) {
        ProcessVariables(sHint, message, sizeof(message));

        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i, bAdmins, bFlags, iFlags)) {
                PrintHintText(i, "%s", message);
            }
        }
    }
    if (sMenu[0]) {
        ProcessVariables(sMenu, message, sizeof(message));

        Panel hPl = new Panel();
        hPl.DrawText(message);
        hPl.CurrentKey = 10;

        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i, bAdmins, bFlags, iFlags)) {
                hPl.Send(i, Handler_DoNothing, 10);
            }
        }

        delete hPl;
    }
    if (sChat[0]) {
        bool bTeamColor = StrContains(sChat, "{teamcolor}", false) != -1;

        char buffer[1024];
        ProcessChatColors(sChat, buffer, sizeof(buffer));
        ProcessVariables(buffer, message, sizeof(message));

        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i, bAdmins, bFlags, iFlags)) {
                if (bTeamColor) {
                    SayText2(i, message);
                } else {
                    PrintToChat(i, "%s", message);
                }
            }
        }
    }
    if (sTop[0]) {
        int iStart    = 0,
            aColor[4] = {255, 255, 255, 255};

        ParseTopColor(sTop, iStart, aColor);
        ProcessVariables(sTop[iStart], message, sizeof(message));

        KeyValues hKv = new KeyValues("Stuff", "title", message);
        hKv.SetColor4("color", aColor);
        hKv.SetNum("level",    1);
        hKv.SetNum("time",     10);

        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i, bAdmins, bFlags, iFlags)) {
                CreateDialog(i, hKv, DialogType_Msg);
            }
        }

        delete hKv;
    }

    if (!g_hAdvertisements.GotoNextKey()) {
        g_hAdvertisements.Rewind();
        g_hAdvertisements.GotoFirstSubKey();
    }
}

public Action Timer_CenterAd(Handle timer, DataPack pack)
{
    char message[1024];
    static int iCount = 0;

    pack.Reset();
    int iClient = pack.ReadCell();
    pack.ReadString(message, sizeof(message));

    if (!IsClientInGame(iClient) || ++iCount >= 5) {
        iCount = 0;
        return Plugin_Stop;
    }

    PrintCenterText(iClient, "%s", message);
    return Plugin_Continue;
}


/**
 * Stocks
 */
bool IsValidClient(int iClient, bool bAdmins, bool bFlags, int iFlags)
{
    return IsClientInGame(iClient) && !IsFakeClient(iClient)
        && ((!bAdmins && !(bFlags && CheckCommandAccess(iClient, "Advertisements", iFlags)))
            || (bAdmins && CheckCommandAccess(iClient, "Advertisements", ADMFLAG_GENERIC)));
}

void ParseAds()
{
    delete g_hAdvertisements;
    g_hAdvertisements = new KeyValues("Advertisements");

    char sFile[64], sPath[PLATFORM_MAX_PATH];
    g_hFile.GetString(sFile, sizeof(sFile));
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);

    if (!FileExists(sPath)) {
        SetFailState("File Not Found: %s", sPath);
    }

    g_hAdvertisements.SetEscapeSequences(true);
    g_hAdvertisements.ImportFromFile(sPath);
    g_hAdvertisements.GotoFirstSubKey();
}

void ProcessVariables(const char[] message, char[] buffer, int maxlength)
{
    char name[64], value[256];
    int buf_idx, i, name_len;
    ConVar hConVar;

    while (message[i]) {
        if (message[i] != '{' || (name_len = FindCharInString(message[i + 1], '}')) == -1) {
            buffer[buf_idx++] = message[i++];
            continue;
        }

        strcopy(name, name_len + 1, message[i + 1]);

        if (StrEqual(name, "currentmap", false)) {
            GetCurrentMap(value, sizeof(value));
            buf_idx += strcopy(buffer[buf_idx], maxlength - buf_idx, value);
        }
        else if (StrEqual(name, "date", false)) {
            FormatTime(value, sizeof(value), "%m/%d/%Y");
            buf_idx += strcopy(buffer[buf_idx], maxlength - buf_idx, value);
        }
        else if (StrEqual(name, "time", false)) {
            FormatTime(value, sizeof(value), "%I:%M:%S%p");
            buf_idx += strcopy(buffer[buf_idx], maxlength - buf_idx, value);
        }
        else if (StrEqual(name, "time24", false)) {
            FormatTime(value, sizeof(value), "%H:%M:%S");
            buf_idx += strcopy(buffer[buf_idx], maxlength - buf_idx, value);
        }
        else if (StrEqual(name, "timeleft", false)) {
            int mins, secs, timeleft;
            if (GetMapTimeLeft(timeleft) && timeleft > 0) {
                mins = timeleft / 60;
                secs = timeleft % 60;
            }

            buf_idx += FormatEx(buffer[buf_idx], maxlength - buf_idx, "%d:%02d", mins, secs);
        }
        else if ((hConVar = FindConVar(name))) {
            hConVar.GetString(value, sizeof(value));
            buf_idx += strcopy(buffer[buf_idx], maxlength - buf_idx, value);
        }
        else {
            buf_idx += FormatEx(buffer[buf_idx], maxlength - buf_idx, "{%s}", name);
        }

        i += name_len + 2;
    }

    buffer[buf_idx] = '\0';
}

void RestartTimer()
{
    delete g_hTimer;
    g_hTimer = CreateTimer(float(g_hInterval.IntValue), Timer_DisplayAd, _, TIMER_REPEAT);
}

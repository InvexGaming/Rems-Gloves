#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

// Plugin Informaiton
#define VERSION "1.08"
#define SERVER_LOCK_IP "45.121.211.57"

public Plugin myinfo =
{
  name = "CS:GO VIP Plugin (rg)",
  author = "Invex | Byte",
  description = "Special actions for VIP players.",
  version = VERSION,
  url = "http://www.invexgaming.com.au"
};

//Convars
ConVar cvar_antifloodtime = null;

//Definitions
#define CHAT_TAG_PREFIX "[{green}RG{default}] "
#define MAX_GLOVES 50
#define RANDOM_GLOVES -1
#define DEFAULT_GLOVES 0

static char szGloveSleeves[][] = 
{
	"models/weapons/v_models/arms/anarchist/v_sleeve_anarchist.mdl", 
	"models/weapons/v_models/arms/balkan/v_sleeve_balkan.mdl", 
	"models/weapons/v_models/arms/fbi/v_sleeve_fbi.mdl", 
	"models/weapons/v_models/arms/gign/v_sleeve_gign.mdl", 
	"models/weapons/v_models/arms/gsg9/v_sleeve_gsg9.mdl", 
	"models/weapons/v_models/arms/idf/v_sleeve_idf.mdl", 
	"models/weapons/v_models/arms/pirate/v_pirate_watch.mdl", 
	"models/weapons/v_models/arms/professional/v_sleeve_professional.mdl", 
	"models/weapons/v_models/arms/sas/v_sleeve_sas.mdl", 
	"models/weapons/v_models/arms/separatist/v_sleeve_separatist.mdl", 
	"models/weapons/v_models/arms/st6/v_sleeve_st6.mdl", 
	"models/weapons/v_models/arms/swat/v_sleeve_swat.mdl"
};

static char szNormalSleeves[][] = 
{
	"models/weapons/t_arms_anarchist.mdl", 
	"models/weapons/t_arms_pirate.mdl", 
	"models/weapons/t_arms_professional.mdl", 
	"models/weapons/t_arms_separatist.mdl", 
	"models/weapons/t_arms_balkan.mdl", 
	"models/weapons/t_arms_leet.mdl", 
	"models/weapons/t_arms_phoenix.mdl", 
	"models/weapons/ct_arms_gign.mdl", 
	"models/weapons/ct_arms_gsg9.mdl", 
	"models/weapons/ct_arms_st6.mdl", 
	"models/weapons/ct_arms_fbi.mdl", 
	"models/weapons/ct_arms_idf.mdl", 
	"models/weapons/ct_arms_sas.mdl", 
	"models/weapons/ct_arms_swat.mdl"
};

enum Listing
{
  String:skinName[64],
  String:category[64],
  String:worldModel[PLATFORM_MAX_PATH],
  ItemDefinitionIndex,
  FallbackPaintKit,
  Float:wear
}

int g_gloves[MAX_GLOVES][Listing];
int g_gloveCount = 1; //starts from 1, not 0
int g_ClientGlove[MAXPLAYERS+1] = {0, ...};
int g_ClientGloveEntities[MAXPLAYERS+1] = {-1, ...};
bool g_canUse[MAXPLAYERS+1] = {true, ...}; //for anti-flood

//Flags
AdminFlag rgFlag = Admin_Custom3;

//Menu
Menu glovesMenu = null;
ArrayList categories;
Menu subMenus[MAX_GLOVES];

//Cookies
Handle c_GloveIndex = null;

//SDKCall
Handle g_hGiveWearableCall = null;

public void OnPluginStart()
{
  //Anti-share
  if (strcmp(SERVER_LOCK_IP, "") != 0) {
    char m_szIP[64];
    int m_unIP = GetConVarInt(FindConVar("hostip"));
    Format(m_szIP, sizeof(m_szIP), "%d.%d.%d.%d", (m_unIP >> 24) & 0x000000FF, (m_unIP >> 16) & 0x000000FF, (m_unIP >> 8) & 0x000000FF, m_unIP & 0x000000FF);

    if (strcmp(SERVER_LOCK_IP, m_szIP) != 0)
      SetFailState("Nope.");
  }
  
  //Store preferences in clienprefs
  c_GloveIndex = RegClientCookie("rg_gloves_preference", "", CookieAccess_Private);
  
  //Translations
  LoadTranslations("rg.phrases");
  
  //Convars
  cvar_antifloodtime = CreateConVar("sm_rg_antifloodtime", "0.75", "Speed at which clients can use the plugin (def. 2.0)");
  
  //Prepare SDK call values
  Handle hConfig = LoadGameConfigFile("wearables.games");
  int iEquipOffset = GameConfGetOffset(hConfig, "EquipWearable");
  StartPrepSDKCall(SDKCall_Player);
  PrepSDKCall_SetVirtual(iEquipOffset);
  PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
  g_hGiveWearableCall = EndPrepSDKCall();
  
  //Init array list
  categories = CreateArray(MAX_GLOVES);
  
  //Configuration
  ReadGloveConfigFile();
  
  //Process players and set them up
  for (int client = 1; client <= MaxClients; ++client) {
    if (!IsClientInGame(client))
      continue;
    
    OnClientPutInServer(client);
  }
  
  HookEvent("player_spawn", Event_PlayerSpawn);
  
  //Create config file
  AutoExecConfig(true, "rg");
}

public void OnMapStart()
{
  //Precache arms models
	int iGlovesSleeves = sizeof(szGloveSleeves);
	for (int i = 0; i < iGlovesSleeves; i++) {
		PrecacheModel(szGloveSleeves[i], true);
	}
	
	int iNormalSleeves = sizeof(szNormalSleeves);
	for (int i = 0; i < iNormalSleeves; i++) {
		PrecacheModel(szNormalSleeves[i], true);
	}
	
	PrecacheModel("models/weapons/v_models/arms/bare/v_bare_hands.mdl", true);
}

public void OnPluginEnd()
{
  for(int i = 1; i <= MaxClients; ++i) {
    if (IsClientConnected(i) && IsClientInGame(i)) {
      //Cookie saving
      OnClientDisconnect(i);
      
      //Removing gloves
      if (IsPlayerAlive(i))
        RemoveClientGloves(i);
    }
  }
}

public void OnClientPutInServer(int client)
{
  g_canUse[client] = true;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));
  
  //Get VIP status
  int isVIP = CheckCommandAccess(client, "", FlagToBit(rgFlag));
  
  if (!isVIP) {
    return Plugin_Continue;
  }
  
  //Give player gloves post spawn
  if (g_ClientGlove[client] != 0)
    GiveClientGloves(client, g_ClientGlove[client]);
  
  return Plugin_Continue;
}

//Monitor chat to capture commands
public Action OnClientSayCommand(int client, const char[] command_t, const char[] sArgs)
{
  char command[32];
  SplitString(sArgs, " ", command, sizeof(command));
  
  //If no spaces then user is calling command with no function
  if (strcmp(command, "") == 0)
    strcopy(command, sizeof(command), sArgs);
  
  //Check if command starts with following strings
  if( StrEqual(command, "!gloves", false) ||
      StrEqual(command, "!glove", false) ||
      StrEqual(command, "!rg", false) ||
      StrEqual(command, "/gloves", false) ||
      StrEqual(command, "/glove", false) ||
      StrEqual(command, "/rg", false)
    )
  {
    //Get VIP status
    int isVIP = CheckCommandAccess(client, "", FlagToBit(rgFlag));
    
    //Only VIPS can use this plugin unless you are setting the default skin
    if (!isVIP) {
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Must be VIP");
      return Plugin_Handled;
    }
    
    //Otherwise continue normally
    ShowGlovesMenu(client);
    
    //Don't print this to chat
    return Plugin_Handled;
  }
  
  return Plugin_Continue;
}

public void ShowGlovesMenu(int client)
{
  if (!IsClientInGame(client))
    return;
    
  if (!(1 <= client <= MaxClients))
    return;
    
  if (!IsPlayerAlive(client)) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Must Be Alive");
    return;
  }
  
  DisplayMenu(glovesMenu, client, MENU_TIME_FOREVER);
}

public int glovesMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
  //Get menu info
  char info[64];
  char display[64];
  GetMenuItem(menu, itemNum, info, sizeof(info), _, display, sizeof(display));

  if (action == MenuAction_DrawItem) {
    if (g_ClientGlove[client] == DEFAULT_GLOVES && StrEqual(display, "Default Gloves"))
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_ClientGlove[client] == DEFAULT_GLOVES && StrEqual(display, "Default Gloves")) {
      //Change selected text
      char equipedText[64];
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    //Show menu based on category name (provided as info)
    int index = categories.FindString(info);
    if (index != -1) {
      DisplayMenu(subMenus[index], client, MENU_TIME_FOREVER);
    }
    else if (itemNum == 0 || itemNum == 1) {
      if (!g_canUse[client]) {
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Anti Flood Message");
        DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
        return 0;
      }
    
      //Subtract 1 as 0 is default and -1 is random
      int item = GiveClientGloves(client, itemNum - 1);
      
      if (item != -1) {
        //Print Chat Option
        char fullGloveName[64];
        Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_gloves[item][category], g_gloves[item][skinName]);
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove", fullGloveName);
      }
      
      //Set anti flood timer
      g_canUse[client] = false;
      CreateTimer(GetConVarFloat(cvar_antifloodtime), Timer_ReEnableUsage, client);
      
      DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
    }
    else {
      DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
    }
  }
  
  return 0;
}

public int glovesSubMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
  //Get menu info
  char info[64];
  char display[64];
  GetMenuItem(menu, itemNum, info, sizeof(info), _, display, sizeof(display));
  int selectedIndex = StringToInt(info);
  
  if (action == MenuAction_DrawItem) {
    if (g_ClientGlove[client] == selectedIndex)
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_ClientGlove[client] == selectedIndex) {
      //Change selected text
      char equipedText[64];
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    if (!g_canUse[client]) {
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Anti Flood Message");
      DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
      return 0;
    }
  
    //Give client selected gloves
    GiveClientGloves(client, selectedIndex);
    
    //Print Chat Option
    char fullGloveName[64];
    Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_gloves[selectedIndex][category], g_gloves[selectedIndex][skinName]);
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove", fullGloveName);
    
    //Set anti flood timer
    g_canUse[client] = false;
    CreateTimer(GetConVarFloat(cvar_antifloodtime), Timer_ReEnableUsage, client);
    
    DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
  }
  else if (action == MenuAction_Cancel)
  {
    if (itemNum == MenuCancel_ExitBack) {
      //Goto main menu
      DisplayMenuAtItem(glovesMenu, client, 0, 0);
    }
  }
  
  return 0;
}

//Re-enable ws for particular client
public Action Timer_ReEnableUsage(Handle timer, int client)
{
  g_canUse[client] = true;
}

void RemoveClientGloves(int client)
{
  if (IsClientConnected(client) && IsClientInGame(client) && IsPlayerAlive(client)) {
    if (g_ClientGloveEntities[client] != INVALID_ENT_REFERENCE) {
      int ent = EntRefToEntIndex(g_ClientGloveEntities[client]);
    
      if (IsValidEntity(ent) && ent > 0) {
        AcceptEntityInput(ent, "Kill");
        g_ClientGloveEntities[client] = INVALID_ENT_REFERENCE;
      }
    }
  }
}

//Returns index i (converting randomised indexes first)
int GiveClientGloves(int client, int i)
{
  if(!IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
    return -1;
    
  //Invalid index
  if (i < -1 || i > g_gloveCount - 1)
    return -1;

  //For randomised index
  //Keep picking random number until a different one is found
  if(i == -1) {
    while (i == g_ClientGlove[client] || i == -1)
      i = GetRandomInt(1, g_gloveCount - 1);
  }
  
  g_ClientGlove[client] = i;
  
  //Remove current gloves
  RemoveClientGloves(client);
  
  //Update the clients sleeves to use a gloves supporting arms model
  UpdateClientSleeves(client);
  
  //If non-default gloves
  if (i != 0) {
    int ent = CreateEntityByName("wearable_item");
    g_ClientGloveEntities[client] = EntIndexToEntRef(ent);
    
    //Process non-default gloves
    if (ent != -1) {
      SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", client);
      SetEntityModel(ent, g_gloves[i][worldModel]);
      SetEntProp(ent, Prop_Send, "m_nModelIndex", PrecacheModel(g_gloves[i][worldModel]));
      SetEntProp(ent, Prop_Send, "m_iTeamNum", GetClientTeam(client));
      SetEntProp(client, Prop_Send, "m_nBody", 1);
      
      //Set skin properties
      SetEntProp(ent, Prop_Send, "m_bInitialized", 1); //removed wearable error message
      SetEntProp(ent, Prop_Send,  "m_iAccountID", GetSteamAccountID(client));
      SetEntProp(ent, Prop_Send, "m_iItemIDLow", 2048);
      SetEntProp(ent, Prop_Send, "m_iEntityQuality", 4);
      SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", g_gloves[i][ItemDefinitionIndex]);
      SetEntProp(ent, Prop_Send,  "m_nFallbackPaintKit", g_gloves[i][FallbackPaintKit]);
      SetEntPropFloat(ent, Prop_Send, "m_flFallbackWear", g_gloves[i][wear]);
      
      SetVariantString("!activator");
      ActivateEntity(ent);
     
      //Call SDK function to give wearable
      SDKCall(g_hGiveWearableCall, client, ent);
    }
  } else {
    //Reset this for default gloves
    SetEntProp(client, Prop_Send, "m_nBody", 0);
  }
  
  //Send a client refresh to all players
  //This will refresh viewmodel for them updating gloves
  //Also avoids 'glove stack' bug if gloves changed mid round
  for (int k = 1; k < MaxClients; ++k) {
    if (IsClientConnected(k) && IsClientInGame(k) && !IsFakeClient(k)) {
      ForceClientRefresh(client, k);
    }
  }
  
  return i;
}

public void OnClientCookiesCached(int client)
{
  char index[4];
  GetClientCookie(client, c_GloveIndex, index, sizeof(index));
  g_ClientGlove[client] = StringToInt(index);
}

//Clean up when client disconnects
public void OnClientDisconnect(int client)
{ 
  if (AreClientCookiesCached(client)) {
    char index[4];
    IntToString(g_ClientGlove[client], index, sizeof(index));
    SetClientCookie(client, c_GloveIndex, index);
  }
  
  g_ClientGlove[client] = 0;
  g_ClientGloveEntities[client] = INVALID_ENT_REFERENCE;
}

//Read glove config file
void ReadGloveConfigFile()
{
  char sPath[PLATFORM_MAX_PATH];
  Format(sPath, sizeof(sPath), "configs/csgo_gloves.cfg");
  BuildPath(Path_SM, sPath, sizeof(sPath), sPath);
  
  if (!FileExists(sPath))
    return;
  
  KeyValues kv = CreateKeyValues("Gloves");
  g_gloveCount = 1;
  
  if (!kv.ImportFromFile(sPath))
    return;
  
  if(kv.GotoFirstSubKey(true))
  {
    do
    {
      //Get glove family information
      char gloveCategory[64];
      kv.GetSectionName(gloveCategory, sizeof(gloveCategory));      
      int m_iItemDefinitionIndex = kv.GetNum("ItemDefinitionIndex");
      char model_world[PLATFORM_MAX_PATH];
      kv.GetString("model_world", model_world, sizeof(model_world));
      
      //Iterate through skins
      if(kv.JumpToKey("skins", false)) {
        if(kv.GotoFirstSubKey(true)) {
          do {
            Format(g_gloves[g_gloveCount][category], 64, gloveCategory);
            g_gloves[g_gloveCount][ItemDefinitionIndex] = m_iItemDefinitionIndex;
            Format(g_gloves[g_gloveCount][worldModel], PLATFORM_MAX_PATH, model_world);
            kv.GetSectionName(g_gloves[g_gloveCount][skinName], 64);
            g_gloves[g_gloveCount][FallbackPaintKit] = kv.GetNum("FallbackPaintKit");
            g_gloves[g_gloveCount][wear] = kv.GetFloat("wear", 0.0001);
          
            ++g_gloveCount;
          } while (kv.GotoNextKey(true));
          kv.GoBack();
        }
        kv.GoBack();
      }
    } while(kv.GotoNextKey(true));
    
    kv.GoBack();
  }
  
  delete kv;
  
  //Create (or update) the menu
  if (glovesMenu != null) {
    CloseHandle(glovesMenu);
    glovesMenu = null;
  }
  
  glovesMenu = CreateMenu(glovesMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
  SetMenuTitle(glovesMenu, "%t", "Menu title");
  
  char numStrBuffer[3];
  IntToString(RANDOM_GLOVES, numStrBuffer, sizeof(numStrBuffer));
  AddMenuItem(glovesMenu, numStrBuffer, "Random Gloves");
  IntToString(DEFAULT_GLOVES, numStrBuffer, sizeof(numStrBuffer));
  AddMenuItem(glovesMenu, numStrBuffer, "Default Gloves");
  Format(g_gloves[DEFAULT_GLOVES][skinName], 64, "Default");
  Format(g_gloves[DEFAULT_GLOVES][category], 64, "CSGO");
  
  //Create submenus
  ClearArray(categories);
  
  char item[4];
  char categoryName[64];
  for (int i = 1; i < g_gloveCount; ++i) {
    int index = categories.FindString(g_gloves[i][category]);
    if (index == -1) {
      //Push
      index = categories.PushString(g_gloves[i][category]);
      
      //Add menu option
      Format(categoryName, sizeof(categoryName), "%s", g_gloves[i][category]);
      AddMenuItem(glovesMenu, categoryName, g_gloves[i][category]);
      
      //Create Menu
      subMenus[index] = CreateMenu(glovesSubMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
      SetMenuExitBackButton(subMenus[index], true);
      SetMenuTitle(subMenus[index], "%s Gloves:", g_gloves[i][category]);
    }
    
    //Add item to submenu
    Format(item, sizeof(item), "%i", i);
    AddMenuItem(subMenus[index], item, g_gloves[i][skinName]);
  }
  
  SetMenuExitButton(glovesMenu, true);
}

//Force client to refresh models etc by faking a player spawn event
stock void ForceClientRefresh(int playerToRefresh, int fireTo)
{
  Event event = CreateEvent("player_spawn", true);

  if (event != null) {
    event.SetInt("userid", GetClientUserId(playerToRefresh));
    event.FireToClient(fireTo);
    event.Cancel();
  }
}

//Update a clients gloves based on which default arm model they are using
stock void UpdateClientSleeves(int client)
{
  char m_szArmsModel[PLATFORM_MAX_PATH];
  GetEntPropString(client, Prop_Send, "m_szArmsModel", m_szArmsModel, sizeof(m_szArmsModel));
  
  bool bUsingDefaultGloves = (g_ClientGlove[client] == DEFAULT_GLOVES) ? true : false;
  
  //Search for a normal sleves match
  int iNormalSleeves = sizeof(szGloveSleeves);
  for (int i = 0; i < iNormalSleeves; ++i) {
    if (StrEqual(m_szArmsModel, szNormalSleeves[i], false)) {
      //If were not using default gloves, we need to update to the glove sleeve version
      if (!bUsingDefaultGloves) {
        SetEntPropString(client, Prop_Send, "m_szArmsModel", szGloveSleeves[i]);
      }
      
      return;
    }
  }
  
  //Search for a gloves sleves match
  int iGlovesSleeves = sizeof(szGloveSleeves);
  for (int i = 0; i < iGlovesSleeves; ++i) {
    if (StrEqual(m_szArmsModel, szGloveSleeves[i], false)) {
      //If were using default gloves, we need to update to the normal sleeve version
      if (bUsingDefaultGloves) {
        SetEntPropString(client, Prop_Send, "m_szArmsModel", szNormalSleeves[i]);
      }
      
      return;
    }
  }
}
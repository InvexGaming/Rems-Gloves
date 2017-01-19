#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

// Plugin Informaiton  
#define VERSION "1.04"
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
ConVar cvar_show_thirdperson = null;
ConVar cvar_antifloodtime = null;

//Definitions
#define CHAT_TAG_PREFIX "[{green}RG{default}] "
#define MAX_GLOVES 50

enum Listing
{
  String:listName[64],
  String:category[64],
  ItemDefinitionIndex,
  FallbackPaintKit,
  Float:wear
}

int g_gloves[MAX_GLOVES][Listing];
int g_gloveCount = 1; //starts from 1, not 0
int g_ClientGlove[MAXPLAYERS+1] = {0, ...};
int g_ClientGloveEntities[MAXPLAYERS+1] = {-1, ...};
bool g_canUse[MAXPLAYERS+1] = {true, ...}; //for anti-flood

ArrayList whitelistModels;

//Flags
AdminFlag rgFlag = Admin_Custom3;

//Menu
Menu glovesMenu = null;
ArrayList categories;
Menu subMenus[MAX_GLOVES];

//Cookies
Handle c_GloveIndex = null;

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
  cvar_show_thirdperson = CreateConVar("sm_rg_showthirdperson", "1", "Show gloves in third person mode, 0: off, 1: all, 2: whitelist (def. 1)");
  cvar_antifloodtime = CreateConVar("sm_rg_antifloodtime", "2.0", "Speed at which clients can use the plugin (def. 2.0)");
  
  //Init array list
  categories = CreateArray(MAX_GLOVES);
  whitelistModels = CreateArray(128);
  
  //Configuration
  ReadCustomModelWhitelist();
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
  
  //Give player spawn 20 frames post spawn
  RequestFrame2(DelayedSpawnGiveGloves, 20, client);
  
  return Plugin_Continue;
}

void DelayedSpawnGiveGloves(int client)
{
  if (g_ClientGlove[client] != 0)
    GiveClientGloves(client, g_ClientGlove[client]);
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
  if (action == MenuAction_Select) {
    char categoryName[64];
    GetMenuItem(menu, itemNum, categoryName, sizeof(categoryName));
    
    //Show menu based on category
    int index = categories.FindString(categoryName);
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
        Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_gloves[item][category], g_gloves[item][listName]);
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
  if (action == MenuAction_Select) {
    if (!g_canUse[client]) {
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Anti Flood Message");
      DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
      return 0;
    }
    
    char itemStr[64];
    GetMenuItem(menu, itemNum, itemStr, sizeof(itemStr));
    int item = StringToInt(itemStr);
  
    GiveClientGloves(client, item);
    
    //Print Chat Option
    char fullGloveName[64];
    Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_gloves[item][category], g_gloves[item][listName]);
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

//Restore ammo of weapons after equiping gloves
void RestoreAmmo(int client) {
  if (IsClientInGame(client) && IsPlayerAlive(client)) {
    //Only process primary and secondary weapons
    RestoreAmmoBySlot(client, CS_SLOT_PRIMARY);
    RestoreAmmoBySlot(client, CS_SLOT_SECONDARY);
  }
}

void RestoreAmmoBySlot(int client, int slot)
{
  if (GetPlayerWeaponSlot(client, slot) != -1) {
    int weaponEntity = GetPlayerWeaponSlot(client, slot);
    if (weaponEntity != -1) {
      //Get ammo
      int clip1 = GetEntProp(weaponEntity, Prop_Send, "m_iClip1");
      int reserve = GetEntProp(weaponEntity, Prop_Send, "m_iPrimaryReserveAmmoCount");
      
      //Create timer to restore ammo
      Handle pack;
      CreateDataTimer(0.0, SetAmmo, pack);
      WritePackCell(pack, EntIndexToEntRef(client));
      WritePackCell(pack, EntIndexToEntRef(weaponEntity));
      WritePackCell(pack, clip1);
      WritePackCell(pack, reserve);
    }
  }
}

public Action SetAmmo(Handle timer, Handle pack)
{
  int client; 
  int weapon;
  int clip1;
  int reserve;
  
  ResetPack(pack);
  
  client = EntRefToEntIndex(ReadPackCell(pack)); 
  weapon = EntRefToEntIndex(ReadPackCell(pack)); 
  clip1 = ReadPackCell(pack); 
  reserve = ReadPackCell(pack); 
  
  if (IsClientInGame(client) && IsPlayerAlive(client)) {
    
    SetEntProp(weapon, Prop_Send, "m_iClip1", clip1);
    SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", reserve);

    int offset_ammo = FindDataMapInfo(client, "m_iAmmo");
    int primaryAmmo = 0;
    int secondaryAmmo = 0;
    
    int offset1 = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") * 4);
    SetEntData(client, offset1, primaryAmmo, 4, true);

    int offset2 = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoType") * 4);
    SetEntData(client, offset2, secondaryAmmo, 4, true);
  }
  
  return Plugin_Handled;
}

void RemoveClientGloves(int client)
{
  if (IsClientConnected(client) && IsClientInGame(client) && IsPlayerAlive(client)) {
    if (g_ClientGloveEntities[client] != -1 && IsWearable(g_ClientGloveEntities[client])) {
      AcceptEntityInput(g_ClientGloveEntities[client], "Kill");
      g_ClientGloveEntities[client] = -1;
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
    
  //We need to set the ammo of primary/secondaries to the correct amount
  //This is because giving a player a "wearable_item" gives them full ammo
  //On all of their guns
  RestoreAmmo(client);
  
  //For randomised index
  //Keep picking random number until a different one is found
  if(i == -1) {
    while (i == g_ClientGlove[client] || i == -1)
      i = GetRandomInt(1, g_gloveCount - 1);
  }
  
  g_ClientGlove[client] = i;
  
  int item = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); 
  SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
  
  //Remove current gloves
  RemoveClientGloves(client);
  
  int ent = CreateEntityByName("wearable_item");
  g_ClientGloveEntities[client] = ent;
  
  //Process non-default gloves
  if (ent != -1 && IsWearable(ent) && (i != 0)) {
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", ent);
    
    SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", g_gloves[i][ItemDefinitionIndex]);
    SetEntProp(ent, Prop_Send,  "m_nFallbackPaintKit", g_gloves[i][FallbackPaintKit]);
    SetEntPropFloat(ent, Prop_Send, "m_flFallbackWear", g_gloves[i][wear]);
    SetEntProp(ent, Prop_Send, "m_iItemIDLow", 2048);
    SetEntProp(ent, Prop_Send, "m_iEntityQuality", 4);
    SetEntProp(ent, Prop_Send,  "m_nFallbackSeed", 0);
    SetEntProp(ent, Prop_Send,  "m_nFallbackStatTrak", -1);
    SetEntProp(ent, Prop_Send, "m_bInitialized", 1); //removed wearable error message

    SetEntPropEnt(ent, Prop_Data, "m_hParent", client);
    SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", client);
    
    //Determine thirdperson mode and if thirdperson should be set for this client
    int thirdPersonMode = GetConVarInt(cvar_show_thirdperson);
    bool setThirdPerson = false;
    
    if (thirdPersonMode == 1)
      setThirdPerson = true; //set for all
    else if (thirdPersonMode == 2) {
      //Get current client model
      char clientCurrentModel[PLATFORM_MAX_PATH];
      GetClientModel(client, clientCurrentModel, sizeof(clientCurrentModel));
      
      for (int j = 0; j < whitelistModels.Length; ++j) {
        char modelName[PLATFORM_MAX_PATH];
        whitelistModels.GetString(j, modelName, sizeof(modelName));
        
        if (StrEqual(clientCurrentModel, modelName, false)) {
          //Whitelisted model, set thirdperson
          setThirdPerson = true;
          break;
        }
      }
    }
    
    //Set third person
    if (setThirdPerson) {
      SetEntPropEnt(ent, Prop_Data, "m_hMoveParent", client);
      SetEntProp(client, Prop_Send, "m_nBody", 1);
    }
    
    DispatchSpawn(ent);
  }
  
  //If default skin, reset these
  if (i == 0) {
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);
    SetEntProp(client, Prop_Send, "m_nBody", 0);
  }
  
  Handle pack;
  CreateDataTimer(0.15, RestoreActiveWeapon, pack, TIMER_FLAG_NO_MAPCHANGE);
  WritePackCell(pack, EntIndexToEntRef(client));
  if (IsValidEntity(item))
    WritePackCell(pack, EntIndexToEntRef(item));
  else
    WritePackCell(pack, -1);
  
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
  if(AreClientCookiesCached(client)) {
    char index[4];
    IntToString(g_ClientGlove[client], index, sizeof(index));
    SetClientCookie(client, c_GloveIndex, index);
  }
  
  g_ClientGlove[client] = 0;
  g_ClientGloveEntities[client] = -1;
  
  //Reset gloves
  if (IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client)) {
    int wearables = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (wearables != -1 && IsWearable(wearables))
      AcceptEntityInput(wearables, "Kill");
  }
}

//Read model whitelist
void ReadCustomModelWhitelist()
{
  char configFilePath[PLATFORM_MAX_PATH];
  Format(configFilePath, sizeof(configFilePath), "configs/csgo_gloves_model_whitelist.txt");
  BuildPath(Path_SM, configFilePath, PLATFORM_MAX_PATH, configFilePath);
  
  if (FileExists(configFilePath)) {
    //Open config file
    File file = OpenFile(configFilePath, "r");
    
    if (file != null) {
      char buffer[PLATFORM_MAX_PATH];
      
      //For each file in the text file
      while (file.ReadLine(buffer, sizeof(buffer))) {
        //Remove final new line
        //buffer length > 0 check needed in case file is completely empty and there is no new line '\n' char after empty string ""
        if (strlen(buffer) > 0 && buffer[strlen(buffer) - 1] == '\n')
          buffer[strlen(buffer) - 1] = '\0';
        
        //Remove any whitespace at either end
        TrimString(buffer);
        
        //Ignore empty lines
        if (strlen(buffer) == 0)
          continue;
          
        //Ignore comment lines
        if (StrContains(buffer, "//") == 0)
          continue; 
        
        //Add to arraylist
        whitelistModels.PushString(buffer);
      }
      
      file.Close();
    }
  } else {
    LogError("Missing required config file: '%s'", configFilePath);
  }
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
  
  if(kv.GotoFirstSubKey())
  {
    do
    {
      //Store values
      kv.GetSectionName(g_gloves[g_gloveCount][listName], 64);
      kv.GetString("category", g_gloves[g_gloveCount][category], 64);
      g_gloves[g_gloveCount][ItemDefinitionIndex] = kv.GetNum("ItemDefinitionIndex");
      g_gloves[g_gloveCount][FallbackPaintKit] = kv.GetNum("FallbackPaintKit");
      g_gloves[g_gloveCount][wear] = kv.GetFloat("wear", 0.0001);
      
      ++g_gloveCount;
    }
    while(kv.GotoNextKey(false));
    
    kv.GoBack();
  }
  else
  {
    kv.Close();
  }
  
  //Create (or update) the menu
  if (glovesMenu != null) {
    CloseHandle(glovesMenu);
    glovesMenu = null;
  }
  
  glovesMenu = CreateMenu(glovesMenuHandler);
  SetMenuTitle(glovesMenu, "%t", "Menu title");
   
  AddMenuItem(glovesMenu, "-1", "Random Gloves");
  AddMenuItem(glovesMenu, "0", "Default Gloves");
  Format(g_gloves[0][listName], 64, "Default");
  Format(g_gloves[0][category], 64, "CSGO");
  
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
      subMenus[index] = CreateMenu(glovesSubMenuHandler);
      SetMenuExitBackButton(subMenus[index], true);
      SetMenuTitle(subMenus[index], "%s Gloves:", g_gloves[i][category]);
    }
    
    //Add item to submenu
    Format(item, sizeof(item), "%i", i);
    AddMenuItem(subMenus[index], item, g_gloves[i][listName]);
  }
  
  SetMenuExitButton(glovesMenu, true);
}

//Restore the active weapon
public Action RestoreActiveWeapon(Handle timer, Handle pack)
{ 
  int client, item; 

  ResetPack(pack); 

  client = EntRefToEntIndex(ReadPackCell(pack)); 
  item = EntRefToEntIndex(ReadPackCell(pack)); 
   
  if (client != INVALID_ENT_REFERENCE && item != INVALID_ENT_REFERENCE) {
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", item);
  }
  
  //Teleporting fixes floating arms with some (custom) player models
  if(IsValidEdict(item)) {
    float origin[3] = 0.0;
    TeleportEntity(item, origin, NULL_VECTOR, NULL_VECTOR);
  }
  
  return Plugin_Stop;
}

//Check if IsWearable
stock bool IsWearable(int entity) {
	static char weaponclass[32];
  
	if(!IsValidEdict(entity))
    return false;
  
	if (!GetEdictClassname(entity, weaponclass, sizeof(weaponclass)))
    return false;
    
	if(StrContains(weaponclass, "wearable", false) == -1)
    return false;
  
	return true;
}

//Credits: KissLick (https://forums.alliedmods.net/member.php?u=210752)
stock void RequestFrame2(RequestFrameCallback func, int framesAhead = 1, any data = 0) 
{ 
  if (framesAhead < 1)
    return; 

  if (framesAhead == 1) {
    RequestFrame(func, data); 
  } else { 
    Handle pack = CreateDataPack(); 
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7 
    WritePackFunction(pack, func); 
#else 
    WritePackCell(pack, func); 
#endif 
    WritePackCell(pack, framesAhead); 
    WritePackCell(pack, data); 

    RequestFrame(RequestFrame2_CallBack, pack); 
  }
} 

//Credits: KissLick (https://forums.alliedmods.net/member.php?u=210752)
public void RequestFrame2_CallBack(any pack)
{ 
  ResetPack(pack); 
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7 
  RequestFrameCallback func = view_as<RequestFrameCallback>(ReadPackFunction(pack));
#else 
  RequestFrameCallback func = ReadPackCell(pack); 
#endif 
  int framesAhead = ReadPackCell(pack) - 1; 
  int data = ReadPackCell(pack); 
  CloseHandle(pack); 
  RequestFrame2(func, framesAhead, data); 
}  
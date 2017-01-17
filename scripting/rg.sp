#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

// Plugin Informaiton  
#define VERSION "1.01"
#define SERVER_LOCK_IP "45.121.211.57"

public Plugin myinfo =
{
  name = "CS:GO VIP Plugin (rg)",
  author = "Invex | Byte",
  description = "Special actions for VIP players.",
  version = VERSION,
  url = "http://www.invexgaming.com.au"
};

//Definitions
#define CHAT_TAG_PREFIX "[{green}RG{default}] "
#define MAX_GLOVES 50
#define ANTI_FLOOD_TIME 3.0

enum Listing
{
  String:listName[64],
  String:category[64],
  ItemDefinitionIndex,
  FallbackPaintKit,
  String:model[PLATFORM_MAX_PATH],
  Float:wear
}

int g_gloves[MAX_GLOVES][Listing];
int g_gloveCount = 1; //starts from 1, not 0
int g_ClientGlove[MAXPLAYERS+1] = {0, ...};
bool g_canUse[MAXPLAYERS+1] = {true, ...}; //for anti-flood

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
  c_GloveIndex = RegClientCookie("invex_rg", "", CookieAccess_Private);
  
  //Translations
  LoadTranslations("rg.phrases");
  
  //Init array list
  categories = CreateArray(MAX_GLOVES);
  
  //Read gloves config file
  ReadGloveConfigFile();
  
  //Process players and set them up
  for (int client = 1; client <= MaxClients; ++client) {
    if (!IsClientInGame(client))
      continue;
    
    OnClientPutInServer(client);
  }
  
  HookEvent("player_spawn", Event_PlayerSpawn);
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
      
      //Print Chat Option
      char fullGloveName[64];
      Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_gloves[item][category], g_gloves[item][listName]);
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove", fullGloveName);
      
      //Set anti flood timer
      g_canUse[client] = false;
      CreateTimer(ANTI_FLOOD_TIME, Timer_ReEnableUsage, client);
      
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
    CreateTimer(ANTI_FLOOD_TIME, Timer_ReEnableUsage, client);
    
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

//Returns index i (converting randomised indexes first)
int GiveClientGloves(int client, int i)
{
  //We need to set the ammo of primary/secondaries to the correct amount
  //This is because giving a player a "wearable_item" gives them full ammo
  //On all of their guns
  RestoreAmmo(client);

  int item = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); 
  SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1); 
  
  int ent = GivePlayerItem(client, "wearable_item");
  
  //Restore default
  if (i == 0) {
    g_ClientGlove[client] = i;
    
    Handle pack2;
    CreateDataTimer(0.0, RestoreActiveWeapon, pack2, TIMER_FLAG_NO_MAPCHANGE);
    WritePackCell(pack2, EntIndexToEntRef(client));
    WritePackCell(pack2, EntIndexToEntRef(item));
    return i;
  }
  
  //For randomised index
  if(i == -1)
    i = GetRandomInt(1, g_gloveCount - 1);
  
  //Set render mode none so we don't see 'floating arms'
  //These floating arms will be killed later on
  SetEntityRenderMode(ent, RENDER_NONE);
  
  if (ent != -1) 
  {
    int m_iItemIDHigh = GetEntProp(ent, Prop_Send, "m_iItemIDHigh"); 
    int m_iItemIDLow = GetEntProp(ent, Prop_Send, "m_iItemIDLow"); 
    
    SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", g_gloves[i][ItemDefinitionIndex]);
    SetEntProp(ent, Prop_Send, "m_iItemIDHigh", -1);
    SetEntProp(ent, Prop_Send, "m_iEntityQuality", 4);
    
    SetEntProp(ent, Prop_Send,  "m_nFallbackPaintKit", g_gloves[i][FallbackPaintKit]);
    SetEntProp(ent, Prop_Send,  "m_iAccountID", GetSteamAccountID(client)); 
    SetEntPropFloat(ent, Prop_Send, "m_flFallbackWear", g_gloves[i][wear]); 
    SetEntProp(ent, Prop_Send,  "m_nFallbackSeed", 0); 
    SetEntProp(ent, Prop_Send,  "m_nFallbackStatTrak", -1);

    int modelEntity = 0;
    //if (!IsModelPrecached(g_gloves[i][model]))
    modelEntity = PrecacheModel(g_gloves[i][model]);
    SetEntProp(ent, Prop_Send, "m_nModelIndex", modelEntity);
    SetEntityModel(ent, g_gloves[i][model]);
    
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", ent); 
    
    //Restore the previous itemID
    Handle pack;
    CreateDataTimer(0.2, RestoreItemID, pack, TIMER_FLAG_NO_MAPCHANGE);
    WritePackCell(pack, EntIndexToEntRef(ent));
    WritePackCell(pack, m_iItemIDHigh);
    WritePackCell(pack, m_iItemIDLow);
     
    Handle pack2;
    CreateDataTimer(0.0, RestoreActiveWeapon, pack2, TIMER_FLAG_NO_MAPCHANGE);
    WritePackCell(pack2, EntIndexToEntRef(client));
    WritePackCell(pack2, EntIndexToEntRef(item));
    
    //Set local variable
    g_ClientGlove[client] = i;
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
  if(AreClientCookiesCached(client)) {
    char index[4];
    IntToString(g_ClientGlove[client], index, sizeof(index));
    SetClientCookie(client, c_GloveIndex, index);
  }

  g_ClientGlove[client] = 0;
}

//Process clients when plugin ends (call cleanup for each client)
public void OnPluginEnd()
{
  for (int client = 1; client <= MaxClients; ++client) {
    if (IsClientInGame(client)) {
      OnClientDisconnect(client);
    }
  }
}

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
      kv.GetString("model", g_gloves[g_gloveCount][model], PLATFORM_MAX_PATH);
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
      int newIndex = categories.PushString(g_gloves[i][category]);
      
      //Add menu option
      Format(categoryName, sizeof(categoryName), "%s", g_gloves[i][category]);
      AddMenuItem(glovesMenu, categoryName, g_gloves[i][category]);
      
      //Create Menu
      subMenus[newIndex] = CreateMenu(glovesSubMenuHandler);
      SetMenuExitBackButton(subMenus[newIndex], true);
      SetMenuTitle(subMenus[newIndex], "%s Gloves:", g_gloves[i][category]);
    } else {
      //Add item to submenu
      Format(item, sizeof(item), "%i", i);
      AddMenuItem(subMenus[index], item, g_gloves[i][listName]);
    }
  }
  
  SetMenuExitButton(glovesMenu, true);
}


//Restore itemIDs and kill floating arms
public Action RestoreItemID(Handle timer, Handle pack)
{
  int entity;
  int m_iItemIDHigh;
  int m_iItemIDLow;
  
  ResetPack(pack);
  entity = EntRefToEntIndex(ReadPackCell(pack));
  m_iItemIDHigh = ReadPackCell(pack);
  m_iItemIDLow = ReadPackCell(pack);
  
  if (entity != INVALID_ENT_REFERENCE) {
    SetEntProp(entity, Prop_Send, "m_iItemIDHigh", m_iItemIDHigh);
    SetEntProp(entity, Prop_Send, "m_iItemIDLow", m_iItemIDLow);
    AcceptEntityInput(entity, "Kill");
  }
  
  return Plugin_Handled;
}

//Restore the active weapon
public Action RestoreActiveWeapon(Handle timer, Handle pack)
{ 
  int client; 
  int item; 

  ResetPack(pack); 

  client = EntRefToEntIndex(ReadPackCell(pack)); 
  item = EntRefToEntIndex(ReadPackCell(pack)); 
   
  if (client != INVALID_ENT_REFERENCE && item != INVALID_ENT_REFERENCE) 
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", item);
  
  return Plugin_Stop;
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
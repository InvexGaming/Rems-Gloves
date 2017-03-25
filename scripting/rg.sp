#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

// Plugin Informaiton
#define VERSION "1.06"
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

float MAP_BOUNDARY_POINT[3] = {16383.0, 16383.0, 16383.0};

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

ArrayList whitelistModels;

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
  cvar_show_thirdperson = CreateConVar("sm_rg_showthirdperson", "1", "Show gloves in third person mode, 0: off, 1: all, 2: whitelist (def. 1)");
  cvar_antifloodtime = CreateConVar("sm_rg_antifloodtime", "2.0", "Speed at which clients can use the plugin (def. 2.0)");
  
  //Prepare SDK call values
  Handle hConfig = LoadGameConfigFile("wearables.games");
  int iEquipOffset = GameConfGetOffset(hConfig, "EquipWearable");
  StartPrepSDKCall(SDKCall_Player);
  PrepSDKCall_SetVirtual(iEquipOffset);
  PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
  g_hGiveWearableCall = EndPrepSDKCall();
  
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
    Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_gloves[item][category], g_gloves[item][skinName]);
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
  
  int ent = CreateEntityByName("wearable_item");
  g_ClientGloveEntities[client] = EntIndexToEntRef(ent);
  
  //Process non-default gloves
  if (ent != -1 && i != 0) {
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
   
    //Call SDK function to give wearable
    SDKCall(g_hGiveWearableCall, client, ent);
    DispatchKeyValue(ent, "effects", "4225");
    
    //Set third person
    if (!setThirdPerson) {
      //TODO: This is a poor method, improve it
      //Teleport gloves to unplayable area in map to hide them
      SetEntPropEnt(ent, Prop_Data, "m_hMoveParent", -1);
      TeleportEntity(ent, MAP_BOUNDARY_POINT, NULL_VECTOR, NULL_VECTOR);
      SetEntProp(client, Prop_Send, "m_nBody", 0);
    }
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
  
  glovesMenu = CreateMenu(glovesMenuHandler);
  SetMenuTitle(glovesMenu, "%t", "Menu title");
   
  AddMenuItem(glovesMenu, "-1", "Random Gloves");
  AddMenuItem(glovesMenu, "0", "Default Gloves");
  Format(g_gloves[0][skinName], 64, "Default");
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
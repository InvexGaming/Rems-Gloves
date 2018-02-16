#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>
#include <colors_csgo_v2>

#pragma semicolon 1
#pragma newdecls required

// Plugin Informaiton
#define VERSION "1.15"

public Plugin myinfo =
{
  name = "Rems Gloves (!rg)",
  author = "Invex | Byte",
  description = "Provides official Valve gloves to players.",
  version = VERSION,
  url = "http://www.invexgaming.com.au"
};

//Convars
ConVar g_Cvar_AntiFloodTime = null;
ConVar g_Cvar_VipFlag = null;

//Definitions
#define CHAT_TAG_PREFIX "[{lime}RG{default}] "
#define MAX_GLOVES 50
#define SKIN_MAX_LENGTH 64
#define CATEGORY_MAX_LENGTH 64
#define RANDOM_GLOVES -1
#define DEFAULT_GLOVES 0
#define MAX_MENU_OPTIONS 8

//All entries in this array must be unique
static char s_NormalSleeves[][] = 
{
  "models/weapons/t_arms.mdl",
  "models/weapons/ct_arms.mdl",
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

//Gloove variants of normal sleeves
//Each entry here matches the entry in s_NormalSleeves with the same index
//Blank string indicates default arms
static char s_GloveSleeves[][] = 
{
  "", //just use defaults
  "", //just use defaults
  "models/weapons/v_models/arms/anarchist/v_sleeve_anarchist.mdl",
  "models/weapons/v_models/arms/pirate/v_pirate_watch.mdl",
  "models/weapons/v_models/arms/professional/v_sleeve_professional.mdl",
  "models/weapons/v_models/arms/separatist/v_sleeve_separatist.mdl",
  "models/weapons/v_models/arms/balkan/v_sleeve_balkan.mdl",
  "", //no leet v_model exists for leet T skin
  "", //no leet v_model exists for phoenix T skin
  "models/weapons/v_models/arms/gign/v_sleeve_gign.mdl",
  "models/weapons/v_models/arms/gsg9/v_sleeve_gsg9.mdl",
  "models/weapons/v_models/arms/st6/v_sleeve_st6.mdl",
  "models/weapons/v_models/arms/fbi/v_sleeve_fbi.mdl",
  "models/weapons/v_models/arms/idf/v_sleeve_idf.mdl",
  "models/weapons/v_models/arms/sas/v_sleeve_sas.mdl",
  "models/weapons/v_models/arms/swat/v_sleeve_swat.mdl"
};

enum GloveStruct
{
  String:skinName[SKIN_MAX_LENGTH],
  String:category[CATEGORY_MAX_LENGTH],
  String:worldModel[PLATFORM_MAX_PATH],
  ItemDefinitionIndex,
  FallbackPaintKit,
  Float:wear
}

int g_Gloves[MAX_GLOVES][GloveStruct];
int g_GloveCount = 1; //starts from 1, not 0
int g_ClientGlove[MAXPLAYERS+1] = {0, ...};
int g_ClientGloveEntities[MAXPLAYERS+1] = {-1, ...};
int g_ClientSleeveIndex[MAXPLAYERS+1] = {-1, ...}; //store index into s_NormalSleeves/s_GloveSleeves
bool g_CanUse[MAXPLAYERS+1] = {true, ...}; //for anti-flood

//Menu
Menu g_GloveMenu = null;
ArrayList g_Categories;
Menu g_SubMenus[MAX_GLOVES];
int g_NumSubMenus = 0;

//Cookies
Handle g_GloveIndexCookie = null;

//SDKCall
Handle g_GiveWearableCall = null;
Handle g_LookupAttachmentCall = null;
Handle g_LookupBoneCall = null;

//Lateload
bool g_LateLoaded = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  g_LateLoaded = late;
  return APLRes_Success;
}

public void OnPluginStart()
{
  //Translations
  LoadTranslations("rg.phrases");

  //Store preferences in clientprefs
  g_GloveIndexCookie = RegClientCookie("rg_Gloves_preference", "", CookieAccess_Private);
  
  //Convars
  g_Cvar_AntiFloodTime = CreateConVar("sm_rg_antifloodtime", "0.75", "Speed at which clients can use the plugin (def. 2.0)");
  g_Cvar_VipFlag = CreateConVar("sm_rg_vipflag", "z", "Which flag to use for plugin access");
    
  //Create config file
  AutoExecConfig(true, "rg");
  
  //Commands
  RegConsoleCmd("sm_rg", Command_ShowGlovesMenu, "Show menu for glove selection");
  RegConsoleCmd("sm_glove", Command_ShowGlovesMenu, "Show menu for glove selection");
  RegConsoleCmd("sm_gloves", Command_ShowGlovesMenu, "Show menu for glove selection");
  RegAdminCmd("sm_rg_reloadconfig", Command_ReloadConfig, ADMFLAG_ROOT, "Reload config file");
  
  //Prepare SDK call values
  
  //g_GiveWearableCall
  Handle hConfig = LoadGameConfigFile("wearables.games");
  if (hConfig == null)
    SetFailState("Error loading wearables.games gamedata file.");
  
  int iEquipOffset = GameConfGetOffset(hConfig, "EquipWearable");
  if (iEquipOffset == -1)
    SetFailState("Error getting EquipWearable offset.");
  
  StartPrepSDKCall(SDKCall_Player);
  PrepSDKCall_SetVirtual(iEquipOffset);
  PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
  g_GiveWearableCall = EndPrepSDKCall();
  
  delete hConfig;
  
  //g_LookupAttachmentCall
  hConfig = LoadGameConfigFile("rg.games");
  if (hConfig == null)
    SetFailState("Error loading rg.games gamedata file.");
  
  StartPrepSDKCall(SDKCall_Entity);
  PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "LookupAttachment");
  PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
  PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
  g_LookupAttachmentCall = EndPrepSDKCall();
  
  if (!g_LookupAttachmentCall)
    SetFailState("Error finding LookupAttachment signature.");
  
  //g_LookupBoneCall
  //int CBaseAnimating::LookupBone( const char *szName )
  //Returns: Bone index number of -1 if no bone found
  StartPrepSDKCall(SDKCall_Entity);
  PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "LookupBone");
  PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
  PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
  g_LookupBoneCall = EndPrepSDKCall();
  
  if (!g_LookupBoneCall)
    SetFailState("Error finding LookupBone signature.");
  
  delete hConfig;
  
  //Init array list
  g_Categories = new ArrayList(CATEGORY_MAX_LENGTH);
  
  //Configuration
  ReadGloveConfigFile();
  
  //Late load
  if (g_LateLoaded) {
    for (int i = 1; i <= MaxClients; ++i) {
      if (IsClientInGame(i))
        OnClientPutInServer(i);
    }
    
    g_LateLoaded = false;
  }
  
  //Hooks
  HookEvent("player_spawn", Event_PlayerSpawn);
  HookEvent("player_team", Event_PlayerTeam);
}

public void OnMapStart()
{
  //Precache arms sleeve models
  for (int i = 0; i < sizeof(s_GloveSleeves); i++) {
    if (FileExists(s_GloveSleeves[i]))
      PrecacheModel(s_GloveSleeves[i], true);
  }
  
  for (int i = 0; i < sizeof(s_NormalSleeves); i++) {
    if (FileExists(s_NormalSleeves[i]))
      PrecacheModel(s_NormalSleeves[i], true);
  }
}

public void OnPluginEnd()
{
  for(int i = 1; i <= MaxClients; ++i) {
    if (IsClientInGame(i)) {
      //Cookie saving
      OnClientDisconnect(i);
      
      //Removing gloves
      if (IsPlayerAlive(i))
        RemoveClientGloves(i);
        
      ForceClientRefreshAll(i);
    }
  }
}

public void OnClientPutInServer(int client)
{
  //Reset variables
  g_CanUse[client] = true;
  g_ClientGloveEntities[client] = INVALID_ENT_REFERENCE;
  g_ClientSleeveIndex[client] = -1;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));
  
  //Do actual giving of gloves in next frame
  //Allows other player_spawn hooks to change arms/models if needed
  RequestFrame(RequestFrame_PlayerSpawn, client);
  
  return Plugin_Continue;
}

public void RequestFrame_PlayerSpawn(int client)
{
  //Get VIP status
  char buffer[2];
  g_Cvar_VipFlag.GetString(buffer, sizeof(buffer));
  bool isVip = ClientHasCharFlag(client, buffer[0]);
  
  //Force default gloves for non VIP
  if (!isVip)
    g_ClientGlove[client] = 0;
  
  //Give player gloves, also does processing for default gloves/no gloves
  GiveClientGloves(client, g_ClientGlove[client]);
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));
  
  if (!(client > 0 && client <= MaxClients && IsClientInGame(client)))
    return Plugin_Handled;
  
  int toTeam = event.GetInt("team");
  
  if (toTeam == CS_TEAM_SPECTATOR || toTeam == CS_TEAM_NONE) {
    //Body will be instantly removed so remove glove entities
    RemoveClientGloves(client);
    ForceClientRefreshAll(client);
  }
  
  return Plugin_Continue;
}

//Show Gloves Menu
public Action Command_ShowGlovesMenu(int client, int args)
{
  //Get VIP status
  char buffer[2];
  g_Cvar_VipFlag.GetString(buffer, sizeof(buffer));
  bool isVip = ClientHasCharFlag(client, buffer[0]);
  
  if (!isVip) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Must be VIP");
    return Plugin_Handled;
  }
  
  //Otherwise continue normally
  ShowGlovesMenu(client);
  
  return Plugin_Handled;
}

public void ShowGlovesMenu(int client)
{    
  if (!(1 <= client <= MaxClients))
    return;
    
  if (!IsClientInGame(client))
    return;
  
  g_GloveMenu.Display(client, MENU_TIME_FOREVER);
}

public int GloveMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
  //Get menu info
  char info[64];
  char display[64];
  menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));

  if (action == MenuAction_DrawItem) {
    //Hacky way to set title
    if (param2 % MAX_MENU_OPTIONS == 0) { 
      char titleString[1024];
      Format(titleString, sizeof(titleString), "%t (V%s)\n%t %s | %s\n ", "Menu Title", VERSION, "Menu Current Gloves Title", g_Gloves[g_ClientGlove[client]][category], g_Gloves[g_ClientGlove[client]][skinName]);
      menu.SetTitle(titleString);
    }
    
    if (g_ClientGlove[client] == DEFAULT_GLOVES && StrEqual(display, "Default Gloves"))
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_ClientGlove[client] == DEFAULT_GLOVES && StrEqual(display, "Default Gloves")) {
      //Change selected text
      char equipedText[CATEGORY_MAX_LENGTH + 5]; //4 bytes + 1 null terminator
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    //Show menu based on category name (provided as info)
    int index = g_Categories.FindString(info);
    if (index != -1) {
      g_SubMenus[index].Display(client, MENU_TIME_FOREVER);
    }
    else if (param2 <= 1) { //first 2 options
      if (!g_CanUse[client]) {
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Anti Flood Message");
        menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
        return 0;
      }
      
      int item = -1;
      
      //Subtract 1 as 0 is default and -1 is random
      if (IsPlayerAlive(client)) {
        item = GiveClientGloves(client, param2 - 1); //Set and Equip
      } else {
        item = SetClientGloves(client, param2 - 1); //Only Set
      }
      
      if (item != -1) {
        //Print Chat Option
        char fullGloveName[CATEGORY_MAX_LENGTH + SKIN_MAX_LENGTH + 4]; //3 bytes + 1 null terminator
        Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_Gloves[item][category], g_Gloves[item][skinName]);
        
        if (IsPlayerAlive(client))
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove", fullGloveName);
        else
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove Dead", fullGloveName);
          
        //Print out legacy player model warning
        if (IsClientModelLegacy(client))
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Legacy Player Model");

        //Print out custom arms warning
        if (IsClientArmsModelCustom(client))
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Custom Arms Model");
      }
      
      //Set anti flood timer
      g_CanUse[client] = false;
      CreateTimer(g_Cvar_AntiFloodTime.FloatValue, Timer_ReEnableUsage, client);
      
      menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
    }
    else {
      menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
    }
  }
  
  return 0;
}

public int GloveSubMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
  //Get menu info
  char info[64];
  char display[64];
  GetMenuItem(menu, param2, info, sizeof(info), _, display, sizeof(display));
  int selectedIndex = StringToInt(info);
  
  if (action == MenuAction_DrawItem) {
    if (g_ClientGlove[client] == selectedIndex)
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_ClientGlove[client] == selectedIndex) {
      //Change selected text
      char equipedText[SKIN_MAX_LENGTH + 5]; //4 bytes + 1 null terminator
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    if (!g_CanUse[client]) {
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Anti Flood Message");
      menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
      return 0;
    }
  
    int item = -1;
    
    if (IsPlayerAlive(client)) {
      item = GiveClientGloves(client, selectedIndex); //Set and Equip
    } else {
      item = SetClientGloves(client, selectedIndex); //Only Set
    }
    
    if (item != -1) {
      //Print Chat Option
      char fullGloveName[CATEGORY_MAX_LENGTH + SKIN_MAX_LENGTH + 4]; //3 bytes + 1 null terminator
      Format(fullGloveName, sizeof(fullGloveName), "%s | %s", g_Gloves[item][category], g_Gloves[item][skinName]);
      
      if (IsPlayerAlive(client))
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove", fullGloveName);
      else
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Equipped Glove Dead", fullGloveName);
    }
    
    //Set anti flood timer
    g_CanUse[client] = false;
    CreateTimer(g_Cvar_AntiFloodTime.FloatValue, Timer_ReEnableUsage, client);
    
    menu.DisplayAt(client, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
  }
  else if (action == MenuAction_Cancel)
  {
    if (param2 == MenuCancel_ExitBack) {
      //Goto main menu
      g_GloveMenu.DisplayAt(client, 0, MENU_TIME_FOREVER);
    }
  }
  
  return 0;
}

//Re-enable ws for particular client
public Action Timer_ReEnableUsage(Handle timer, int client)
{
  g_CanUse[client] = true;
}

void RemoveClientGloves(int client)
{
  if (IsClientInGame(client) && IsPlayerAlive(client)) {
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
int SetClientGloves(int client, int i)
{
  if(!IsClientInGame(client) || IsFakeClient(client))
    return -1;
    
  //Invalid index
  if (i < -1 || i > g_GloveCount - 1)
    return -1;
    
  //For randomised index
  //Keep picking random number until a different one is found
  if(i == -1) {
    while (i == g_ClientGlove[client] || i == -1)
      i = GetRandomInt(1, g_GloveCount - 1);
  }
  
  g_ClientGlove[client] = i;
  
  return i;
}

//Give a client their gloves (set and give)
int GiveClientGloves(int client, int i)
{
  if(!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
    return -1;
    
  //Invalid index
  if (i < -1 || i > g_GloveCount - 1)
    return -1;

  //Set client gloves
  i = SetClientGloves(client, i);
  
  //Remove current gloves
  RemoveClientGloves(client);
  
  //Check if using custom arms
  bool isUsingCustomArms = IsClientArmsModelCustom(client);

  //Update the clients sleeves to use a gloves supporting arms model for non-custom arms
  if (!isUsingCustomArms)
    UpdateClientSleeves(client);

  //If non-default gloves and we aren't using custom arms, give the client gloves
  if (i != DEFAULT_GLOVES && !isUsingCustomArms) {
    int ent = CreateEntityByName("wearable_item");
    
    //Process non-default gloves
    if (ent != -1) {
      g_ClientGloveEntities[client] = EntIndexToEntRef(ent);
    
      SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", client);
      SetEntityModel(ent, g_Gloves[i][worldModel]);
      SetEntProp(ent, Prop_Send, "m_nModelIndex", PrecacheModel(g_Gloves[i][worldModel]));
      SetEntProp(ent, Prop_Send, "m_iTeamNum", GetClientTeam(client));
      SetEntProp(client, Prop_Send, "m_nBody", 1);
      
      //Set skin properties
      SetEntProp(ent, Prop_Send, "m_bInitialized", 1); //removed wearable error message
      SetEntProp(ent, Prop_Send,  "m_iAccountID", GetSteamAccountID(client));
      SetEntProp(ent, Prop_Send, "m_iItemIDLow", 2048);
      SetEntProp(ent, Prop_Send, "m_iEntityQuality", 4);
      SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", g_Gloves[i][ItemDefinitionIndex]);
      SetEntProp(ent, Prop_Send,  "m_nFallbackPaintKit", g_Gloves[i][FallbackPaintKit]);
      SetEntPropFloat(ent, Prop_Send, "m_flFallbackWear", g_Gloves[i][wear]);
      
      SetVariantString("!activator");
      ActivateEntity(ent);
     
      //Call SDK function to give wearable
      SDKCall(g_GiveWearableCall, client, ent);
      
      //After SDK call is made, check if we should remove model in third person view for legacy player models
      if (IsClientModelLegacy(client))
        SetEntPropEnt(ent, Prop_Data, "m_hMoveParent", -1);
    }
  }
  //Otherwise, reset the values for default gloves 
  else {
    SetEntProp(client, Prop_Send, "m_nBody", 0);
  }
  
  //Send a client refresh to all players
  //This will refresh viewmodel for them updating gloves
  //Also avoids 'glove stack' bug if gloves changed mid round
  ForceClientRefreshAll(client);
  
  return i;
}

public void OnClientCookiesCached(int client)
{
  char index[4];
  GetClientCookie(client, g_GloveIndexCookie, index, sizeof(index));
  g_ClientGlove[client] = StringToInt(index);
}

//Clean up when client disconnects
public void OnClientDisconnect(int client)
{ 
  if (IsFakeClient(client))
    return;
  
  if (AreClientCookiesCached(client)) {
    char index[4];
    IntToString(g_ClientGlove[client], index, sizeof(index));
    SetClientCookie(client, g_GloveIndexCookie, index);
  }
  
  g_ClientGlove[client] = 0;
  g_ClientGloveEntities[client] = INVALID_ENT_REFERENCE;
}

public Action Command_ReloadConfig(int client, int args)
{
  ReadGloveConfigFile();
  CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Config Reloaded");
  return Plugin_Handled;
}

//Read glove config file
void ReadGloveConfigFile()
{ 
  //Reset values
  delete g_GloveMenu;
  for (int i = 0; i < g_NumSubMenus; ++i) {
    delete g_SubMenus[i];
  }
  
  g_GloveCount = 1; //starts at 1
  g_NumSubMenus = 0;
  
  //Create main menu
  g_GloveMenu = new Menu(GloveMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
  
  char numStrBuffer[3];
  IntToString(RANDOM_GLOVES, numStrBuffer, sizeof(numStrBuffer));
  g_GloveMenu.AddItem(numStrBuffer, "Random Gloves");  //Add Random Gloves option
  IntToString(DEFAULT_GLOVES, numStrBuffer, sizeof(numStrBuffer));
  g_GloveMenu.AddItem(numStrBuffer, "Default Gloves"); //Add Default Gloves option
  Format(g_Gloves[DEFAULT_GLOVES][skinName], SKIN_MAX_LENGTH, "Default");
  Format(g_Gloves[DEFAULT_GLOVES][category], CATEGORY_MAX_LENGTH, "CSGO");
  
  //Clear categories
  g_Categories.Clear();
  
  //Search for config file
  char path[PLATFORM_MAX_PATH];
  Format(path, sizeof(path), "configs/rg.cfg");
  BuildPath(Path_SM, path, sizeof(path), path);
  
  if (!FileExists(path)) {
    SetFailState("Config file rg.cfg was not found");
  }
  
  KeyValues kv = new KeyValues("Gloves");
  
  if (!kv.ImportFromFile(path))
    return;
  
  if(kv.GotoFirstSubKey(true))
  {
    do
    {
      //Get glove family information
      char gloveCategory[CATEGORY_MAX_LENGTH];
      kv.GetSectionName(gloveCategory, sizeof(gloveCategory));      
      int m_iItemDefinitionIndex = kv.GetNum("ItemDefinitionIndex");
      char model_world[PLATFORM_MAX_PATH];
      kv.GetString("model_world", model_world, sizeof(model_world));
      
      //Process catagory here if its a new category
      int categoryIndex = g_Categories.FindString(gloveCategory);
      if (categoryIndex == -1) {
        //Push
        categoryIndex = g_Categories.PushString(gloveCategory);
        
        //Add Menu Option
        g_GloveMenu.AddItem(gloveCategory, gloveCategory);
        
        //Create Sub Menu
        g_SubMenus[categoryIndex] = new Menu(GloveSubMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
        g_SubMenus[categoryIndex].SetTitle("%s Gloves:", gloveCategory);
        g_SubMenus[categoryIndex].ExitBackButton = true;
        ++g_NumSubMenus;
      }
      
      //Iterate through skins
      if(kv.JumpToKey("skins", false)) {
        if(kv.GotoFirstSubKey(true)) {
          do {
            Format(g_Gloves[g_GloveCount][category], CATEGORY_MAX_LENGTH, gloveCategory);
            g_Gloves[g_GloveCount][ItemDefinitionIndex] = m_iItemDefinitionIndex;
            Format(g_Gloves[g_GloveCount][worldModel], PLATFORM_MAX_PATH, model_world);
            kv.GetSectionName(g_Gloves[g_GloveCount][skinName], SKIN_MAX_LENGTH);
            g_Gloves[g_GloveCount][FallbackPaintKit] = kv.GetNum("FallbackPaintKit");
            g_Gloves[g_GloveCount][wear] = kv.GetFloat("wear", 0.0001);
          
            //Add this skin to its categories submenu
            char item[4];
            Format(item, sizeof(item), "%i", g_GloveCount);
            g_SubMenus[categoryIndex].AddItem(item, g_Gloves[g_GloveCount][skinName]);
          
            ++g_GloveCount;
          } while (kv.GotoNextKey(true));
          kv.GoBack();
        }
        kv.GoBack();
      }
    } while(kv.GotoNextKey(true));
    
    kv.GoBack();
  }
  
  delete kv;
}

//Force client refresh and fireTo all players
stock void ForceClientRefreshAll(int playerToRefresh)
{
  for (int i = 1; i <= MaxClients; ++i) {
    if (IsClientInGame(i) && !IsFakeClient(i)) {
      ForceClientRefresh(playerToRefresh, i);
    }
  }
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

//Set the appropriate sleeves (arms models) based of if client is using gloves or not
stock void UpdateClientSleeves(int client)
{
  //Get current arms
  char m_szArmsModel[PLATFORM_MAX_PATH];
  GetEntPropString(client, Prop_Send, "m_szArmsModel", m_szArmsModel, sizeof(m_szArmsModel));
  
  //We need to get the sleve index
  //We search in this order: NormalSleeves -> g_ClientSleeveIndex -> s_GloveSleeves
  //The s_GloveSleeves search is only a fallback as the first two searches should return a result
  int index = SearchArray(s_NormalSleeves, sizeof(s_NormalSleeves), m_szArmsModel);
  
  if (index == -1)
    index = g_ClientSleeveIndex[client];
  
  if (index == -1)
    index = SearchArray(s_GloveSleeves, sizeof(s_GloveSleeves), m_szArmsModel);
    
  if (index == -1)
    SetFailState("Failed to find a sleeve index");
  
  //Preserve the index for the next usage
  g_ClientSleeveIndex[client] = index;
  
  //If using default gloves
  if (g_ClientGlove[client] == DEFAULT_GLOVES) {
    //Need to set s_NormalSleeves
    Format(m_szArmsModel, sizeof(m_szArmsModel), s_NormalSleeves[index]);
  }
  else {
    //Need to set s_GloveSleeves
    Format(m_szArmsModel, sizeof(m_szArmsModel), s_GloveSleeves[index]);
  }
  
  //If non emtpy model, perform precache here
  //Fixes issue where arms don't appear properly and default back to maps arms
  if (!StrEqual(m_szArmsModel, ""))
    PrecacheModel(m_szArmsModel, false);
  
  //Finally set arms model
  SetEntPropString(client, Prop_Send, "m_szArmsModel", m_szArmsModel);
  
  //Perform refresh at this point
  ForceClientRefreshAll(client);
}

//Check if client is using a legacy player model
bool IsClientModelLegacy(int client)
{
  if (!SDKCall(g_LookupAttachmentCall, client, "legacy_weapon_bone"))
    return true;
  else {
    if (SDKCall(g_LookupBoneCall, client, "ValveBiped.Bip01_Pelvis") != -1)
      return true;
    else
      return false;
  }
}

//Check if the client is using custom player arms (non stock normal/sleeve arms)
bool IsClientArmsModelCustom(int client)
{
  //Get current arms
  char m_szArmsModel[PLATFORM_MAX_PATH];
  GetEntPropString(client, Prop_Send, "m_szArmsModel", m_szArmsModel, sizeof(m_szArmsModel));

  //Search normal sleeves and glove sleeves arrays
  int index = SearchArray(s_NormalSleeves, sizeof(s_NormalSleeves), m_szArmsModel);
  if (index == -1)
    index = SearchArray(s_GloveSleeves, sizeof(s_GloveSleeves), m_szArmsModel);

  return (index == -1);
}

//Given an array, searches 
stock int SearchArray(char[][] array, int arrayMaxLength, char[] searchString, bool caseSensitive = false)
{
  for (int i = 0; i < arrayMaxLength; ++i) {
    if (StrEqual(searchString, array[i], caseSensitive))
      return i;
  }
  
  return -1;
}

stock bool ClientHasCharFlag(int client, char charFlag)
{
  AdminFlag flag;
  return (FindFlagByChar(charFlag, flag) && ClientHasAdminFlag(client, flag));
}

stock bool ClientHasAdminFlag(int client, AdminFlag flag)
{
  if (!IsClientConnected(client))
    return false;
  
  AdminId admin = GetUserAdmin(client);
  if (admin != INVALID_ADMIN_ID && GetAdminFlag(admin, flag, Access_Effective))
    return true;
  return false;
}
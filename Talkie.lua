-------------------------------------------------------------------------------
--  Libraries --
-------------------------------------------------------------------------------
local LAM2 = LibStub:GetLibrary("LibAddonMenu-2.0")

Talkie = {}
Talkie.name = "Talkie"
Talkie.version = "1"
Talkie.varversion = 1

Talkie.Default = {
	isGrouped = false,
	isLeader = false,
	groupSize = 1,
	leaderUnitTag = nil,
	leaderName = nil,
	client = "Discord",
	preamble = nil,
	leaderInvite = "",
	invite = nil,
	invitePending = false
}

function Talkie.OnAddOnLoaded(event, addonName)
  if addonName == Talkie.name then
    Talkie:Initialize()
  end
end

function Talkie:Initialize()
  Talkie.saved = ZO_SavedVars:New("TalkieVars", Talkie.varversion, nil, Talkie.Default)
  Talkie.saved.preamble = Talkie.name .. ": [" .. Talkie.saved.client .. "] "
  self:SaveGroupState()

  -- State variables
  self.playerName = GetUnitName("player")
  self.displayName = GetDisplayName()
  self.isInCombat = false

  -- Menu panel
  Talkie:CreateSettingsWindow()

  -- Event handlers
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_GROUP_MEMBER_JOINED, Talkie.OnMemberJoin)
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_GROUP_MEMBER_LEFT, Talkie.OnMemberLeave)
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_LEADER_UPDATE, Talkie.OnLeaderChange)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CHAT_MESSAGE_CHANNEL, Talkie.OnChatMessage)
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_PLAYER_COMBAT_STATE, Talkie.OnCombatState)
  EVENT_MANAGER:UnregisterForEvent(Talkie.name, EVENT_ADD_ON_LOADED)
end


------------------------------------------------------------------------------
-- ESO helper functions
------------------------------------------------------------------------------

-- get full name i.e. charact^er@DisplayName
function Talkie:GetFullName(tag)
  if tag then
    local cn = GetRawUnitName(tag) or "none"
    local dn = GetUnitDisplayName(tag) or "none"
    return cn .. DecorateDisplayName(dn)
  else
    return "none"
  end
end

-- update all saved variables related to group state
function Talkie:SaveGroupState()
  Talkie.saved.isGrouped = IsUnitGrouped("player")

  if Talkie.saved.isGrouped then
    Talkie.saved.groupSize = GetGroupSize() or 1
    Talkie.saved.isLeader = IsUnitGroupLeader("player")
    Talkie.saved.leaderUnitTag = GetGroupLeaderUnitTag()
    Talkie.saved.leaderName = Talkie:GetFullName(Talkie.saved.leaderUnitTag)
  else
    Talkie.saved.groupSize = 1
    Talkie.saved.isLeader = false
    Talkie.saved.leaderUnitTag = nil
    Talkie.saved.leaderName = nil
  end
end

------------------------------------------------------------------------------
-- ESO Event callbacks
------------------------------------------------------------------------------

function Talkie:OnMemberJoin(name)
  d(name .. " joined the group as a new member")
  Talkie:SaveGroupState()

  if Talkie.saved.isLeader then
    d("as leader I must invite new members to chat")
    if Talkie.saved.invite then
      -- send the invite we have
      Talkie:ChatInviteGroup()
    else
      -- need to set up
      Talkie:GroupLeaderSetup()
    end
  end
end

function Talkie:OnMemberLeave(name, reason, isLocal, isLeader, dn, vote)
  -- sort out the reason in case it is relevant
  local action = " left"
  if     reason == GROUP_LEAVE_REASON_DESTROYED then
    action = " disappeared after you left or were kicked from"
  elseif reason == GROUP_LEAVE_REASON_DISBAND then
    action = " was disbanded with"
  elseif reason == GROUP_LEAVE_REASON_KICKED then
    action = " was kicked by leader from"
  elseif reason == GROUP_LEAVE_REASON_LEFT_BATTLEGROUND then
    action = " left battleground from"
  elseif reason == GROUP_LEAVE_REASON_VOLUNTARY then
    action = " left voluntarily from"
  end

  -- sort out isLeader
  local wasLeader = " (was not leader)"
  if isLeader then
    wasLeader = " (was leader)"
  end

  -- was it me that left?
  if isLocal then
    -- I left the group
    d("I" .. action .. " the group" .. wasLeader)
    Talkie:GroupMemberTeardown()

    if isLeader then
      -- I was the leader
      Talkie:GroupLeaderTeardown()
    end

  else
    -- somebody else left the group
    d(name .. dn .. action .. " the group" .. wasLeader)
  end

  Talkie:SaveGroupState()
end

function Talkie:OnLeaderChange(tag)
  d("OnLeaderChange(" .. tag .. ")")
  local fn = Talkie:GetFullName(tag)

  if tag == "player" then
    d("I am now leader")
    Talkie:GroupLeaderSetup()
  elseif Talkie.saved.isLeader then
    d("I am no longer leader")
    Talkie:GroupLeaderTeardown()
  else
    d(fn .. " is new group leader")
  end

  Talkie:SaveGroupState()
end

-- Chat parser - still working up to coding the link handler
function Talkie:OnChatMessage(chan, from, text, isCS, fromDN)
  local channel = nil
  if chan == CHAT_CHANNEL_PARTY then channel = "group"
  else return end

  local first = from or "none"
  local last = fromDN or "none"
  local author = first .. DecorateDisplayName(last)
  local leader = Talkie.saved.leaderName or "lnone"

  d(Talkie.name .. ": [" .. author  .. "] " .. channel .. ": " .. text)
  d("Author: " .. author)
  d("Leader: " .. leader)
  if author == leader then
    d("message came from group leader")
    i,j = string.find(text,Talkie.saved.preamble)
    if not i then return end
    local invite = string.sub(text, j+1)
    d("received chat invite: " .. invite)
    Talkie:GroupMemberSetup(invite)
  end
end

-- track combat state so we can defer sending invitations until after combat
function Talkie:OnCombatState(inCombat)
  if inCombat then
    Talkie.isInCombat = true
    return
  end

  Talkie.isInCombat = false

  -- send pending invitations
  if Talkie.saved.invitePending then
    Talkie:ChatInviteGroup()
  end
end


------------------------------------------------------------------------------
-- ESO text chat functions - sending and receiveing chat invitations
------------------------------------------------------------------------------

-- send voice chat invitation to group chat channel for everyone
-- Precondition: unit is grouped
-- Precondition: unit is leader
function Talkie:ChatInviteGroup()
  if not Talkie.saved.invite then
    d("Talkie:ChatInviteGroup(): invite is empty")
    return
  elseif not Talkie.saved.isGrouped then
    d("Talkie:ChatInviteGroup(): not grouped")
    return
  elseif not Talkie.saved.isLeader then
    d("Talkie:ChatInviteGroup(): not group leader")
    return
  end

  -- DO NOT interrupt the leader while in combat!!
  -- take a note to come back and do this after combat is over
  if Talkie.isInCombat then
    d("Talkie:ChatInviteGroup(): in combat")
    Talkie.saved.invitePending = true
    return
  end

  d("Send voice chat invite to the group")
  local command = "/group " .. Talkie.saved.preamble .. Talkie.saved.invite
  d(command)

  -- check if command is already there
  local text = CHAT_SYSTEM.textEntry:GetText() or ""
  if command == text then
    d("chat command is already in the chat bar - skipping")
    return
  end

  -- Put command in the chat bar - leader still has to click send
  CHAT_SYSTEM:StartTextEntry(command)
  Talkie.saved.invitePending = false
end


------------------------------------------------------------------------------
-- Discord voice chat interface
-- Any voice chat client interface must implement the following methods:
--    * GroupLeaderSetup()     create channel and invite members
--    * GroupLeaderTeardown()  cleanup channel after chat is over
--    * GroupMemberSetup()     for members to join channel
--     GroupMemberTearDown()  for members to leave channel
-- TODO: abstract this interface to an embedded library (lib/discord.lua)
-- TODO: implement libraries for TeamSpeak and others (lib/teamspeak.lua) etc.
-- TODO: settings panel to select installed chat clients
-- TODO: settings panel to select default (leader) client
-- TODO: group leader dictates which chat client to use
-- TODO: group members discover which cient to use based on invite format
------------------------------------------------------------------------------

-- Group Leader maintains the voice chat invitation for everyone else
-- precondition: player is group leader
-- postcondition: invite is valid and saved invite != nil
function Talkie:GroupLeaderSetup()
  if not Talkie.saved.isLeader then return end
  d("Remember to initialize voice chat channel")
  -- request invite here - remove dummy data below for production
  Talkie.saved.invite = Talkie.saved.leaderInvite
  d("Setting invitation = " .. Talkie.saved.invite)
  Talkie:ChatInviteGroup()
end

-- Group leader needs to clean up after they leave or after the chat is over 
-- precondition: player is group leader and saved invite != nil
-- postcondition: invite is nullified and saved invite == nil
function Talkie:GroupLeaderTeardown()
  if not Talkie.saved.isLeader then return end
  d("Remember to take down your voice chat channel and/or cancel invites")
  -- cancel invites here
  Talkie.saved.invite = nil
end

-- group members use invitation to join chat
-- precondition: invite != nil
-- postcondition: saved invite != nil
function Talkie:GroupMemberSetup(invite)
  d("Follow your invite link to join voice chat: " .. invite)
  -- connect using invite here
  if Talkie.saved.isLeader then return end
  Talkie.saved.invite = invite
end

-- all members need to disconnect when they leave the group
-- postcondition: if not isLeader then invite == nil
function Talkie:GroupMemberTeardown()
  d("Remember to disconnect from voice chat")
  -- disconnect here
  if Talkie.saved.isLeader then return end
  Talkie.saved.invite = nil
end

-- Menu panel definition
function Talkie:CreateSettingsWindow()

  local panelData = {
    type = "panel",
    name = "Talkie",
    displayName = "Talkie Voice Chat Integration",
    author = "motorheadabega",
    version = Talkie.version,
    slashCommand = "/talkie",
    registerForRefresh = true,
    registerForDefaults = true,
  }
  LAM2:RegisterAddonPanel("Talkie_panel", panelData)

  local optionsData = {
    [1] = {
        type = "header",
        name = "Talkie",
        width = "full",
    },
    [2] = {
        type = "description",
        title = "Talkie",
        text = "Talkie Voice Chat Integration using Discord",
        width = "full",
    },
    [3] = {
      type = "editbox",
      name = "Discord voice chat invitation",
      tooltip = "Paste your own group voice chat invitation here. This is the invitation that you will send to others when you are grop leader.",
      getFunc = function() return Talkie.saved.leaderInvite end,
      setFunc = function(text) Talkie.saved.leaderInvite = text end,
      isMultiline = false,
      width = "full",
      warning = "Will need to reload the UI.",
      default = "",   --(optional)
    },
  }
  LAM2:RegisterOptionControls("Talkie_panel", optionsData)
end

 
-- Register Initalization callback
EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_ADD_ON_LOADED, Talkie.OnAddOnLoaded)

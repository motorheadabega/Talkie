Talkie = {}
Talkie.name = "Talkie"
Talkie.version = "1"

function Talkie.OnAddOnLoaded(event, addonName)
  if addonName == Talkie.name then
    Talkie:Initialize()
  end
end

function Talkie:Initialize()

  -- State variables
  self.playerName = GetUnitName("player")
  self.displayName = GetDisplayName()
  self.groupState = self:GetGroupState()
  self.clientState = self:InitClientState()
  self.clientState.invitePending = false
  self.isInCombat = false
  self.invitePending = false

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

-- get full name i.e. charact^er@Display
function Talkie:GetFullName(tag)
  if tag then
    local cn = GetUnitName(tag) or "none"
    local dn = GetUnitDisplayName(tag) or "none"
    return cn .. DecorateDisplayName(dn)
  else
    return "none"
  end
end

-- return all values related to group state in a single table
function Talkie:GetGroupState()
  local g = {}
  g.isGrouped = IsUnitGrouped("player")

  if g.isGrouped then
    g.groupSize = GetGroupSize() or "0"
    g.isGroupLeader = IsUnitGroupLeader("player")
    g.leaderUnitTag = GetGroupLeaderUnitTag()
    g.leaderName = Talkie:GetFullName(g.leaderUnitTag)
  else
    g.groupsize = 1
    g.isGroupLeader = false
    g.leaderUnitTag = nil
    g.leaderName = nil
  end
  return g
end

------------------------------------------------------------------------------
-- ESO Event callbacks
------------------------------------------------------------------------------

function Talkie:OnMemberJoin(name)
  d("OnMemberJoin(" .. name .. ")")
  local new = Talkie:GetGroupState()

  d(name .. " joined the group as a new member")

  if new.isGroupLeader then
    d("as leader I must invite new members to chat")
    Talkie:ChatInviteGroup()
  end

  Talkie.groupState = new -- update global group state
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

  Talkie.groupState = Talkie:GetGroupState() -- update global group state
end

function Talkie:OnLeaderChange(tag)
  d("OnLeaderChange(" .. tag .. ")")
  local fn = Talkie:GetFullName(tag)

  if tag == "player" then
    d("I am now leader")
    Talkie:GroupLeaderSetup()
  elseif Talkie.groupState.isGroupLeader then
    d("I am no longer leader")
    Talkie:GroupLeaderTeardown()
  else
    d(fn .. " is new group leader")
  end

  Talkie.groupState = Talkie:GetGroupState() -- update global group state
end

-- Chat parser - still working up to coding the link handler
function Talkie:OnChatMessage(chan, from, text, isCS, fromDN)
  local channel = false
  if chan == CHAT_CHANNEL_PARTY then
    channel = "group"
  end

  local first = from or "none"
  local last = fromDN or "@none"
  local author = first .. DecorateDisplayName(last)
  local leader = Talkie.groupState.leaderName or "none"

  if channel then
    d(Talkie.name .. ": [" .. author  .. "] " .. channel .. ": " .. text)
    d("Author: " .. author .. ", Leader: " .. leader)
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
  if Talkie.invitePending then
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
  if not IsUnitGrouped("player") then
    d("do not send chat information if you are not grouped")
    return
  end
  if not IsUnitGroupLeader("player") then
    d("do not send chat information if you are not group leader")
    return
  end

  -- DO NOT interrupt the leader while in combat!!
  -- take a note to come back and do this after combat is over
  if Talkie.isInCombat then
    d("do not disturb the group leader while in combat")
    Talkie.invitePending = true
    return
  end

  d("Remember to send voice chat invite to the group")
  local c = Talkie.clientState
  local command = "/group " .. c.preamble .. c.invitation
  d(command)

  -- check if command is already there
  local text = CHAT_SYSTEM.textEntry:GetText()
  if command == text then
    d("chat command is already in the chat bar - skipping")
    return
  end

  -- Put command in the chat bar - leader has to click send
  CHAT_SYSTEM:StartTextEntry(command)
  Talkie.invitePending = false
end


------------------------------------------------------------------------------
-- Discord voice chat interface
-- Any voice chat client interface must implement the following methods:
--    * GroupLeaderSetup()     create channel and invite members
--    * GroupLeaderTeardown()  cleanup channel after chat is over
--    * GroupMemberSetup()     for members to join channel
--    * GroupMemberTearDown()  for members to leave channel
-- TODO: abstract this interface to an embedded library (lib/discord.lua)
-- TODO: implement libraries for TeamSpeak and others (lib/teamspeak.lua) etc.
-- TODO: settings panel to select installed chat clients
-- TODO: settings panel to select default (leader) client
-- TODO: group leader dictates which chat client to use
-- TODO: group members discover which cient to use based on invite format
------------------------------------------------------------------------------

-- initialize client state variables for now until we know more
function Talkie:InitClientState()
  local c = {}
  c.preferredClient = "Discord"
  c.connected = false
  c.invitePending = false
  c.invitation = "test_mock_discord_invitation"
  c.preamble = Talkie.name .. ": [" .. c.preferredClient .. "] "
  return c
end

-- Group Leader is responsible for hosting voice chat channel
-- and for maintaining the invitation
function Talkie:GroupLeaderSetup()
  d("Remember to initialize voice chat channel")
  d("Remember to request invite to channel")
end

-- Group leader needs to clean up after they leave or after the chat is over 
function Talkie:GroupLeaderTeardown()
  d("Remember to take down your voice chat channel and/or cancel invites")
end

-- members use invitation to join chat
-- postcondition: .clientState.connected = true
function Talkie:GroupMemberSetup()
  d("Follow your invite link to join voice chat")
  Talkie.clientState.connected = true
end

-- all members need to disconnect when they leave the group
-- postcondition: .clientState.connected = false
function Talkie:GroupMemberTeardown()
  d("Remember to disconnect from voice chat")
  Talkie.clientState.connected = false
end

 
-- Register Initalization callback
EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_ADD_ON_LOADED, Talkie.OnAddOnLoaded)

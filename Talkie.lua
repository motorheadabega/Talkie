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
  playerName = GetUnitName("player")
  displayName = GetDisplayName()
  groupState = Talkie:GetGroupState()
  clientState = Talkie:InitClientState()
  isInCombat = false
  invitePending = false

  -- Event handlers
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_LEADER_UPDATE, Talkie.OnGroupChange)
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_GROUP_MEMBER_JOINED, Talkie.OnGroupChange)
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_GROUP_MEMBER_LEFT, Talkie.OnGroupChange)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CHAT_MESSAGE_CHANNEL, Talkie.OnChatMessage)
  EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_PLAYER_COMBAT_STATE, Talkie.OnCombatState)
  EVENT_MANAGER:UnregisterForEvent(Talkie.name, EVENT_ADD_ON_LOADED)
end


------------------------------------------------------------------------------
-- ESO helper functions
------------------------------------------------------------------------------

-- return all values related to group state in a single table
function Talkie:GetGroupState()
  local g = {}
  g.isGrouped = IsUnitGrouped("player")
  g.members = {}

  if g.isGrouped then
    d("You are in a group")

    g.groupSize = GetGroupSize()
    g.isGroupLeader = IsUnitGroupLeader("player")
    g.leaderUnitTag = GetGroupLeaderUnitTag()
    g.leaderName = GetUnitDisplayName(leaderUnitTag)
    if g.isGroupLeader then
      d("Your are group leader")
    else
      d("Your are subordinate")
      d("Group leader is " .. g.leaderName)
    end

    -- keep a list of members in the group
    for i = 1,g.groupSize,1 do
      local tag = GetGroupUnitTagByIndex(i)
      g.members[tag] = 1
    end

  else
    d("You are not in a group")

    g.groupsize = 1
    g.isGroupLeader = false
    g.leaderUnitTag = nil
    g.leaderName = nil
  end
  return g
end

function Talkie:OnCombatState(event, inCombat)
  if inCombat then
    Talkie.isInCombat = true
    return
  end

  Talkie.isInCombat = false

  -- delay chat invitations until after combat is over
  if Talkie.invitePending then
    Talkie:ChatInviteGroup()
  end
end

------------------------------------------------------------------------------
-- ESO Event callbacks
------------------------------------------------------------------------------

-- find out what changed in the group
function Talkie:OnGroupChange(event)
  -- start by taking a snapshot of the new group state
  -- we will compare it to the existing state in Talkie.groupState
  local new = Talkie:GetGroupState()
  local old = Talkie.groupState

  -- find out who left
  if event == EVENT_GROUP_MEMBER_LEFT then
    local departures = Talkie:LeftDisjoin(old.members, new.members)
    d("Members left group as follows: " .. table.implode(Talkie:keys(departures), ", "))
    d("groupSize=" .. new.GroupSize)

    -- was I one of them?
    if Talkie:ConfirmKey(departures, "player") then
      d("I left the group")
      Talkie:GroupMemberTeardown()
    end

    -- empty group cleanup
    if new.groupSize == 1 and old.isLeader then
      Talkie:GroupLeaderTearDown()
    end

  -- find out who joined
  elseif event == EVENT_GROUP_MEMBER_JOINED then
    local arrivals = Talkie:LeftDisjoin(new.members, old.members)
    d("New group members as follows: " .. table.implode(Talkie:keys(arrivals), ", "))
    d("groupSize=" .. new.GroupSize)

    -- was I one of them? (remove this clause when invitation is implemented)
    if Talkie:ConfirmKey(arrivals, "player") then
      d("I joined the group. No further action until invite is received")
    end

    -- Leader's job to send invitations to new guys
    if new.leaderUnitTag == "player" then
      d("As leader you need to send invitations")
      Talkie:ChatInviteGroup()
    end

  -- deal with leadership change
  elseif event == EVENT_LEADER_UPDATE then
    d("Leader change from " .. old.leaderName .. " to " .. new.leaderName)
    if new.leaderUnitTag == "player" then
      d("Congratulations on your recent promotion to leader")
      Talkie:GroupLeaderSetup()
    elseif old.leaderUnitTag == "player" then
      d("I was leader and I left the group")
      Talkie:GroupLeaderTeardown()
    end

  end
  Talkie.groupState = new -- update global group state
end

-- Chat parser - still working up to coding the link handler
-- the event parameter (normally at position 1) is not passed - I am concerned
function Talkie:OnChatMessage(chan, from, text, isCS, fromDN)
  local from = IsDecoratedDisplayName(from) and from or zo_strformat(SI_UNIT_NAME, from)

  local channel = false
  if chan == CHAT_CHANNEL_PARTY then
    channel = "group"
  end

  if channel then
    d(Talkie.name .. ": [" .. from .. fromDN  .. "] " .. channel .. ": " .. text)
  end
end

-- track combat state so we can defer sending invitations until after combat
function Talkie:OnCombatState(event, inCombat)
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
  if not Talkie.groupState.isGrouped then return end
  if not Talkie.groupState.isLeader then return end

  -- DO NOT interrupt the leader while in combat!!
  -- take a note to come back and do this after combat is over
  if Talkie.isInCombat then
    Talkie.invitePending = true
    return 
  end

  d("Remember to send voice chat invite to the group")
  local c = Talkie:InitClientState()
  local command = "/group " .. c.preamble .. c.invitation
  d(command)

  -- Put command in the chat bar - leader has to click send
  CHAT_SYSTEM:StartTextEntry(command)
  Talkie.invitePending = false
end


------------------------------------------------------------------------------
-- Primitive helper functions
------------------------------------------------------------------------------

-- return list of keys
function Talkie:keys(set)
  result = {}
  for k, v in pairs(set) do
    table.insert(result, k)
  end
  return result
end

-- determine if a key is present in a table
function Talkie:ConfirmKey(set, key)
  return set[key] ~= nil
end

-- return keys from alist that are not in blist
function Talkie:LeftDisjoin(alist, blist)
  local result = {}
  for k,v in ipairs(alist) do
    if not Talkie:ConfirmKey(blist, k) then
      result[key] = 1
    end
  end
  return result
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
  c.invitation = "http://discord.gg/test_mock_invitation"
  c.preamble = Talkie.name .. ": [" .. c.preferredClient .. "] "
  return c
end

-- Group Leader is responsible for hosting voice chat channel
-- and sending invitations - and they shouldn't forget to connect themselves :)
function Talkie:GroupLeaderSetup()
  d("remember to create voice chat channel")
  d("remember to request invite to channel")
  Talkie:GroupMemberSetup()
  Talkie:InviteGroup()
end

-- Group leader needs to clean up after they leave or after the chat is over 
function Talkie:GroupLeaderTeardown()
  d("remember to destroy your voice chat channel")
end

-- members use invitation to join chat
function Talkie:GroupMemberSetup()
  d("Follow your invite link to join voice chat")
end

-- all members need to disconnect when they leave the group
function Talkie:GroupMemberTeardown()
  d("Remember to disconnect from voice chat")
end

 
-- Register Initalization callback
EVENT_MANAGER:RegisterForEvent(Talkie.name, EVENT_ADD_ON_LOADED, Talkie.OnAddOnLoaded)

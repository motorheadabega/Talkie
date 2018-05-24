# Talkie
ESO AddOn to provide Discord voice chat integration to group play on Elder Scrolls online
## Update
I started this project with the best of intentions and the wide-eyed idealism of a newborn newb. I had expected to be able to communicate using simple REST calls and/or access to shell commands. I had thought luasocket to be part of the lua language, where as it is a user-created library, which is not allowed for use in ESO AddOns. I am not sure what is the complete reason for this, but it probably a very good reason, which I will not contend. I have found that I can pass information out of ESO using saved variables, but this would not provide th functionality I am looking for. This project will be considered closed. I may make one or two more submissions just clean up code and debug statements in case someone ever wants to revive the idea for themselves. Maybe you can succeed where I have failed :) It was still fun.
## Why do we need this?
I have found numerous forum threads going back over several years on which users have pleaded for some kind of (working) Discord overlay support for Elder Scrolls Online. For whatever reason, not much has materialized in the present.
As a result, I am considering the possibility of implementing this as an ESO Addon: because it is in my power to do so, and because it sounds like an interesting challenge.
This Addon is not in a usable state and permission is hereby NOT GRANTED to post it or otherwise make it available on any public download site.
I would, however, welcome some help testing it to bring it to fruition. The kind of help I am talking about is hanging out in-game, grouping and ungrouping, and observing different behaviours - at least until we are ready to hook into Discord REST API to make the actual voice connections. Contact me on Github if you would be interested.
## What will be required to make it work?
* each user must have an account on Discord (at least initially - I am already thinking about ways to abstract this to support multiple chat clients, although everyone in a group would have to support the same client)
* each user must have their own server on Discord (it's free)
* each user must have Manipulate Channels permission on their server
* Discord user information will be stored in the addon settings
## How will it work?
### When a player first becomes group leader
Group leader's addon will greate a new temporary (disposable) voice chat channel on their Discord server and generate an invite url to that specific voice chat channel only. The leader will send a group chat message in-game containing the invite.
* invite must be sent manually
The addon can only populate the command bar with the contents of the message. The group leader will have to pause what they are doing long enough to press enter to send it. This is a limitation of the addon API intended to discourage spam and I am in complete agreement with the intent of this limitation. For example I have already mapped the enter key to a button combination on my Steam Controller and it works OK in my own testing so far.
* invite will be clearly marksed as coming from this app 
I want people to be able to easily filter it as spam if they don't want to receive it.
### When a player first receives a voice chat invitation
The player must be in a group and the message must come from the current leader of the group and the invitation must conform to the general pattern of an invitation for the appropriate client (http://discord.gg/something for Discord for now). The addon will follow the link for each member of the group to facilitate the connection.
At this point the group should be together on voice chat.
### When a player leaves the group
They are disconnected from the voice chat
### When the leader leaves the group or the group becomes empty
The temporary (disposable) voice chat channel will be deleted. Partly to keep unxanted former chat sessions from piling up
, but also to render to oustanding invitaions useless (for privacy and security concerns)
### When the leader leaves a remaining party of 2 or more
The previous leader (that just left) will leave the voice chat and tear down the channel as described above.
Once the new leader receives notification of their new position, their addon will create a new voice chat channel and send invitation to remaining members and chat goes on.
The delay in this process will depend on how quick the new leader is to send the new invitations
## Installation
Current installation is a ssimple as cloning this repository in the following directory:
* C:\Users\<your_username>\Documents\Elder Scrolls Online\live\AddOns\
## Next Steps
As I learn more about how to competently write md documents, I will flesh out the documentatio and move a lot of this stuff out to supporting documents.


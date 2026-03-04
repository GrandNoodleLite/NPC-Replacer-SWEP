# NPC-Replacer-SWEP
This is a SWEP that lets you replace the NPC you are looking at. Left click while looking at an NPC disintegrates it and spawns a replacement NPC in the exact location of the old one. Right click opens a menu that allows you to customize the properties of the replacement NPC and save presets that you can easily swap between. You can also press R to just disintegrate an NPC if you just want to see it fizzle out without a replacement.

_Customization:_

In addition to setting the npc class, there are also a few optional settings you can configure for a replacement NPC. You can set a specific model, what weapon it spawns with, and the health the replacement NPC has.

_Don't know npc class names, model file paths, or the name of an NPC's weapon? No problem!_

Each field has a button next to it that allows you to just copy another NPC! Want an exact copy of an NPC? There's a button that lets you copy all the settings from another NPC in one click! How does copying work? Click on the "Copy from Target" button next to the setting you want to copy or click the "Copy All from Target" button in the menu. You'll then go into "Copy Mode" and see a big popup that tells you exactly what you need to do, which is to left click on an NPC to copy (don't worry, the SWEP won't replace or remove any NPCs when you're in copy mode). When you click on an NPC in copy mode, the menu will pop back up automatically filled with whatever you wanted copied.

_What do the other buttons in the right click menu do?_

Clear: Clears all the fields.

Save: Lets you save the current settings as a preset. You will be asked to name it.

Delete: When a preset is selected from the drop-down menu, it will delete it. The preset needs to be selected for it to be deleted!

**And most importantly...**

**Apply: Applies the settings/config to the Replacer SWEP. ANY changes you make, including switching saved profiles, will not take effect until you click "Apply"! The background of the Apply button will even turn red when you have made changes that haven't been applied! This way, you can click the X button to close the menu, look through the Q menu for npc classes, models, and weapons to get information for these fields that way, or do other things in game without being forced to use a config for the replacement NPCs that isn't complete. So again, YOU NEED TO CLICK APPLY FOR ANY CHANGES, INCLUDING PROFILE SWAPS, TO TAKE EFFECT!**


This was originally going to just be a quick script I had AI make, but I ended up spending more time playtesting it and asking for more features than I thought I would, so I figured others might be interested in it too.


_FAQ:_

_Couldn't I just press Z (Undo) or use the remover tool and spawn in NPCs with the Q menu?_

Sure! But I like to play on maps and use mods that spawn waves of enemies to fight. Even for NPCs you spawn yourself, if you want to replace an NPC that you spawned a long time ago, and you've spawned other props or entities since, you either need to press Z (Undo) a bunch of times and delete NPCs or props you might want to keep, or use the remover tool, then go into the Q menu, set the weapon override for an NPC if you want a specific weapon, then disable it if you don't want future NPCs to use that weapon override. This SWEP lets me quickly replace NPCs with saved profiles instead.

_Where is the SWEP in the Q Menu?_

Open Q Menu - Weapons - GrandNoodleLite's Weapons

_Does this work in multiplayer?_

I exclusively tested it in singleplayer cause that's where I use it. If it does, you probably want an addon that will restrict who can use it. It could lead to other players replacing NPCs they didn't spawn. Also, since the replacement NPCs aren't spawned by a player they can't be deleted with the Z (Undo) key, you wouldn't be able to tell who spawned the replacement NPCs. Oh, and it could be used to bypass NPC spawn limits.


_Which AIs did you use to make this SWEP and how much work did you really do on this SWEP?_

Grok, and Claude depending on usage limits. I spent time troubleshooting lua errors, thinking of more features to tell the AI to add, and playtesting the changes that were made with each version.

_Can you update/add something to this tool for me?_

No. I wasn't even planning on releasing this initially. I'm only publishing it now because I spent WAY too long on it and since I spent all this time on it I might as well post it and hope someone else finds it cool/useful too. ¯\_(ツ)_/¯

_Can I change/improve this addon and upload my own version?_

Sure. Ultimately, AI made the code. I'm going a step further by posting this on github to help you get started! Change it yourself or shove it into your favorite AI with your own ideas and see what pops out!

If you want to support the project feel free to donate here:
paypal.me/Efinix


Efinix Classic UI
=================

Brings the original 2004-2006 Vanilla interface back to World of Warcraft: Forever:
the carved main bar with gryphons, the small 36 px action buttons, the purple XP bar,
the old micro menu and bag buttons, the old player/target/pet/party frames, the
thin yellow cast bar, the round minimap with its sun/moon icon, buffs and debuffs
in the top right corner, the old chat frame with its scroll buttons, the dark blue
tooltips, the classic nameplates, the old spellbook and loot window, a weapon swing
timer, a classic-styled all-in-one bag window, unit frames you can drag wherever
you like, and an optional dark mode for all the frame art.


INSTALL
-------

1. Download the newest zip from the "Releases" page (right side of the GitHub page).
   Do not use the green "Code" button, that download has the wrong folder name.
2. Unzip it. You get one folder called "Efinix_Classic_UI".
3. Move that folder into
   World of Warcraft\_classic_beta_\Interface\AddOns\
   (or _classic_ once Forever has launched).
4. Start the game and enable "Efinix Classic UI" in the AddOns list at the
   character screen. If it is marked as out of date, tick "Load out of date AddOns".


COMMANDS  (type them in the chat box)
--------

/fcui                       opens the options window (turn parts on or off, bar scale,
                            minimap size, nameplate size, bag columns). Also found
                            under Options > AddOns.
/fcui status                shows what is running and which old textures are missing
/fcui missing               lists only the old texture files your client does not have
/fcui move                  shows green boxes on the player, target, focus and pet
                            frames; drag them where you want, then type /fcui move
                            again to lock them
/fcui move reset            puts the frames back to their default places
/fcui bags columns 12       how many item slots per row in the bag window (4-20)
/fcui bags bankcolumns 14   same for the bank window (4-24)
/fcui bags selljunk         sells all grey items (only at a vendor)
/fcui bags shiftsell off    turns the hold-Shift auto sell and repair off (on = back on)
/fcui scale 1.1             makes the whole bottom bar bigger or smaller (0.5-2.0)
/fcui dark on               dark mode: all frame art (bars, unit frames, minimap,
                            chat, tooltips, windows) and the game's own windows (quest,
                            gossip, vendor, character, mail, trainer, ...) tinted dark
                            grey; quest and book text get the game's dark "quest text
                            contrast" background with light text; "off" undoes it.
                            Also a checkbox in the options window.
/fcui disable Bags          turns a part off. Parts: ActionBars, UnitFrames, CastBar,
                            SwingTimer, Minimap, Auras, Chat, Tooltip, Nameplates,
                            RaidFrames, LootFrame, SpellBook, Bags, Vendor.
/fcui enable Bags           turns it on again. Both need /reload afterwards.
/fcui reset                 forgets all settings, then /reload


GOOD TO KNOW
------------

Minimap: the clock, the calendar button and the addon button are hidden like in
2006. Click the sun/moon icon at the top right of the minimap to open the calendar.
The tracking icon left of the minimap still opens the tracking menu.
Chat: the chat tabs only appear while your mouse is over the chat frame, as they
did back then. If your text box sits at the top of the chat frame, set
"Chat Style" to "Classic" in the Interface options.
Swing timer: thin yellow bars above the cast bar show your main hand, off hand
and ranged auto-attack timers, using the game's own swing timer dressed in the
old cast bar look. Type /fcui disable SwingTimer if you do not want it; that also
switches the game's swing timer setting back to what it was. Edit Mode lets you
choose whether the bars show always or only in combat.
Nameplates: the addon draws the flat 2006 plate (coloured bar, thin black frame,
level to the right) and switches off the game's shrinking of far-away plates, as
there was none back then. "Nameplate size" in the options makes them bigger or
smaller. Turning the Nameplates part off (or removing the addon after
/fcui disable Nameplates) puts your old nameplate settings back.
Minimap: "Minimap size" in the options scales the whole minimap cluster; the
buffs move left to make room.
Raid frames: the modern compact raid frames are hidden. Use the raid tab of the
social window and drag groups out of it, as in 2006.
Spellbook: P (or the spellbook button in the micro menu) opens the old two-page
book with the skill tabs on the right. Drag spells to your bars as usual. It opens
and closes in combat too, and Escape closes it. Clicking a spell in the book casts
it, except during combat, where the game only lets you look, read tooltips and
drag; casting from the book is back the moment the fight ends.
Loot window: the small 2006 loot panel with four item slots and page arrows
opens at the top left, or under the mouse if you have that option turned on.
The options window (/fcui) lets you turn the spellbook and loot window off
if you prefer the game's own versions.
Edit Mode still works for things the addon does not manage. The addon puts the
player, target, focus, pet, cast bar, swing timer, chat and tooltip frames in
their 2006 places, but as soon as you drag one of them in Edit Mode and save,
it stays where you put it. "Reset to default" in Edit Mode brings the 2006
position back.


BAGS
----

Press B or click the backpack as usual, everything opens in one window.
Click a bag icon at the top of the window to hide or show that bag's slots.
Hover a bag icon (in the window or on the bottom bar) to light up the slots that
belong to that bag. The keyring only shows the rows that hold keys.
Type in the search box to dim everything that does not match.
"Sort" tidies the bags. Drag the window by its border to move it.
The coin icon next to "Sort" sells all grey junk while a vendor is open; the same
icon sits next to the repair buttons in the vendor window. Holding Shift for about
one second at a vendor sells all junk and repairs all your gear automatically.
These vendor features are their own part ("Vendor" in the options), so they keep
working when the bag window is turned off.
At a banker the bank window opens next to it. Buying new bank tabs is done
through the "Blizzard bank" button in the bank window.


PROBLEMS
--------

If something looks wrong or you get an error, please open an issue on the GitHub
page and include the text of /fcui status and, if you have it, the error from
BugSack. Screenshots help a lot.


LICENSE
-------

MIT. See the LICENSE file.

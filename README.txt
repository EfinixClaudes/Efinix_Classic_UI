If you want to support the project feel free to donate here:
paypal.me/Efinix


Efinix Classic UI
=================

Brings the original 2004-2006 Vanilla interface back to World of Warcraft: Forever:
the carved main bar with gryphons, the small 36 px action buttons, the purple XP bar,
the old micro menu and bag buttons, the old player/target/pet/party frames, the
thin yellow cast bar, the round minimap with its sun/moon icon, buffs and debuffs
in the top right corner, the old chat frame with its scroll buttons, the dark blue
tooltips, the classic nameplates, a classic-styled all-in-one bag window and
unit frames you can drag wherever you like.


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

/fcui                       shows the command list
/fcui status                shows what is running and which old textures are missing
/fcui move                  shows green boxes on the player, target, focus and pet
                            frames; drag them where you want, then type /fcui move
                            again to lock them
/fcui move reset            puts the frames back to their default places
/fcui bags columns 12       how many item slots per row in the bag window (4-20)
/fcui bags bankcolumns 14   same for the bank window (4-24)
/fcui bags selljunk         sells all grey items (only at a vendor)
/fcui bags shiftsell off    turns the hold-Shift auto sell and repair off (on = back on)
/fcui scale 1.1             makes the whole bottom bar bigger or smaller (0.5-2.0)
/fcui disable Bags          turns a part off. Parts: ActionBars, UnitFrames, CastBar,
                            SwingTimer, Minimap, Auras, Chat, Tooltip, Nameplates,
                            RaidFrames, Bags.
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
Nameplates: the addon switches the game's nameplate style to its hidden "Classic"
look. Turning the Nameplates part off (or removing the addon after
/fcui disable Nameplates) puts your old style back.
Raid frames: the modern compact raid frames are hidden. Use the raid tab of the
social window and drag groups out of it, as in 2006.
Edit Mode still works for things the addon does not manage; positions and sizes
of the frames listed above are set by the addon, except the chat frame and the
tooltip, which keep a position you gave them in Edit Mode.


BAGS
----

Press B or click the backpack as usual, everything opens in one window.
Click a bag icon at the top of the window to hide or show that bag's slots.
Type in the search box to dim everything that does not match.
"Sort" tidies the bags. Drag the window by its border to move it.
The coin icon next to "Sort" sells all grey junk while a vendor is open; the same
icon sits next to the repair buttons in the vendor window. Holding Shift for about
one second at a vendor sells all junk and repairs all your gear automatically.
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

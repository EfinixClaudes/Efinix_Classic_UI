If you want to support the project feel free to donate here:
paypal.me/Efinix


Efinix Classic UI
=================

Brings the original 2004-2006 Vanilla interface back to World of Warcraft: Forever:
the carved main bar with gryphons, the small 36 px action buttons, the purple XP bar,
the old micro menu and bag buttons, a classic-styled all-in-one bag window and
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
/fcui scale 1.1             makes the whole bottom bar bigger or smaller (0.5-2.0)
/fcui disable Bags          turns a part off. Parts: ActionBars, UnitFrames, Bags.
/fcui enable Bags           turns it on again. Both need /reload afterwards.
/fcui reset                 forgets all settings, then /reload


BAGS
----

Press B or click the backpack as usual, everything opens in one window.
Click a bag icon at the top of the window to hide or show that bag's slots.
Type in the search box to dim everything that does not match.
"Sort" tidies the bags. Drag the window by its border to move it.
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

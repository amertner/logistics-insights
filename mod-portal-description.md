# Logistics Insights

When playing Factorio, have you ever wondered what all of your logistics bots are up to? Whether you have too many, or too few? Whether you have enough storage? Particularly in the mid game where everything is scaling up, I've found that the answers sometimes are quite surprising.

Logistics Insights can help:

- Provides actionable insights on what to do to improve your network, based on how it's performing
- Undersupply: Shows a list of the top things where demand consistently outstrips supply
- Multi-network: Helps you keep an eye on your key networks and easily navigate between them
- Multi-player: When you work together on a base, you can keep track of and help each other
- Real-time: Shows what's happening in your networks real time
- Interactive: Most things are clickable so you can easily get to the root of whatever the issue is

## Quick info available

In the top left corner of the screen, you'll see two icons.
![QuickInfo](https://assets-mod.factorio.com/assets/a7748701a84ca1c61fa6bf249f8f362252d8077f.png)

- The lightbulb shows how many Suggestions you have across all of the networks being analyzed. Click this button to open/close the Networks window where you can see more detail.
- The logistics bot shows how many logistics bots are idle in your current network. If this gets to 0, you most likely don't have enough. Click this button to open the Logistics Insights window to see much more detail about the network.

## The two main windows

The main Logistics Insights window focuses on showing everything you need to know about a single bot network at a time, whether it's the one where you are or one you're looking at via the map view.
![main-window](https://assets-mod.factorio.com/assets/a5aabefdc59d2795e402a39cf62019bfd2c608e0.png)

The Logistics Networks window shows all of the networks you've visited, with a few key highlights like number of bots, number of active suggestions and how many things are in short supply. You can also easily navigate between networks from here. Clicking the gear icon opens the Logistics Insights window with the settings pane below.
![Networks-window](https://assets-mod.factorio.com/assets/8dc5ad9fae2043276ba940d747e53e1d35df5169.png)

The main window supports the *Pipette action* ("Q" by default), which allows you to pick up a ghost of an entity shown. This is useful if you need to build or search for that item, for example using Factory Search.

When the settings pane is open (you can also open it with the settings icon next to the Network row), you can see and edit the settings that apply to the current network.
![Settings-pane](https://assets-mod.factorio.com/assets/f7b40b8fca1b4b163d79e7185f805ab937887146.png)

## How to use Undersupply information

In the Undersupply row, you can see items that have more demand than can be supplied in the network. This is useful to identify hard-to-spot bottlenecks.
![Undersupply](https://assets-mod.factorio.com/assets/46066c3567a4829c276b2992d91007fd367474a7.png)

If you click on an item, LI will highlight every place that requests the item, and if you right-click, it will also zoom in and focus the map view on one of them. You can repeatedly right-click to get a sense for where the problems are.

If an item is shown in undersupply but you don't want to track it, you can Shift-click on the icon to ignore that item type in the current network. I find this useful when I have requests for "accidental" items that I want to capture somewhere, but where there is no real shortage.

## How to use Suggestions

There are several types of suggestions, depending on what is happening in your network:

- **Build more roboports.** A common problem is that a lot of your bots are waiting to charge, which means that fewer bots are free to do useful work. Building more bots doesn't help though! Instead, build more roboports so the bots can quickly find a place to charge, without having to wait. LI will show this as a High priority suggestion if you need more than 100 additional roboports.
![Suggest-RPs](https://assets-mod.factorio.com/assets/238554f7b48bbe2e7dba8e70e6a2866693fbba10.png)
- **Build more storage.** If your storage is close to full, your network will work less efficiently as bots need to go further to find available storage. This suggestion shows up when your storage is 70% full, and becomes High priority when it's 90% full. Note that "fullness" of storage is measured by stacks, so you may have more storage available than LI suggests as it only looks for empty stacks. A network with no storage chests at all is told so instead; if that is how you want it, for a mall or an outpost say, tick *Ignore when no storage* in the network settings.
- **Build more unfiltered storage.** Filtered storage is great, but you may be running out of storage that isn't filtered. LI uses the same thresholds as for total storage here, and only makes this suggestion when some of your storage has a filter; without any, it would just repeat the one above.
![Suggest-more-storage](https://assets-mod.factorio.com/assets/9707bae6b868bfb1837c40e58d13f35bf3c025ab.png)
- **Filtered storage mismatch.** If your filtered storage has items that don't match the filter, LI suggests you fix it. You can click/right-click on the suggestion to see which chests show the problem, which is otherwise hard to find. If a mismatch doesn't matter to you, you can Shift-click on the cell to ignore the chests in question from flagging a mismatch.
![Suggest-filter-mismatch](https://assets-mod.factorio.com/assets/dc2015a3a1bce8a8d937eca847ef93308bc13daf.png)
- **Too few bots**. Sometimes, you just don't have enough bots to do everything, and you might get this suggestion. It needs a network of at least 20 bots that have been 98% busy for a minute, and it stands down while bots are queuing to charge, because building more bots then only lengthens the queue.
![Suggest-more-bots](https://assets-mod.factorio.com/assets/1a78eaf3acfcf5eb9d98c855c5ec6992f4395a65.png)
- **Too many bots**. If more than half your bots are idle, but you are still adding more new bots, LI will suggest that you stop adding more bots.
![Suggest-fewer-bots](https://assets-mod.factorio.com/assets/da50c7d52869836dc29f2721151af41def969a24.png)
- **Items carried unusually far.** If bots regularly carry an item much further than they usually do, e.g. to an outpost when the item mostly goes to a nearby mall, LI suggests a supply closer to that destination, or a belt or train. Click the suggestion to see the trip on the map. If the long trip is expected, Shift+click to exclude it. Trips to players and spidertrons are left out by default, as they go wherever the player is; a setting turns that off. How far is far enough to be worth mentioning depends on the base, so the minimum distance and the sensitivity are both settings, and the suggestion can be turned off entirely. This suggestion uses the delivery history, so it only appears for networks you have viewed with the History rows shown.

## How to keep an eye on things

Before a base reaches megabase level, keep the Networks window open to keep an eye on whether there are a lot of things in Undersupply or Suggestions. Then, if there is an issue, click on the network to immediately move the map view there and see the main Insights window:

**In the Delivering/Totals/Distance carried/Longest trip rows**

- If there is some item that's being transported unnecessarily (i.e. it shows up early in the Totals list), perhaps could belt that item instead. For example, in one case I found that my bots were transporting iron ore 90% of the time, filling up my storage chests, all because I accidentally put ore in an active provider chest.
- Distance carried shows which items take up most of your bots' work: the total distance bots have flown carrying each one. The items at the top are the best candidates for belts or trains, or for a source closer to where they're needed.
- Longest trip shows the items that bots carry furthest from pickup to delivery in one go. A long trip can be hidden among many short ones, e.g. iron plates carried a few metres to a mall and occasionally hundreds of metres to an outpost, so look for items with an average trip much higher than the median. Distances are shown in metres and kilometres; one tile is one metre. A distance shown with a tilde, like ~435 m, is an estimate: the bot was first seen already carrying the item, so the trip is at least that long.
- Click an item in Longest trip to show the destinations of up to 5 of its longest trips on the map, one at a time, and right-click to show where the trip being shown starts. If a long trip is expected, Shift+click to exclude it; excluded items and destinations can be managed in the network settings. For an item that is needed a bit here and a bit there, Ctrl+Shift+click ignores its trips to every destination; ignored items have their own list in the network settings.
- Sometimes, a small number of items are delivered a long way, cluttering up the statistics. Click the trash button next to a History row to clear the delivery history and start again.
- If you don't need part of the display right now, click the pause button to temporarily pause collecting it. Or change the setting to remove the History, Undersupply or Suggestions rows entirely, which also makes the window smaller.

**In the Activity row**
![Activity-Network](https://assets-mod.factorio.com/assets/fde1dd48cfe0fb3945aff89739c2820dad4f88ed.png)

- If too many bots are "waiting to charge", you'll get a "Build more Roboports" suggestion
- If too few bots are "available", you'll need to add more bots. A suggestion will show this.
- If most of the bots are "available", you can probably stop adding more bots. If you continue adding bots to a network where most of them are idle, you'll get a suggestion that you stop adding more.

**In the Network row**

- If I'm trying to update my bots to a higher quality level, this makes it easy to see how many are still at the lower level
- If I've upgraded my bots to a higher level, but my roboports are low quality, charging will take much longer. Upgrade them asap!

## Settings

Logistics Insights has several settings that are on a per-map basis. These allow you to control what data is gathered and whether you allow freezing the game; since all data gathered is global to all players, these are configured for everyone. They come in four groups: what is gathered (quality data, undersupply, player requests, whether data is kept for networks nobody is in), the suggestions (how long a resolved suggestion lingers, what counts as a long trip, whether trips to players count), performance (chunk size, ticks between chunks, the two analysis divisors and the background refresh interval) and, on its own, whether highlighting freezes the game.
![Per-map settings](https://assets-mod.factorio.com/assets/bb2e582531443b2676f73174d7896c3474c91c48.png)

There are also player-specific settings that allow each player to configure what is displayed on their screen: which rows to show, how many columns, the two mini windows, how long highlights stay, the zoom level, and whether estimated trip starts are drawn. Showing the History rows is also what makes LI record history for the network you are in.
![Per-player settings](https://assets-mod.factorio.com/assets/d1e4718cf48b85ecbdca9f5ef7fb92c3dc3c681f.png)

While in the game, there are settings that apply to individual networks and allow you to fine tune what is collected and suggested at that level. To access this, click the gear icon next to the Network row in the main window, which opens a settings pane below the main window. This is where the ignore lists live (chests for the filter mismatch, items for undersupply, and destinations and items for long trips), along with whether higher-quality items count as a filter mismatch, whether buffer chests count as demand, and whether a network without storage should be told so.
![Network settings](https://assets-mod.factorio.com/assets/cf39de1498ab45cd64a47483ec40210b7a4fbc3e.png)

In all cases, LI is aware of which settings are changed, and allows you to revert to defaults in the standard Factorio way.

## How Logistics Insights minimises its overhead

What Logistics Insights does takes time, and for very large bot networks can cause the game to slow down. The mod is written to mitigate this by processing the bots, network items, etc. in chunks, so it only processes a small portion of the whole each tick. The default *chunk size* is 400, but you can change this.

It is tempting to lower the chunk size to reduce the load, but that is the wrong way round: a larger chunk is cheaper per bot, because the fixed cost of a pass is spread over more of them, and it gives a more consistent picture, because every bot in a chunk is seen at the same moment. The mod copies the full list and processes it one chunk at a time, so with small chunks the game state moves on between the first chunk and the last. The only cost of a large chunk is that all its work lands in one tick; lower the size only if that shows up as stutter.

A progress indicator shows the chunk processing in action, and the chunks apply both bots, roboports, undersupply and suggestions. For example,

- If you have 1,800 bots and use the default chunk size of 400, it will take 5 passes before the bot data showing Delivering and History (Totals, Distance carried and Longest trip) is updated. A pass is done every 7 ticks, or around 10 times per second.
- If you have 900 roboports with the default chunk size, it will take 3 passes before the Activity data about your bots is updated (showing Available, Charging, Waiting, Picking Up or Delivering).
- Undersupply and the storage analysis are more expensive per entity, so they use the chunk size divided by the *Analysis* divisor, 4 by default. If you have 1,100 requesters and a chunk size of 400, each analysis chunk is 100 requesters and the pass takes 11 chunks; the undersupply sampling below then cuts that further.

If you have fewer items than the chunk size, the data will be updated on every pass, keeping the data more accurate, though its polling-based nature means it will rarely be 100% accurate. Good enough though!

On a powerful machine, you can easily have a chunk size of 1,000 or more, and process data every 3 ticks. On a less powerful machine, you may want to process fewer items at a time, less often.

From v0.10, Logistics Insights uses a custom scheduler that smooths the load across many ticks, allowing you to get up to date information even with many networks and several players, without suffering a noticeable performance impact on the game.

Five settings control the tradeoff between how current the information is and CPU load: the chunk size and the ticks between chunks described above, the background refresh interval (how often networks nobody is looking at are scanned and analysed), and two that apply to the analysis steps only:

- *Undersupply: requesters checked per scan (1/N)* (default N=3) instructs LI to only sample 1/Nth of requesters in a network when it's scanned. This makes sense because scanning of requesters is expensive, yet requesters don't often change their request sizes. Requesters that are controlled by circuit network are always scanned on every cycle.
- *Analysis: split each chunk into N* (default 4) sets the chunk size used for the analysis steps (undersupply and storage). If your chunk size is 400 (used to scan the bots) and N is 4, each analysis chunk is 100 entities. A larger N spreads the analysis over more ticks, so each tick does less work and the answer takes longer to arrive.

## What's next?

There are many ways in which this mod could become more useful, and I'll be looking for feedback on what you'd like to see. Here are some of my ideas:

### Main window

- Maybe it would be useful to step forward more than one tick at a time. Should there be a "step 10-ticks" button, or maybe a config option?
- The main window right now is floating, which means you can position it anywhere, but it also means it might open overlapping with something else. Should it instead stick to the top or left sides? Should it be an option?
- The max number of items that can be shown in Delivering/history is 10. Would more be useful?

### Highlighting items

- When highlighting bots, it might be useful to show info about where each bot is going. Maybe an arrow pointing to the destination?
- When clicking on a category to highlight them, there is no limit to how many items are shown. It's possible that this needs to be limited to 1,000 or something so the game doesn't grind to a halt if you have a lot of items, so maybe an option is in order.
- When highlighting a group of items, maybe it would be useful to set zoom level to include as many of them as possible, and focus somewhere around the middle?

### Completely new functionality

- When focusing on a single bot (with right-click in a cell like Delivering), it might be fun to have a "follow" window that allows you to see where it's going.
- I'd love to show a heat map of activity on the mini map, but I can't see a way for a mod to do this. Do you know how?
- Maybe it would be useful to also show what Construction Bots are doing? Not sure about that, maybe that's another mod!

## Factorio 2.0 and 2.1

Factorio only loads a mod marked for the game version it is running, so every release of Logistics Insights is published twice with identical code: 1.2.x for Factorio 2.0 and 1.3.x for Factorio 2.1, with the same last number in both, so 1.2.5 and 1.3.5 are the same release. The in-game mod browser offers the right one for your game. Both zips are produced by `build.sh` from the same source.

## Known issues

- The game may desync in multiplayer if players join the server while the Logistics Insights mod is upgrading to a new version. Please wait a second or two for this to complete and it should be fine for other players to join the game.

## Want to contribute?

I value contributions, even if it's just a forum post to say what you like or don't like about the mod :)

If you want to contribute functionality or bugfixes, please create a pull request on [Github](https://github.com/amertner/logistics-insights).

You can also create an issue if you find a bug or have an idea for a feature, either on Github or on the Factorio Mod Portal.

## Translation

The mod is currently available in **English** and **Danish**, but it's easy to contribute even just a few strings. Go to [This project](https://crowdin.com/project/factorio-mods-localization), pick the language you'd like to contribute to, and find the Logistics Insights mod. Translations will show up in the game later, typically about a week.

## Thanks

These people helped me with code and inspiration:

- [Xorimuth](https://mods.factorio.com/user/Xorimuth) for the excellent [Factory Search](https://mods.factorio.com/mod/FactorySearch) mod and code to highlight items on the map
- [raiguard](https://mods.factorio.com/user/raiguard) for [Stats GUI](https://mods.factorio.com/mod/StatsGui) in particular
- [justarandomgeek](https://mods.factorio.com/user/justarandomgeek) for the brilliant [mod debugger](https://github.com/justarandomgeek/vscode-factoriomod-debug)
- [Qon](https://mods.factorio.com/user/Qon) for [Pause Combinator](https://mods.factorio.com/mod/PauseCombinator), which gave me the idea for the freeze functionality
- [HermanyAI](https://mods.factorio.com/user/HermanyAI) for [Item Cam 2](https://mods.factorio.com/mod/item-cam-2), which I thought I could use but ultimately didn't...

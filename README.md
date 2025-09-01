# Logistics Insights

When playing Factorio, have you ever wondered what all of your logistics bots are up to? Whether you have too many, or too few? Is your storage nearly full? Do you have enough roboports? Particularly in the mid game where everything is scaling up, I've found that the answers sometimes are quite surprising.

Logistics Insights can help:

- Shows suggestions for what to do to improve performance: Add roboports, add storage, review filtered storage, etc
- Shows Undersupply: A list of the top things where demand outstrips supply
- Shows all of the networks you've visited so you can keep an eye on them
- Shows a list of the top items being carried in real time
- Shows a sorted list of items that have been delivered the most
- Shows a list showing the items that took the longest to deliver
- Shows what your bots are doing: Idle, charging, waiting to charge, picking or delivering
- Shows what entities you have in your bot network: roboports, requesters, providers, etc.
- Shows the quality level of your bots and roboports.
- With a click, can highlight all entities or bots doing a particular activity, making it easy to find them
- When highlighting bots, the game temporarily freezes, allowing you to inspect the state of things
- You can freeze and single-step the game manually as well
- You can easily pause parts of the monitoring to reduce impact on game speed
- Hide and show the main window by clicking the "logistics bot icon window" that's always open, or use the shortcut icon
- Either analyse the network you're looking at, or keep analysing a specific one

The main Logistics Insights window focuses on a single bot network at a time, whether it's the one where you are or one you're looking at via the map view.

The Logistics Networks window shows all of the networks you've visited, with a few highlights like number of bots, number of active suggestions and how many things are in short supply. You can also easily navigate between networks with this screen.

## How to use Undersupply information

In the Undersupply row, you can see items that have more demand than can be supplied in the network. This is useful to identify hard-to-spot bottlenecks.

If you click on an item, LI will highlight every place that requests the item, and if you right-click, it will also zoom in and focus the map view on one of them. You can repeatedly right-click to get a sense for where the problems are.

## How to use Suggestions

There are several types of suggestions, depending on what is happening in your network:

- **Build more roboports.** A common problem is that a lot of your bots are waiting to charge - and building more bots doesn't help. Instead, builid more roboports so the bots can quickly find a place to charge, without having to wait. LI will show this as a High priority suggestion if you need more than 100 additional roboports.
- **Build more storage.** If your storage is close to full, your network will work less efficiently as bots need to go further to find available storage. This suggestion shows up when your storage is 70% full, and becomes High priority when it's 90% full.
- **Build more unfiltered storage.** Filtered storage is great, but you may be running out of storage that isn't filtered. LI uses same thresholds as for total storage here.
- **Filtered storage issue.** If your filtered storage has items that don't match the filter, LI suggests you fix it. You can click/right-click on the suggestion to see which chests show the problem.

Note that "fullness" of storage is measured by stacks, so you may have more storage available than LI suggests as it only looks for empty stacks.

## How else I started using the mod

Before a base reaches megabase level, keep the LI window open to keep an eye on whether you have the right number of bots and roboports. If it gets in the way, just close it and occasionally open it to see what's going on.

**In the Delivering/Total/Ticks rows**

- If some items take a disproportionate amount of time to deliver (i.e. they show up early in the Ticks/item list), consider transporting those using belts instead, or creating a source of items closer to where it's needed
- If there is some item that's being transported unnecessarily (i.e. it shows up early in the Totals list), perhaps could belt that item instead. For example, in one case I found that my bots were transporting iron ore 90% of the time, filling up my storage chests, all because I accidentally put ore in an active provider chest.
- Sometimes, a small number of items are delivered a long way, cluttering up the Ticks/item statistics. Right-click on one of the buttons to clear the history and start again.
- If you don't need part of the display right now, click the pause button to temporarily pause collecting it. Or change the setting to remove the rows entirely, which also makes the window smaller.

**In the Activity row**

- If too many bots are "waiting to charge", you'll get a "Build more Roboports" suggestion
- If too few bots are "available", you'll need to add more bots
- If most of the bots are "available", you can probably stop adding more bots

**In the Network row**

- If I'm trying to update my bots to a higher quality level, this makes it easy to see how many are still at the lower level
- If I've upgraded my bots to a higher level, but my roboports are low quality, charging will take much longer. Upgrade them asap!

## Performance and chunking

What Logistics Insights takes time, and for very large bot networks may cause the game to slow down. The mod is written to mitigate this by processing the bots and network items in chunks. The default chunk size is 400, but you can change this.

By lowering the chunk size, you reduce the performance impact of Logistics Insights, at the expense of getting results that are not entirely accurate.  This is because the mod copies the full list of items and processes it one chunk at a time, which means that the game state may have changed by the time it finishes processing the full list.

A progress indicator shows the chunk processing in action, and the chunks apply to both bots and roboports. For example,

- If you have 1,800 bots and use the default chunk size of 400, it will take 5 passes before the bot data showing Delivering and History (Total and Ticks/Item) is updated. A pass is done every 10 ticks, or 6 times per second.
- If you have 900 roboports with the default chunk size, it will take 3 passes before the Activity data about your bots is updated (showing Available, Charging, Waiting, Picking Up or Delivering). A pass is done every 10 ticks if Delivery or History is enabled, and every 60 ticks otherwise.

If you have fewer bots or roboports than the chunk size, the data will be updated on every pass, keeping the data more accurate.

On a powerful machine, you can easily have a chunk size of 1,000 or more, and process data every 5 ticks. On a less powerful machine, you may want to process fewer items at a time, less often.

From v0.10, Logistics Insights uses a sophisticated scheduler that attempts to smoothe the load across many ticks, allowing you to get up to date
information even with many networks, without suffering a noticeable performance impact.

## What's next?

There are many ways in which this mod could become more useful, and I'll be looking for feedback on what you'd like to see. Here are some of my ideas:

**Main window**

- Maybe it would be useful to step forward more than one tick at a time. Should there be a "step 10-ticks" button, or maybe a config option?
- The main window right now is floating, which means you can position it anywhere, but it also means it might open overlapping with something else. Should it instead stick to the top or left sides? Should it be an option?
- The max number of items that can be shown in Delivering/history is 10. Would more be useful?

**Highlighting items**

- When highlighting bots, it might be useful to show info about where each bot is going. Maybe an arrow pointing to the destination?
- When clicking on a category to highlight them, there is no limit to how many items are shown. It's possible that this needs to be limited to 1,000 or something so the game doesn't grind to a halt if you have a lot of items, so maybe an option is in order.
- When highlighting a group of items, maybe it would be useful to set zoom level to include as many of them as possible, and focus somewhere around the middle?

**Completely new functionality**

- When focusing on a single bot (with right-click in a cell like Delivering), it might be fun to have a "follow" window that allows you to see where it's going.
- I'd love to show a heat map of activity on the mini map, but I can't see a way for a mod to do this. Do you know how?
- Maybe it would be useful to also show what Construction Bots are doing? Not sure about that, maybe that's another mod!

## Known issues

- If you freeze the game, the mod does not pick up a new network (even if you change map position) until you unfreeze it.

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
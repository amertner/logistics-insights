# Logistics Insights

Have you ever wondered what all of your logistics bots are up to? Whether you have too many, or too few? Particularly in the mid game where everything is scaling up, I've found that the answers sometimes are surprising.

Logistics Insights can help:
- Shows a list of the top items being carried in real time
- Shows a sorted list of items that have been delivered the most
- Shows a list showing the items that took the longest to deliver
- Shows what your bots are doing: Idle, charging, waiting to charge, picking or delivering
- Shows what entities you have in your bot network: roboports, requesters, providers, etc.
- With a click, can highlight all entities or bots doing a particular activity, making it easy to find them
- When highlighting bots, the game temporarily freezes, allowing you to inspect the state of things
- You can freeze and single-step the game manually as well
- You can easily pause and restart gathering of what is being delivered to reduce impact on game speed
- Hide and show the main window by clicking the "logistics bot icon window" that's always open.

Logistics Insights focuses on a single bot network at a time, whether it's the one where the player is located or one you're looking at via the map view. It does not gather info on all networks at the same time.

## How I started using it

Before a base reaches megabase level, I keep the LI window open to keep an eye on whether I have the right number of bots and roboports. If it gets in the way, I'll close it and occasionally open it to see what's going on.

## In the Delivering/Total/Ticks rows
- If some items take a disproportionate amount of time to deliver (i.e. they show up early in the Ticks/item list), I'll consider transporting those using belts instead, or creating a source of items closer to where it's needed
- If there is some item that's being transported unnecessarily (i.e. it shows up early in the Totals list), I'll see if I could belt that item instead. For example, in one case I found that my bots were transporting iron ore 90% of the time, filling up my storage chests, all because I accidentally put ore in an active provider chest.

## In the Activity row
- If too many bots are "waiting to charge", I need to build more roboports
- If too few bots are "available", I need to add more bots
- If most of the bots are "available", I need to stop adding more bots

## Performance and chunking

What Logistics Insights does can be expensive, and for very large bot networks will cause the game to slow down. The mod is written to mitigate this by processing the bots and network items in chunks. The default chunk size is 400, but you can change this.

By lowering the chunk size, you reduce the performance impact of Logistics Insights, at the expense of getting results that are not entirely accurate.  This is because the mod copies the full list of items and processes it one chunk at a time, which means that the game state may have changed by the time it gets to the final chunk.

A progress indicator shows the chunk processing in action, and the chunks apply to both bots and roboports:
- If you have 1,800 bots and use the default chunk size of 400, it will take 5 passes before the bot data showing Delivering and History (Total and Ticks/Item) is updated. A pass is done every 10 ticks, or 6 times per second.
- If you have 900 roboports with the default chunk size, it will take 3 passes before the Activity data about your bots is updated (showing Available, Charging, Waiting, Picking Up or Delivering). A pass is done every 10 ticks if Delivery or History is enabled, and every 60 ticks otherwise.

If you have fewer bots or roboports than the chunk size, the data will be updated on every pass.

## Limitations

Logistics Insights only works in single-player games. This is to avoid adding a large performance overhead on everyone from monitoring multiple logistics networks, as well as to keep the code simpler.

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
- If you configure the highlights to never time out (set a timeout value of 0), there is no way to clear them. Maybe there should be a button to do this, but where would be a good place for it?

### Performance
- Is the performance impact too big when playing with 100,000 bots in a single network? I have tested it with 20,000 bots in a network, and it seems fine, but it's possible that more performance work should be done.
- Maybe there should be an option to automatically change the chunk size and update intervals to keep the performance impact of the mod in the right place. (Slider to favour accuracy or performance?)

### Completely new functionality
- When focusing on a single bot (with right-click in a cell like Delivering), it might be fun to have a "follow" window that allows you to see where it's going.
- I'd love to show a heat map of activity on the mini map, but I can't see a way for a mod to do this. Do you know how?
- Maybe it would be useful to also show what Construction Bots are doing? Not sure about that, maybe that's another mod!

## Known issues

If you load a game that was saved while frozen, all entities will show a yellow blinking icon for some reason. Unfreeze or single-step the game to clear this condition.

## Translation

The mod is not yet translated to languages other than English, though all strings are set up in a way that makes it possible. I intend to make it possible to submit translations at some point.

## Thanks

These people helped me with code and inspiration:
- [Xorimuth](https://mods.factorio.com/user/Xorimuth) for the excellent [Factory Search](https://mods.factorio.com/mod/FactorySearch) mod and code to highlight items on the map
- [raiguard](https://mods.factorio.com/user/raiguard) for [Stats GUI](https://mods.factorio.com/mod/StatsGui) in particular
- [justarandomgeek](https://mods.factorio.com/user/justarandomgeek) for the brilliant [mod debugger](https://github.com/justarandomgeek/vscode-factoriomod-debug)
- [HermanyAI](https://mods.factorio.com/user/HermanyAI) for [Item Cam 2](https://mods.factorio.com/mod/item-cam-2), which I thought I could use but ultimately didn't...
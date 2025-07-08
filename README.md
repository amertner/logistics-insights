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

Logistics Insights focuses on a single bot network, whether it's the one where the player is located or one you're looking at via the map view. It does not gather info on all networks at the same time.

## Performance impact

What Logistics Insights does can be expensive, and for very large bot networks will cause the game to slow down. The mod is written to mitigate this by processing the bots and network items in chunks. The default chunk size is 400, but you can change this.

By lowering the chunk size, you reduce the performance impact of Logistics Insights, at the expense of getting results that are not entirely accurate.  This is because the mod copies the full list of items and processes it one chunk at a time, which means that the game state may have changed by the time it gets to the final chunk.

A progress indicator shows the chunk processing in action.

## Limitations

Logistics Insights only works in single-player games. This is to avoid adding a large performance overhead on everyone from monitoring multiple logistics networks, as well as to keep the code simpler.

## Translation

The mod is not yet translated to languages other than English, though all strings are set up in a way that makes it possible. I intend to make it possible to submit translations at some point.

## Thanks

These people helped me with code and inspiration:
- [Xorimuth](https://mods.factorio.com/user/Xorimuth) for the excellent [Factory Search](https://mods.factorio.com/mod/FactorySearch) mod and code to highlight items on the map
- [raiguard](https://mods.factorio.com/user/raiguard) for [Stats GUI](https://mods.factorio.com/mod/StatsGui) in particular
- [justarandomgeek](https://mods.factorio.com/user/justarandomgeek) for the brilliant [mod debugger](https://github.com/justarandomgeek/vscode-factoriomod-debug)
- [HermanyAI](https://mods.factorio.com/user/HermanyAI) for [Item Cam 2](https://mods.factorio.com/mod/item-cam-2), which I thought I could use but ultimately didn't...
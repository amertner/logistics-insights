# What are Suggestions?

Suggestions are the result of analysing a Logistics Network, and give ideas for how it could run better or more efficiently. Suggestions show up with either a red background (high priority) or a yellow banground (lower priority).

These are the available suggestions:

## Build more roboports

If you build just enough roboports to cover your base, it's likely that it won't support the population of robots well. This is because robots take quite a long time to charge, and each roboport only has 4 charge ports. This in turn means that it's easy to end up in a situation where a lot of your robots aren't doing anything useful, but are simply waiting to charge.

In this situation, the best bet is to build more roboports along the most commonly traveled paths. If you can build higher-quality roboports, even better as they help robots charge faster.

Logistics Insights will suggest that you build 1 new roboport for every 4 bots that are waiting to charge. If you have more than 400 robots waiting to charge, this suggestion will be high priority.

## Build more storage

If your storage runs low, Logistics Insights will suggest that you add more storage chests when you've used up more than 70% of the available space. If your storage is more than 90% used, this will be a high-priority suggestion.

Note that there is a per-network setting to not create this suggestion for networks that have no storage at all.

## Build more unfiltered storage

If you don't have free storage without a filter, your robots can't drop off items that there isn't a filtered chest for.

If more than 70% of your unfiltered storage is in use (or if you have no unfiltered storage), Logistics Insights will suggest that you add more unfiltered storage chests.

## Mismatched filtered storage

If you put a filter on a storage chest, robots will only store that item in the chest, which can be great to avoid a chaotic storage area. However, if you add things to chests in some other way, or added a filter to a chest with existing contents, you can end up with chests that contain items other than the filter.

If you do, this suggestion will tell you how many such chests you have. You can click on the icon to highlight them, or right-click to focus on one of them randomly, which can help you figure out why and fix the issue.

You can also Shift-click on the suggestion to ignore it. This adds all of the chests to a list that will be ignored for filter mismatches. To clear the list again, open the Settings for the network and Clear the list.

The settings also has an option to ignore filter mismatches where the quality is higher than the filter. For example, you may have a chest with a filter for "uncommon power poles". If you check this option, power poles of quality higher than uncommon will no longer flag a mismatch.

## Stop adding more robots

If you already have more bots than you need, it's a waste of Factorio resources (and potentially your computer's resources) to continue adding them.

Logistics Insights will look for networks of more than 100 robots where more than 50% of them are idle and where more bots are being added. If it finds this is the case, it will suggest you stop adding more.

## Unpowered Roboports

If a roboport is disconnected from the electric grid, Logistics Insights will tell you to reconnect it. When a roboport is built, it comes preloaded with 25% energy, so it can connect to a logistics network in range and power a few bots; until it is connected to electricity, Logistics Insights will suggest you do so. The suggestion remains even after a roboport is completely out of power, at which point it's technically no longer part of the network.

## Aging out suggestions

As of v1.0.7, suggestions no longer just disappear when their condition is resolved. Instead, they remain visible on a greyed-out background for 3 minutes to give you a chance to look at what happened without worrying that interesting suggestions disappear before you get to see them. The interval is configurable in the per-map mod settings, from 0 (don't show aging suggestions) to 60 minutes.

## More suggestions could be added

What might be useful for you? What patterns have you spotted?

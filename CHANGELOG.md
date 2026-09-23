# Changelog

## 1.4.0-beta4

- Updated shared YippYapp library.

## 1.4.0-beta3

- **AutoFeed only ever edits macros it made itself.** If a macro with one of its names already exists and isn't one of AutoFeed's, it is left alone and AutoFeed says so instead of overwriting it.
- **Lighter on your bags:** moving things around no longer makes AutoFeed re-read every item. It only rescans when what you carry actually changed, and the settings page reads your bags when you open it rather than at login.
- Updated shared YippYapp library: addon messages are resent after the game refuses them, and windows open above the Options window instead of closing it.

## 1.4.0-beta2

- Updated shared YippYapp library: settings under Options > AddOns > YippYapp, the shared minimap button keeps its position.
- Buffs are never read while the game keeps them hidden, so no errors in combat or encounters.

## 1.4.0-beta1

- **One welcome window for all YippYapp addons.** AutoFeed no longer opens its own first-time window. Its introduction and the Create buttons for the macros are now a page in the shared YippYapp welcome window, which opens by itself (never in combat or in a dungeon) while you have no AutoFeed macros yet. `/autofeed welcome`, left-clicking the AutoFeed icon on the minimap (behind the YippYapp button if you use several YippYapp addons), and `/yippyapp` open it by hand.
- **Tidier settings page:** sections for Macros, Food & water, Potions, Scrolls & bandages and Exclusions, with the version in the title. The minimap and launcher buttons are now switched on and off on the shared YippYapp settings page (Options > AddOns > YippYapp); if you had turned AutoFeed's minimap button off, it stays off.
- **The AutoFeed icon goes straight to the settings:** clicking it (minimap, addon compartment, launcher) opens AutoFeed's settings in the YippYapp window, where the Create-macro buttons are. Either mouse button does the same.
- **Welcome / what's new** button on the settings page opens AutoFeed's page in that window.
- The minimap button now uses the standard LibDBIcon button, so the icon sits centred in the ring and drags like other addons' buttons. It keeps the spot you had it in.
- If you already saw the old AutoFeed welcome window, the new one doesn't pop up for you.
- The welcome page counts as seen per character, so a new alt with no AutoFeed macros still gets it.
- Potions and drinks AutoFeed doesn't use (Swiftness, Free Action, alcohol and so on) no longer make it rescan your bags over and over after every bag change.
- Scrolls are found right after login too, instead of the scroll macro saying "all scroll buffs active" until the next bag change.
- Buffs gained or lost during combat update the macros once combat ends.
- Create buttons say "can't create macros in combat" in combat, instead of claiming your macro slots are full.
- No more "AutoFeed loaded" line in chat at login.

## 1.3.0 (unreleased)

Ported to the modern game client that WoW: Forever runs on.

- **Buff food for XP while leveling.** On Forever, Well Fed also gives +5% experience from kills. When you're below max level and not Well Fed, the food macro now picks your best buff food (or buff drink if you have no buff food) until the buff is up, then switches back to plain food. On by default; turn it off in settings. `/autofeed status` says when it's doing this.
- Your buffs are read more reliably, so buff food is no longer suggested while you already have Well Fed. When some of your buffs are hidden from addons, AutoFeed doesn't suggest buff food, since it can't tell whether Well Fed is missing. `/autofeed status` shows what it sees.
- Shorter settings labels, so the left column no longer runs into the right one.
- Item and buff lookups use the modern item and aura APIs (the old global functions are gone on this client).
- Bags are scanned up to the last equipped bag, including the extra bag slot the modern client adds.
- The settings checkboxes are rebuilt for the modern client: the old options checkbox template no longer exists.
- Addon compartment entry next to the minimap.
- Forever's bronze look for the welcome window: the client's own bronze frame and stained-wood background (the same art as Forever's character creation). The settings page keeps Blizzard's standard look.
- Optional button on the shared YippYapp launcher bar (off by default), with a new AutoFeed icon. Its tooltip shows the food your macro currently eats.
- Updated for WoW: Forever (interface 120100 / 120105).

## 1.2.2

- **Settings open again on patch 1.15.9.** Clicking Settings did nothing and threw an error.
  The patch changed how addons open their options page - it now needs a numeric category ID,
  and AutoFeed was handing it a name.
- Opening settings **during combat** no longer throws a "blocked" error. The game protects the
  options panel in combat, so AutoFeed now just says to try again after the fight.
- Updated for game version **1.15.9**.

## 1.2.1

- Minimap button sits cleanly on the ring at the right size, with a hover glow, and scales
  with the minimap instead of drifting off the edge when it's resized.

## 1.2.0

### New
- **AutoBandage** macro — points at your best bandage (with the next tier as a
  fallback). Off-cooldown healing, a hardcore staple.
- **Minimap button** — left-click for settings, right-click to create macros, drag
  to move (toggle in Settings).
- **"Create all"** button in the welcome window and Settings to make every macro
  at once.

### Fixes
- Scroll buffs are now skipped when a non-stacking class buff for that stat is
  already active (Arcane Intellect / Power Word: Fortitude / Divine Spirit and
  their group variants), so AutoScroll no longer suggests a scroll that would just
  fail with "a more powerful spell is already active."

## 1.1.0

### New
- **Welcome window** on first login (reopen with `/autofeed welcome`) with a
  Create button for each macro. Macros are now created **on demand** instead of
  automatically, so AutoFeed only uses the character macro slots you ask for.
- **Create-macro buttons** in Settings too, showing which macros already exist.

### Fixes
- Food/potions sometimes not detected right after login — the scan now retries
  until item data finishes loading, and never caches a "not a consumable" verdict
  from incomplete data. `/autofeed update` also clears the cache now.
- Buff / Well Fed food is no longer auto-suggested when "filter buff food" is on,
  even if it's the only food in your bags (it's saved for raids).
- Scroll buffs whose aura isn't named after the stat (e.g. Scroll of Protection →
  "Armor") are now detected correctly, so a scroll you've already used isn't
  suggested again.

## 1.0.0

Initial release.

AutoFeed keeps a small set of self-updating macros pointed at the best consumables
in your bags — eat, drink, pot, and buff from one button each, with no dragging
food/water/potions/scrolls onto your action bars.

### Macros
- **AutoFeed / AutoDrink** — picks the best food/water for your level (conjured-first
  optional), drains partial stacks, and can combine eat + drink on a single click.
- **AutoHealPot / AutoManaPot** — combat-safe macros that list your top 3 potion tiers,
  so the next one fires if your best runs out mid-fight. Strongest-first or weakest-first.
- **AutoScroll** — cycles the scroll buffs you're missing (Stamina / Strength / Agility /
  Intellect / Spirit / Protection), always self-targeted, and goes blank once fully buffed.

### Other
- Exclude list for specific potions and scrolls (remembered by item).
- Buff-food filter — ignores Well Fed / stat food by default so you save it for raids.
- Self-updating on bag, level, and buff changes; updates deferred during combat.
- Settings via `/autofeed` (or `/af`); `/autofeed status | update | debug` helpers.

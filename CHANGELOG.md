# Changelog

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

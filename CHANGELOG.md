# Changelog

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

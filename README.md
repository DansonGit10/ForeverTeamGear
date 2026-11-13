# Forever Team Gear

### Automatic synchronization in 0.31.0

Automatic synchronization is enabled in online modes. A small section manifest is announced 10–40 seconds after entering the world and every 5–6 minutes thereafter. Receivers request only missing or changed sections through targeted addon whispers, with at most two automatic downloads active at once. Legacy guild-wide sync requests remain ignored. Existing private-group handshakes announce manifests automatically, and supported channel-roster APIs rediscover online peers in an already joined private channel after reload. Joining a private channel still requires the existing setup/share click when the client has not joined it; protected chat operations are never retried from background timers. Offline mode disables all communication. Sharing permissions, paced packets and receive-memory limits remain in effect. Sync Party and Share my data remain available for manual use. All participants should update.


### Sync Now in 0.30.0

Sync Now, `/ftg sync`, and right-clicking the minimap button exchange profiles only with current party/raid members. Requests are sent through PARTY/RAID; profiles travel through audience-checked addon whispers. Offline mode does not communicate. Existing guild membership / matching private group code and sharing settings still apply. A request has a 30-second cooldown; replies are delayed randomly by 1–5 seconds and aggregate reply requests are rate-limited. No guild-wide request is issued. `/ftg share` retains the one-way publication/discovery command. Background own-data publication remains unchanged.


### Communication in 0.28.0

Update every participant to 0.28.0 (FTG11). **Share my data** and `/ftg sync` publish only your current character's own snapshot. Receiving data, party/guild roster changes, and legacy sync requests do not trigger profile replies. Background updates send changed sections; login publications are staggered by 10–40 seconds. A manual share sends your full allowed snapshot so new receivers can obtain it. Friends must publish their own data; opening the addon does not fetch everyone's history. Private discovery handshakes establish routes without uploading profiles. Guild publication uses one broadcast stream; private delivery still sends a separate copy per peer. Packets remain paced at 180 payload bytes per 0.12 seconds. Incomplete receive data is capped at 2 MiB per client, with at most 80 active sections and expiry after 120 seconds. Received profile UI refreshes are coalesced to one per 0.25 seconds. The older synchronization descriptions below describe prior versions.


A lightweight character-sharing addon for **World of Warcraft: Forever 1.60.1** (`Interface 16001`, Camelot).

## Features

- synchronizes equipment with a private group, a guild, or both;
- synchronizes aggregated bag contents and the last bank contents seen after opening the bank;
- includes an **Inventory** tab with a character selector and separate **Bags / Bank** views;
- character-panel layout with equipment slots on both sides and weapons along the bottom;
- a shared character picker for Equipment and Inventory, with name/class/profession search, source filters, optional hidden alts, and saved favorites;
- choose a player first, then one of their characters; Settings includes a player display name, backed by an automatically generated account-local ID shared by your alts; friends need the updated addon and a fresh sync from each character, while older snapshots appear under Unassigned;
- the character picker uses a three-column grid of buttons with full names in class colors, classes, levels, data origin, and snapshot age; favorites sort first, followed by your characters and then other characters alphabetically;
- allows any saved character to be marked as an alt, keeping its data visible while excluding it from automatic BoE upgrade alerts;
- synchronizes class, level, and specialization;
- shows the exact talent-point split for all three class trees in the Equipment summary;
- opens a synchronized, read-only talent window with all three class trees visible side by side;
- uses the original class-specific talent background artwork already included in the WoW client;
- draws prerequisite paths and directional arrows between connected talents, colored green when the synchronized build activates both talents;
- shows the talent entry tooltip for the synchronized rank instead of the local character's spell tooltip;
- tracks profession levels and known recipes;
- presents one icon card per profession, combining all saved characters;
- opens a classic-style profession browser when a profession is clicked;
- merges recipes by recipe ID and lists every character who knows each recipe;
- shows individual character profession ranks in the profession card tooltip;
- groups recipes by their in-game category, with an item-type fallback when Forever does not expose a recipe category;
- filters recipes by a manually entered Required Level, the currently logged-in character's level, text search, or whether you currently have enough materials;
- shows a recipe's crafted item, output quantity, required materials, and how many of each material you have in bags and the bank;
- lets you mark recipes with **Track materials** and warns when a newly acquired ingredient is needed by a saved, non-alt character in your selected audience;
- detects newly acquired Bind on Equip items in party members' bags;
- automatically refreshes and requests every party member's equipment whenever a new BoE is detected;
- opens a Warcraft-style comparison window naming every character for whom the BoE is a potential item-level upgrade;
- evaluates saved characters in the selected audience, including offline snapshots, without requiring party/raid membership, and suppresses duplicate automatic alerts;
- shows the currently equipped item beside the new BoE, including icons, item levels, matching slot, and item-level gain;
- identifies who looted the BoE and lets group members answer **Need** or **Pass** in the comparison window;
- includes a **Test Alert** button in **Settings**; it previews the notification for the character selected in Equipment without creating a fake BoE record;
- compares each BoE with saved equipment in the matching slot; **Compare** can reopen the assessment at any time;
- checks the item's required level plus class armor, shield, relic, and weapon eligibility before treating it as a potential upgrade;
- remembers the latest character data and up to 100 recent BoE items locally;
- adds a draggable minimap button: left-click toggles the addon and right-click synchronizes the group;
- can manually share one selected macro as inspectable text; received macros are never installed or executed automatically;
- no external server, account, telemetry, or third-party libraries.

## Installation

Copy the complete `ForeverTeamGear` folder to:

`World of Warcraft\_classic_beta_\Interface\AddOns\ForeverTeamGear`

Every player who wants to exchange data must install the addon. Log in and type `/ftg`.

## Setup and privacy settings (0.22.0)

### Synchronization in 0.24.0

All participants must update to **0.24.0 or newer**: section updates use the FTG9 protocol and are intentionally isolated from older whole-profile receivers.

- Profiles are transferred as independent identity/settings, equipment, talent, profession, bag, and bank sections. Receiving one section preserves all the others.
- Automatic updates skip unchanged sections for each destination. Direct sync requests include the recipient's saved section fingerprints so only missing or different sections need to be returned. Guild-wide requests without a per-character manifest use a complete reply to repair missing data reliably.
- Bag updates collect changes for 15 seconds; an explicit Sync or a more urgent equipment/privacy update can advance that deadline.
- Handshakes and sync requests have top queue priority, requested replies follow, and background professions/bank data have lower priority. Pending snapshots of the same section are replaced by newer ones.
- Persisted section revisions prevent delayed background transfers from overwriting newer data. Incomplete or missing sections are requested again by the next direct Sync.
- Combined private+guild broadcasts avoid duplicating automatic data to private contacts who receive the same guild broadcast. Profiles are never relayed from one player to another.
- The Sync button shows queued outgoing packets or active reception. Large incoming sections print progress at roughly 25%, 50%, 75%, and 100%.

Initial synchronization still needs to deliver all enabled data and may take time for large recipe/inventory snapshots. Transport pacing remains one packet per 0.12 seconds, with up to 180 payload bytes per packet. Each section supports up to 2048 packets. No external compression library is required.

`lua tests/SyncScale.lua` simulates 20 clients and 380 peer profiles, including 160-recipe snapshots, repeated unchanged sync, a bag change delivered to 19 peers, missing-section repair, priority changes, stale data arriving late, and a larger 1200-recipe section. These are mocked transport tests, not a live 20-player performance measurement.

Version 0.22.4 starts private-channel discovery only from **Save**, **Sync Now**, `/ftg sync`, or a minimap right-click. Reload events and timers never join or send ordinary channel chat automatically. If joining the channel completes asynchronously, click **Sync Now** again after the channel-ready message. Addon whisper replies and subsequent data updates remain automatic. Blocked-action events now print the exact API name to addon chat for troubleshooting.

On your first login with this version, choose a mode and click **Start**. Until setup is saved, communication stays disabled. Reopen this page with the **Settings** button or `/ftg settings` (`/ftg setup` also works).

- **Offline:** only your locally saved characters are visible; no addon data is sent or received.
- **Private group:** choose **Generate**, share the code with friends, and have everyone enter the same code and save. **Sync Now** discovers members automatically, including outside a party/raid. No character names need to be entered. A dedicated password-protected WoW channel carries discovery greetings only; actual character data uses code-checked addon whispers. Nothing is sent to party/raid or guild channels in this mode. Players need compatible realm/faction chat and an available custom chat channel slot. Codes identify membership; they do not encrypt data. Settings displays the number of connected friends.
- **Guild:** your characters plus members of your current guild, including cached offline members; synchronization uses the guild channel and authenticated whispers. Guild membership is checked against the game's roster. Without a guild there is no guild synchronization.

Settings apply to all characters sharing this SavedVariables file. Characters scanned locally are remembered as yours. Existing local profiles are migrated when identifiable; log in to each alt to ensure it is recorded as yours. Cached profiles from outside the selected audience are hidden, not deleted. Changing the private group code hides profiles received under the previous code. Only the character currently logged in is transmitted; other characters remain available from previous snapshots. The previous party-based Group mode is reset to Offline and setup is reopened so no data is shared before a code is chosen. All private-group participants need version 0.20.0 or newer.

You can independently share equipment, specialization/talents, professions/recipes, bags, bank, BoE drops/Need/Pass, and manually selected macros. **All sharing checkboxes are enabled by default for new configurations (0.22.10); existing choices are preserved.** Basic identity (name, class, level) is included in online profiles. All data remains available locally even when sharing is disabled. Macro sharing still requires explicitly selecting a macro with the command.

As of 0.22.9, sharing checkboxes save immediately after the initial setup and queue a fresh profile without disconnecting friends. Mode, group-code, and guild-audience changes still require **Save settings**. Receipt messages include whether bags/bank are shared and how many item types were received. Bank contents still require a previously captured bank snapshot.

Privacy settings remove disabled data before transmission, including whisper replies to sync requests. Saving settings discards queued transmissions and sends an updated allowed profile when online. Receivers running this version replace the old snapshot and label private inventory as not shared. Previously delivered snapshots cannot be erased from other players' computers, particularly while they are offline or running older versions.

Enable **Also sync with my guild in Private group mode** to participate in both audiences simultaneously. The same sharing preferences apply to both. Private-group packets still use code-checked whispers; guild packets use guild channels or authorized whispers. Other players' profiles are not relayed between audiences.

BoE comparisons and material alerts use all saved characters visible in the selected audience, including offline private-group members and guild members outside your party/raid. Alts remain excluded from upgrade/material notifications. Each BoE's **Compare** button reruns the assessment on demand and can reopen a previously shown alert. Equipment data is the most recent received snapshot; offline characters cannot provide a fresh scan until they log in and synchronize. Evaluation still uses item level and eligibility, not build-specific stat weights.

Regression checks: run `lua tests/Settings.lua` and `lua tests/PrivateGroup.lua` from the addon directory with Lua 5.1. The second test simulates three clients discovering members, synchronizing by whispers without a party/guild, ignoring different codes, changing codes, and rejoining. These checks use mocked WoW APIs; actual chat-channel support and synchronization still require testing in the Forever client.

## Commands

- `/ftg` — opens the equipment panel;
- `/ftg settings` — opens setup, operating modes, and sharing preferences;
- `/ftg boe` — opens the BoE comparison list;
- `/ftg sync` — scans and shares the latest data;
- `/ftg sync FirstName Surname` — tests direct private-group synchronization by addon whisper without channel discovery; the recipient must have the same saved code;
- `/ftg inventory` — opens synchronized bag and bank contents;
- `/ftg macros` — opens manually shared macro text;
- `/ftg sharemacro <number>` — shares exactly one macro from your macro list with the current group;
- `/ftg help` — prints the command summary.

Open each profession window at least once. The game does not expose its known recipe list to addons until that profession has been opened.

## Profession browser

Each profession has one shared card. Its browser lists each recipe once. The selected recipe's owners appear under the materials in the right panel. Search also matches character names; hover a recipe for the full owner list. Hover a profession card to see each character's skill rank. **Track materials** applies to every current owner of the selected recipe; selected-audience and non-alt notification rules still apply.

The recipe list uses a dark Blizzard-style layout with compact rows, gold category headers, and a persistent selected-row highlight. Click a category to collapse or expand it. Filters temporarily show matching recipes even in collapsed categories. Skill-up colors and difficulty indicators are omitted.

Open the **Professions** tab and click a profession marked **Click to browse**. Recipes appear on the left; selecting one shows its output and required materials on the right. Material ownership is counted from your own bags and the bank, regardless of which party member knows the recipe. Open the bank once after login so the game can expose its current contents to addons.

After installing this version, each player should open every profession window once and click **Sync Now**. Older cached recipe entries remain visible but cannot show their materials until they are scanned again.

## Version 0.17.2

- Coalesces frequent profile broadcasts and replaces queued, unsent profiles with the newest snapshot, preserving transfers already in progress.
- Validates group senders, profile ownership, BoE looters, macro ownership, and Need/Pass responders.
- Rejects malformed or inconsistent chunks, limits incomplete transfers, and expires abandoned transfers independently of incoming traffic.
- Allows 120 seconds of inactivity before abandoning a transfer so larger profiles can finish on a busy queue.

## Limitations

The BoE view first checks the synchronized character's level and normal Classic class equipment rules, then compares item levels in the matching slot. It does not claim that a higher-level item is automatically better for a particular build. Stats, effects, unusual item-specific tooltip restrictions, learned weapon proficiencies, and personal priorities still require a player decision.

Only bags are watched for newly acquired drops. Bank contents contribute to profession material totals but are deliberately not treated as fresh loot. Bank totals depend on the game's last known bank data and become reliable after the bank has been opened during the current session.

Shared inventory is intentionally aggregated by item and stack count instead of reproducing exact bag-slot positions. Bags update while playing. Bank data is the last snapshot captured when that character opened the bank; the Inventory tab displays its age.

WoW: Forever is still evolving. A future client update may require changing the `Interface` number in the TOC file.

## Privacy

In version 0.21.0, **Macros** is a main-window tab. **My macros** lists both account and character macros. Select one to preview its text, then click **Share selected** to send exactly that macro to connected private-group members or your guild, according to Settings. Sharing must be enabled for macros. **Shared macros** lists received and previously shared text for the selected audience; click the text and use Ctrl+A / Ctrl+C to copy it. Nothing is installed or executed automatically.

Each BoE entry has a **Delete** button. It removes only that individual drop from your local saved history and closes its comparison popup, if open. It does not delete items or change other players' history.

The BoE list displays all retained drops as compact entries with item tooltips, looter, age, and a summary of potential upgrades for current, non-alt group characters. Click an entry to expand saved-character comparisons and Need/Pass responses. Shift-click the item header to insert its link into chat.

The addon sends only enabled categories of character data through WoW's built-in addon whispers for the private group, or guild channel/whispers for Guild mode. A dedicated private-group chat channel sends discovery greetings only. Bag and bank item IDs/counts are sent only when explicitly enabled in Settings. Offline mode sends and receives nothing and leaves the private discovery channel. It never connects to the Internet.

Automatic BoE upgrade and tracked-material alerts are disabled by default. Choose a minimum rarity in Settings under "Automatic alerts — minimum rarity" (the selected rarity and higher). Test Alert and manual comparisons remain available.

Version 0.26.0 preserves exact random-stat BoE links and separate bag/bank item variants, including suffix and seed. All peers must update to 0.26.0 (FTG10). Rescan bags, open the bank to refresh it, and sync each character. Legacy BoE records cannot recover lost suffixes.

Version 0.27.0 identifies characters by full character name without backend realm suffixes. Existing profile keys and character references migrate automatically; duplicate backend aliases keep the newest profile. Update all peers. Realm values are read only for interpreting legacy client name APIs and migrating old saves.

Version 0.29.0: Shared macros use the player → character picker, limited to owners with visible macros. Delete locally removes a received copy; Unshare locally removes your local shared entry without deleting the actual WoW macro or recalling copies on other computers. Duplicate packets do not restore deleted entries; an explicit newer share may restore them. BoE Drops has Clear all, retains at most 100 entries, and automatically expires entries older than 48 hours at startup, when viewing/receiving drops, and every five minutes.

Version 0.30.6: Private-group discovery handles asynchronous channel joins and both numbered and raw channel-name event formats. Existing members initiate code-checked addon handshakes when a new member joins; only users who explicitly publish send their own profiles. Settings displays private-channel discovery and error status below Connected friends. Both users should update, select the same code, and click Share my data.

Version 0.30.7: Talent trees use a fixed, collision-free grid rather than proportional coordinate scaling. Extreme coordinates no longer compress nearby icons, distinct nodes sharing a position remain accessible, and overflowing trees can be scrolled independently.

Version 0.30.8: Recipe capture waits for the profession API to be ready, retries delayed loading, and preserves previous recipes on empty or incomplete scans. Manual sharing refreshes the currently open profession first. Recipe names and icons now travel with output and material data. All profession slots, including the sixth secondary slot, are scanned. Open each profession once after updating, then click Share my data to repair previously empty received snapshots.

Version 0.31.1: Automatic BoE popups first check the logged-in character's class, armor/weapon compatibility and required level. An upgrade for another player no longer opens a popup when the local character cannot equip the item. Unknown item classification suppresses automatic alerts; manual team comparisons and Test Alert remain available.

Version 0.31.2: Skill-line changes queue an immediate profession update. The open profession window refreshes skill rank and cap on existing records independently of recipe loading; stale API readings cannot overwrite newer skill values. Reopen each profession once and use Share my data to repair an older received snapshot.

Version 0.31.3: Automatic alert deduplication and X/Dismiss state persist locally for 48 hours, including across reloads and duplicate deliveries. Bag loot identity ignores viewer level/specialization and link display text while preserving random-stat suffixes and unique seeds, preventing existing items from being repeatedly detected as new drops. Manual comparisons and distinct later drops remain eligible.

Version 0.31.4: Talent updates listen for both classic and trait events, retry incomplete reads, support active/current/entry rank API variants and respec decreases, and derive tree point totals from nodes when possible. Failed reads preserve the last complete snapshot. Open talent browsers refresh when synchronized builds change; read-only preview events do not trigger scan loops.

Version 0.31.5: Section revisions use a persisted counter with a server-time floor, preventing a reset/restored sender counter from being permanently rejected by cached receivers. Talent API exceptions no longer abort the complete character scan. Malformed currency entries and alternate active-entry shapes are handled safely. `/ftg talentstatus` on the affected character opens a copyable report with the live scan result and exact failure detail.

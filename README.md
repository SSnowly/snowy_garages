# snowy_garages

A FiveM garage resource built from scratch after VMS Garages sucked.

Supports **QBox**, **QBCore**, and **ESX** out of the box. Garages, parking spots, pay stations, impound, IPL interiors - all configurable in-game without touching a database.

---

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- QBox (`qbx_core`), QBCore (`qb-core`), or ESX (`es_extended`)

---

## Installation

1. Drop `snowy_garages` into your resources folder.
2. Add `ensure snowy_garages` to your `server.cfg` **after** your framework and `oxmysql`.
3. Configure `configs/shared/main.lua` to match your server.
4. Start the resource - tables are created automatically.

If `snowy_garages` table is empty on first start, default garages from `data/seed_garages.ndjson` are inserted automatically.

---

## Configuration

All config lives in `configs/shared/main.lua`.

```lua
ownedVehiclesTable = 'player_vehicles'  -- your framework's vehicle table
platePattern       = 'AAAA1111'         -- plate generation format (A = letter, 1 = digit)
npcPlatePattern    = '1111AAAA'         -- NPC plates, set false to disable rewriting

autosaveIntervalMinutes = 5             -- how often out-of-garage vehicles are autosaved
autosaveClientTimeoutMs = 2000          -- how long to wait for a client to report props

loadDistance         = 120.0            -- distance at which garage zones load
interactDistance     = 4.0             -- distance to interact with spots/pay stations
parkingGracePeriod   = 3600            -- seconds before parking fee kicks in after storing

creatorGroups = { ['superadmin'] = true, ['admin'] = true }  -- who can use the creator

impoundJobs = { 'police', 'sheriff' }  -- jobs that can use /impound
impoundFee  = 500                      -- default fine pre-filled in the impound dialog
```

### Impound lots

Defined as a table in config. Each lot handles specific vehicle classes:

```lua
impoundLots = {
    {
        id         = 'car',
        label      = 'Capital Blvd',
        classes    = nil,              -- nil = catch-all for anything not matched elsewhere
        location   = vector3(...),
        spawnPoint = vector4(...),
        npc = {
            model    = `a_m_m_rurmeth_01`,
            coords   = vector4(...),
            animDict = '...',
            anim     = '...',
        },
    },
    {
        id      = 'boat',
        classes = { 14 },             -- only vehicle class 14 (boats)
        ...
    },
}
```

Add as many lots as you need. Vehicles are routed to the first lot whose `classes` list contains their vehicle class. The lot with `classes = nil` is the fallback.

---

## Features

### Garage types

| Type | Description |
|---|---|
| `parking` | Standard open-world parking zone |
| `ipl` | Interior garage - teleports the vehicle in/out through an entry point |

### Job-locked garages

Set the `company` field on a garage to a job name. Only players with that job can store/retrieve vehicles from that garage.

### Vehicle type filtering

Set `vehicle_type` on a garage to `car`, `boat`, or `air`. Players can't store the wrong type.

### Pay stations

Garages with a `fee` and pay stations require payment before taking a vehicle out. Players have a grace period (`parkingGracePeriod` seconds) after storing before the fee applies.

### Impound

Officers with a job in `impoundJobs` can use `/impound` near a vehicle. Supports:
- Custom fine amount
- Lockout duration (vehicle can't be released until time expires)
- Reason text shown to the player

Vehicles swepted into impound on resource start (limbo vehicles with no garage) get `fee = 0` automatically so players aren't charged for a crash.

---

## In-game creator

Players in a `creatorGroups` ACE group get access to the garage creator.

**Creating a garage:**
1. Open the creator menu (configured keybind).
2. Set an identifier, label, type, and optional company/fee.
3. Draw the zone boundary around the parking area.
4. Place spawn spots inside the zone.
5. Optionally place pay stations.
6. Save - the garage is live immediately with no restart.

**Deleting a garage** moves all stored vehicles to impound with a zero fine before removing it.

---

## Default garages

`data/seed_garages.ndjson` is loaded on first start when the `snowy_garages` table is empty.

The seed file only runs once. To re-seed, truncate the `snowy_garages` table and restart.

---

## Commands

| Command | Description | Usable By |
|---|---|---|
| `/impound` | Impound the nearest vehicle  | any `ImpoundJobs` jobs |
| `/impoundall` | Impound all vehicles out on the server | Admins only |
| `/admincar` | Adds the vehicle you are in to the owned vehicle list, as your vehicle | Admins only |
| `/gotovehicle [plate]` | Teleport to a vehicle by plate | Admins only |
| `/dupevehicle [plate]` | Duplicate a vehicle's data to a new plate | Admins only |

---

## Framework support

The active framework is detected automatically from which core resource is running. No config needed.

| Framework | Vehicle table | Owner column |
|---|---|---|
| QBox (`qbx_core`) | `player_vehicles` | `citizenid` |
| QBCore (`qb-core`) | `player_vehicles` | `citizenid` |
| ESX (`es_extended`) | `owned_vehicles` | `owner` |

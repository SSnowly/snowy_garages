local Config    = require "configs.shared.main"
local Framework = require "bridge.framework"

MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS `snowy_garages` (
        `id`             INT          NOT NULL AUTO_INCREMENT,
        `identifier`     VARCHAR(64)  NOT NULL,
        `label`          VARCHAR(100) NOT NULL,
        `type`           VARCHAR(20)  NOT NULL DEFAULT 'parking',
        `company`        VARCHAR(70)  DEFAULT NULL,
        `fee`            INT          DEFAULT NULL,
        `entry`          LONGTEXT     DEFAULT NULL,
        `pay_stations`   LONGTEXT     DEFAULT NULL,
        `show_blip`      TINYINT(1)   NOT NULL DEFAULT 0,
        `coords`         LONGTEXT     NOT NULL,
        `vehicle_coords` LONGTEXT     DEFAULT NULL,
        `spawns`         LONGTEXT     NOT NULL,
        `vehicle_type`   VARCHAR(10)  DEFAULT NULL,
        `zone`           LONGTEXT     DEFAULT NULL,
        `created_at`     INT          DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `snowy_garages_identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS `snowy_garages_ipl_presets` (
        `id`         INT          NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(64)  NOT NULL,
        `label`      VARCHAR(100) NOT NULL,
        `entry`      LONGTEXT     NOT NULL,
        `spawns`     LONGTEXT     NOT NULL,
        `created_at` INT          DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `snowy_garages_ipl_presets_identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

-- Add our custom columns to the vehicle table if they are missing.
-- All ALTER TABLE calls use IF NOT EXISTS so they are safe on every restart.
local vt = Config.ownedVehiclesTable

-- Impound columns needed by all frameworks (QBCore doesn't ship impound_date by default either).
MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `impound_date`   INT          DEFAULT NULL'):format(vt))
MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `impound_fine`   INT          DEFAULT NULL'):format(vt))
MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `impound_until`  INT          DEFAULT NULL'):format(vt))
MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `impound_reason` VARCHAR(128) DEFAULT NULL'):format(vt))

if Framework.isEsx then
    -- ESX owned_vehicles only has owner/plate/vehicle/stored/job by default.
    -- Add every column that snowy_garages needs and that QBCore already ships with.
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `garage`       VARCHAR(64)  DEFAULT NULL'):format(vt))
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `garageSpotID` INT          DEFAULT NULL'):format(vt))
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `netid`        INT          DEFAULT NULL'):format(vt))
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `state`        TINYINT(1)   NOT NULL DEFAULT 0'):format(vt))
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `parking_date` INT          DEFAULT NULL'):format(vt))
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `company`      VARCHAR(70)  DEFAULT NULL'):format(vt))
end

-- Sweep vehicles that have no garage and no impound_date (limbo from crashes or migrated from
-- another resource) into impound with a zero fine and no lockout so players can reclaim them.
MySQL.query.await(
    ('UPDATE `%s` SET `impound_date` = ?, `impound_fine` = 0, `impound_until` = NULL WHERE `garage` IS NULL AND `impound_date` IS NULL'):format(vt),
    { os.time() }
)

-- Seed default garages from data/seed_garages.ndjson if the table is empty.
-- The file is NDJSON: one JSON object per line, coords/spawns/zone already stored as JSON strings.
local garageCount = MySQL.scalar.await('SELECT COUNT(*) FROM `snowy_garages`')
if garageCount == 0 then
    local content = LoadResourceFile(GetCurrentResourceName(), 'data/seed_garages.ndjson')
    if content then
        local inserted = 0
        for line in content:gmatch('[^\r\n]+') do
            if line ~= '' then
                local g = json.decode(line)
                if g and g.identifier then
                    MySQL.insert.await(
                        'INSERT INTO `snowy_garages` (`identifier`, `label`, `type`, `company`, `fee`, `entry`, `pay_stations`, `show_blip`, `coords`, `vehicle_coords`, `spawns`, `vehicle_type`, `zone`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                        { g.identifier, g.label, g.type or 'parking', g.company, g.fee, g.entry, g.pay_stations, g.show_blip or 0, g.coords, g.vehicle_coords, g.spawns, g.vehicle_type, g.zone, os.time() }
                    )
                    inserted = inserted + 1
                end
            end
        end
        if inserted > 0 then
            print(('[snowy_garages] Seeded %d default garages'):format(inserted))
        end
    end
end

-- Math.lua: the geometry and the loudness curves. Nothing in here calls the game,
-- so it can be tested on its own.
local _, ns = ...

local Math = {}
ns.Math = Math

local pi, tau = math.pi, 2 * math.pi
local cos, sin, sqrt, atan2 = math.cos, math.sin, math.sqrt, math.atan2

function Math.Clamp(x, low, high)
    if x < low then return low end
    if x > high then return high end
    return x
end

-- 0 at t = 0, 1 at t = 1, with gentle shoulders at both ends.
function Math.Smoothstep(t)
    t = Math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- Positions are (north, west) in yards: the order UnitPosition returns them in.
function Math.Distance(north1, west1, north2, west2)
    local dn, dw = north2 - north1, west2 - west1
    return sqrt(dn * dn + dw * dw)
end

-- Compass direction from point 1 to point 2, in the same terms as GetPlayerFacing:
-- radians, 0 = north, growing counterclockwise (north, west, south, east).
function Math.Bearing(north1, west1, north2, west2)
    return atan2(west2 - west1, north2 - north1) % tau
end

-- Where something is compared with the way you face: 0 straight ahead, positive to
-- your left, negative to your right, +/- pi directly behind.
function Math.RelativeAngle(bearing, facing)
    local angle = (bearing - facing) % tau
    if angle > pi then angle = angle - tau end
    return angle
end

-- The point `yards` in front of a position, along `facing`.
function Math.Ahead(north, west, facing, yards)
    return north + cos(facing) * yards, west + sin(facing) * yards
end

-- How loud a voice is from its distance alone, 0..1. Full volume within `full` yards,
-- silence from `silent` on. In between it drops the way sound does in open air (the
-- level halves each time the distance doubles), eased off so it reaches nothing gently.
function Math.DistanceGain(distance, full, silent)
    if distance <= full then return 1 end
    if distance >= silent then return 0 end
    local fade = 1 - Math.Smoothstep((distance - full) / (silent - full))
    return (full / distance) * fade
end

-- Extra softening for a voice behind you. `behind` is the level straight behind (0..1);
-- beside you it is halfway. `weight` (0..1) blends the effect in, so it doesn't kick in
-- while you stand right next to the speaker.
function Math.FacingGain(angle, behind, weight)
    local level = behind + (1 - behind) * (1 + cos(angle)) * 0.5
    return 1 - weight * (1 - level)
end

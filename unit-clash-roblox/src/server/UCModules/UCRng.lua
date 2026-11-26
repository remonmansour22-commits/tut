-- Seeded RNG: faithful mulberry32 + FNV-1a port (32-bit exact via mulmod32).
-- All battle randomness flows through this so runs are reproducible.

local UCRng = {}

local function mulmod32(a, b)
	local al, ah = a % 65536, math.floor(a / 65536)
	local bl, bh = b % 65536, math.floor(b / 65536)
	return (al * bl + ((ah * bl + al * bh) % 65536) * 65536) % 4294967296
end

function UCRng.hashSeed(text)
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = mulmod32(h, 16777619)
	end
	return h
end

function UCRng.new(seed)
	local s = (seed or 1) % 4294967296
	local next
	next = function()
		s = (s + 1831565813) % 4294967296
		local t = s
		t = bit32.bxor(t, bit32.rshift(t, 15))
		t = mulmod32(t, bit32.bor(t, 1))
		t = bit32.bxor(t, (t + mulmod32(bit32.bxor(t, bit32.rshift(t, 7)), 61)) % 4294967296)
		t = bit32.bxor(t, bit32.rshift(t, 14))
		return t / 4294967296
	end
	return {
		next = next,
		range = function(_, a, b) return a + (b - a) * next() end,
		int = function(_, a, b) return a + math.floor(next() * (b - a + 1)) end,
		pick = function(_, list) return list[math.floor(next() * #list) + 1] end,
	}
end

function UCRng.deterministicSeed(base, index)
	return (base + index * 7919) % 4294967296
end

return UCRng

class_name TissueDebris
extends RefCounted

## Material variety, not anatomy.
##
## The reason gore reads as "red sparks" is that every solid bit is the same
## colour and roughly the same shape. Four restrained material classes fix that
## without going anywhere near organ simulation: pale grains among the red are
## instantly legible, and the eye reads them as matter.
##
## Palettes are deliberately close together. Fat is cream, not cartoon yellow;
## dark tissue is a deep brown-red, not black. Gore must not become confetti.

## Per-category colour, with a small jitter range so a burst is not uniform.
const COLORS := {
	BloodTypes.Tissue.FLESH: Color(0.42, 0.08, 0.07),
	BloodTypes.Tissue.FAT: Color(0.80, 0.72, 0.54),
	BloodTypes.Tissue.DARK_TISSUE: Color(0.20, 0.06, 0.05),
	BloodTypes.Tissue.THICK_BLOOD: Color(0.26, 0.015, 0.02),
}

## Relative size per category. Fat grains are small and sparse; flesh carries
## the big pieces.
const SIZES := {
	BloodTypes.Tissue.FLESH: 1.0,
	BloodTypes.Tissue.FAT: 0.62,
	BloodTypes.Tissue.DARK_TISSUE: 0.85,
	BloodTypes.Tissue.THICK_BLOOD: 0.9,
}

## How heavy each category flies. Thick blood and flesh carry; fat floats and
## drops short.
const DRAG := {
	BloodTypes.Tissue.FLESH: 1.0,
	BloodTypes.Tissue.FAT: 1.7,
	BloodTypes.Tissue.DARK_TISSUE: 1.1,
	BloodTypes.Tissue.THICK_BLOOD: 0.75,
}


static func color_for(category: BloodTypes.Tissue, rng: RandomNumberGenerator) -> Color:
	var base: Color = COLORS.get(category, COLORS[BloodTypes.Tissue.FLESH])
	var j := rng.randf_range(-0.05, 0.05)
	return Color(
		clampf(base.r + j, 0.0, 1.0),
		clampf(base.g + j * 0.5, 0.0, 1.0),
		clampf(base.b + j * 0.5, 0.0, 1.0),
		1.0
	)


static func size_for(category: BloodTypes.Tissue) -> float:
	return SIZES.get(category, 1.0)


static func drag_for(category: BloodTypes.Tissue) -> float:
	return DRAG.get(category, 1.0)


## Pick a category from a release's mixture. `roll` is a 0..1 random value.
static func pick(mix: PackedFloat32Array, roll: float) -> BloodTypes.Tissue:
	var total := 0.0
	for w in mix:
		total += w
	if total <= 0.0:
		return BloodTypes.Tissue.FLESH
	var target := roll * total
	var running := 0.0
	for i in mix.size():
		running += mix[i]
		if target <= running:
			return i as BloodTypes.Tissue
	return BloodTypes.Tissue.FLESH


## The shared low-poly library every grain and chunk is drawn from. Irregular on
## purpose: a row of identical cubes is what made the old chunks read as debris
## from a crate rather than out of a body.
static func build_meshes() -> Array[Mesh]:
	var meshes: Array[Mesh] = []

	var sliver := BoxMesh.new()
	sliver.size = Vector3(1.0, 0.28, 0.7)
	meshes.append(sliver)

	var strand := BoxMesh.new()
	strand.size = Vector3(0.35, 0.3, 1.7)
	meshes.append(strand)

	var wedge := PrismMesh.new()
	wedge.size = Vector3(1.0, 0.85, 0.75)
	meshes.append(wedge)

	var lump := SphereMesh.new()
	lump.radius = 0.55
	lump.height = 0.95
	lump.radial_segments = 5
	lump.rings = 3
	meshes.append(lump)

	var shard := PrismMesh.new()
	shard.size = Vector3(0.55, 1.2, 0.5)
	meshes.append(shard)

	var flat := BoxMesh.new()
	flat.size = Vector3(1.3, 0.18, 1.0)
	meshes.append(flat)

	return meshes

# build_randomizers.gd — wraps each sound's chosen takes into one AudioStreamRandomizer (docs/sound_design.md §7.3)
#
# Run it after process_sfx.sh and after you've picked the takes (rejects moved to tools/sfx/rejected/):
#   godot --headless --path . --import                                               # import the new WAVs first
#   godot --headless --path . --script res://tools/sfx/build_randomizers.gd
#   godot --headless --path . --script res://tools/sfx/build_randomizers.gd -- --dry-run   # report only
#   ... -- --sfx-dir=res://some/folder     # read takes from (and save the .tres files in) another folder (for tests)
#
# For every one-shot id in audio/sound_bank.gd it takes the WAVs in audio/sfx/<id>/ and saves audio/sfx/<id>.tres
# (the path the registry expects). Loops are skipped: they are played straight from audio/loops/<id>.ogg.
# Variation:
#   SFX bus:       random take (never the same twice in a row), +-1 semitone random pitch, +-2 dB random volume
#   UI and Music:  random take and +-1 dB volume only, so chimes and stingers stay in key
extends SceneTree

const SoundBank = preload("res://audio/sound_bank.gd")
const SFX_DIR := "res://audio/sfx"
var _sfx_dir: String = SFX_DIR
const PITCH_SEMITONES := 1.0      # spec: about +-1 semitone
const PITCH_FALLBACK := 1.06      # random_pitch (a scale) for Godot versions without random_pitch_semitones
const VOLUME_DB_SFX := 2.0
const VOLUME_DB_OTHER := 1.0

func _init() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry-run")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sfx-dir="):
			_sfx_dir = arg.get_slice("=", 1).trim_suffix("/")
	var built: Array[String] = []
	var missing: Array[String] = []
	var errors: Array[String] = []
	for id in SoundBank.SOUNDS:
		var entry: Dictionary = SoundBank.SOUNDS[id]
		if entry.get("loop", false):
			continue
		var takes := _takes(String(id))
		if takes.is_empty():
			missing.append(String(id))
			continue
		var streams: Array[AudioStream] = []
		for path in takes:
			var stream := load(path) as AudioStream
			if stream == null:
				errors.append("%s could not be loaded (run godot --headless --path . --import first)" % path)
			else:
				streams.append(stream)
		if streams.size() != takes.size():
			continue
		var randomizer := _randomizer(streams, entry.get("bus", &"SFX"))
		var out: String = entry.get("path", "%s/%s.tres" % [SFX_DIR, id])
		if _sfx_dir != SFX_DIR:
			out = "%s/%s.tres" % [_sfx_dir, id]
		if dry:
			built.append("%s: %d take(s) -> %s" % [id, streams.size(), out])
			continue
		var err := ResourceSaver.save(randomizer, out)
		if err != OK:
			errors.append("could not save %s (error %d)" % [out, err])
		else:
			built.append("%s: %d take(s) -> %s" % [id, streams.size(), out])

	print("%s %d randomizer(s):" % ["Would build" if dry else "Built", built.size()])
	for line in built:
		print("  " + line)
	if not missing.is_empty():
		print("%d one-shot id(s) have no takes yet (they stay silent): %s" % [missing.size(), ", ".join(missing)])
	for e in errors:
		printerr("  ERROR: " + e)
	if dry:
		print("Dry run: nothing was saved.")
	quit(1 if not errors.is_empty() else 0)

# The WAV takes in audio/sfx/<id>/, sorted
func _takes(id: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("%s/%s" % [_sfx_dir, id])
	if dir == null:
		return out
	for file in dir.get_files():
		if file.get_extension().to_lower() == "wav":
			out.append("%s/%s/%s" % [_sfx_dir, id, file])
	out.sort()
	return out

func _randomizer(streams: Array[AudioStream], bus: StringName) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for s in streams:
		r.add_stream(-1, s, 1.0)
	# "no repeats" needs at least two takes to choose from
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS if streams.size() >= 2 else AudioStreamRandomizer.PLAYBACK_RANDOM
	var is_sfx := bus == &"SFX"
	if is_sfx:
		if _has_property(r, "random_pitch_semitones"):
			r.set("random_pitch_semitones", PITCH_SEMITONES)
		else:
			r.random_pitch = PITCH_FALLBACK
	r.random_volume_offset_db = VOLUME_DB_SFX if is_sfx else VOLUME_DB_OTHER
	return r

func _has_property(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if p.name == prop:
			return true
	return false

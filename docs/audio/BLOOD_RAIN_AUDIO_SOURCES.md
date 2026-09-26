# Blood rain: original recording provenance and acquisition blocker

Access date: **2026-09-24**. Source site: **Freesound**, original uploader pages below. Each listed license was independently checked: **Creative Commons Zero (CC0 1.0)**. [License terms](https://creativecommons.org/publicdomain/zero/1.0/).

**No external audio is integrated yet.** The original download links require a logged-in account. No authentication bypass, protected-download scraping, game/video rip, or preview transcoding was performed. No source was downloaded, auditioned or processed; selection below is a provisional metadata shortlist, not an auditory endorsement. Production noise-generated rain has been removed. Until processed originals are supplied, missing categories are silent and counted by `missing_foley_events`; startup emits one warning.

## Exact download shortlist

| Source title | Author | ID / original source | License | Original filename |
|---|---|---|---|---|
| Water_Drip_One_Shot_2.wav | michael_grinnell | [464411](https://freesound.org/people/michael_grinnell/sounds/464411/) | CC0 | `464411__michael_grinnell__water_drip_one_shot_2.wav` (download-link filename) |
| Water drop (splash) | bolkmar | [451126](https://freesound.org/people/bolkmar/sounds/451126/) | CC0 | WAV; exact original download filename pending authenticated acquisition |
| water_drop.wav | velkstar | [425209](https://freesound.org/people/velkstar/sounds/425209/) | CC0 | title `water_drop.wav`; full download filename pending acquisition |
| Various Water Splashes | NichelleMedia | [614850](https://freesound.org/people/NichelleMedia/sounds/614850/) | CC0 | WAV; exact original filename pending acquisition |
| Tomato squish;wet.wav | HonorHunter | [271666](https://freesound.org/people/HonorHunter/sounds/271666/) | CC0 | title `Tomato squish;wet.wav`; full download filename pending acquisition |
| AMB_Ext_Rain_Courtyard_Close_002.wav | conleec | [149237](https://freesound.org/people/conleec/sounds/149237/) | CC0 | `149237__conleec__amb_ext_rain_courtyard_close_002.wav` (download-link filename) |

Verified but not selected: [410335 Water drop / Splash, bxyorna](https://freesound.org/people/bxyorna/sounds/410335/) CC0, AIFF; [673286 Rain drops on concrete and plastic container, felix.blume](https://freesound.org/people/felix.blume/sounds/673286/) CC0, WAV. The latter may contain container resonance; no listening judgment was made. Other candidates were not integrated or assumed licensed. No Sonniss bundle needed to be shipped or downloaded.

The 464411 and149237 original download links were opened and did not yield an audio file through the available unauthenticated access. Their source pages explicitly show Login to download. Obtain originals using normal Freesound login; preserve them under `assets/audio/blood/source/`. Do not put raw multi-minute material into the runtime bank.

## Expected game-ready bank (hooks implemented, files currently absent)

All paths start `assets/audio/blood/processed/`. The bank has **17 fixed optional slots**, loaded once. It refuses non-mono, non-48kHz, non-PCM16, looping or >1.2s samples. Godot import must retain PCM16, mono48k and loop disabled. A missing category does not substitute procedural noise or an unrelated category.

| Expected GAME FILE(s) | Planned source IDs | Category / intended preparation — NOT processing already performed |
|---|---|---|
| `blood_drop_small_01.wav` | 464411 | trim recorded drop; mono48k PCM16; short fades, conservative peak |
| `blood_drop_small_02.wav` | 425209 | alternative quiet transient; same format |
| `blood_drop_small_03.wav` | 451126 | smaller isolated portion; same format |
| `blood_splash_medium_01.wav`, `blood_splash_medium_02.wav` | 451126 / 614850 | two clean recorded splash transients, <=0.45s |
| `blood_splat_heavy_01.wav`, `blood_splat_heavy_02.wav` | 614850 + 271666 | recorded splash with quiet viscous layer, <=0.6s; no comic squish |
| `blood_pool_impact_01.wav`, `blood_pool_impact_02.wav` | 614850 | softer recorded wet contact, optionally subtle271666; <=0.5s |
| `blood_rain_sparse_01.wav`, `blood_rain_sparse_02.wav` | 464411 / 425209 / 451126 | offline edit of several irregular real ticks, about0.24–0.35s |
| `blood_rain_patter_01.wav`, `blood_rain_patter_02.wav` | 149237 | selected close patter excerpts, about0.4–0.55s |
| `blood_rain_dense_01.wav`, `blood_rain_dense_02.wav` | 149237 | denser clean excerpts with occasional wet transient, about0.6–0.8s |
| `blood_rain_heavy_01.wav`, `blood_rain_heavy_02.wav` | 149237 / 614850 | dense irregular recorded texture, about0.8–1.1s, not louder static noise |

Before integrating EACH output, add an entry recording actual original filename, source ID(s), SHA256 of original/output, exact trim intervals and actual processing. Remove unused proposed slots if listening warrants a smaller bank. License verification does not certify sonic suitability.

Recommended offline preparation: audition and mark exact ranges; trim excess silence; remove DC only if present; mild corrective EQ only when necessary; mono conversion; one resample to48k; 2–5ms entry fade preserving transient and10–20ms exit fade; conservative peak/gain matching. Do not normalize every source to the same perceived loudness. Never transcode through lossy previews. Layer viscosity offline to avoid extra impact voices. No cuts/normalization/listening were completed in this task because originals are unavailable.

## Runtime behavior / current validation limit

Six existing spatial voices;32 clusters;128 recent impacts;2 starts/frame. Tier0 selects small/medium/heavy or wet variants. Higher tiers select authored sparse/patter/dense/heavy clips, with mild pitch/gain variation and actual clip duration. Wet dense events retain the patter bed and slightly lower pitch/gain; they no longer replace the entire bed with one wet plop. No global loop. No loading or stream creation per impact.

Playback telemetry includes the **actual resource path** under `last_events[].sample`. With no originals installed, actual real samples played = **NONE**, not a successful foley validation. The automated missing-bank check verifies silence/capacity and absence of a synthetic substitute; it does not claim audio acceptance. The acquisition blocker is SOURCE MATERIAL, before MIXING/ATTENUATION/SURFACE RESPONSE can be judged.

## Hard correction pass checkpoint (2026-09-24)

The six shortlisted uploader pages were rechecked during this pass: CC0 is still displayed and original downloads still require login. **FOLEY ASSETS REQUIRE MANUAL PLAYER DOWNLOAD.** No originals were acquired or processed; no production file can be claimed as played. Do not describe the bank as final sound design.

F10 now toggles `blood_impact_audio_debug` in development builds. With valid processed assets installed, it sets an obvious isolated diagnostic playback level (-6dB). The bounded playback trace records drop ID, stream path, volume, pitch, position, bus, attenuation model, unit size, maximum distance and `playing`. Without files, `last_missing_impact` records the concrete collision and missing category. It never synthesizes a replacement.

Checkpoint G (one audible REAL ground impact) remains blocked at stream selection. Checkpoint H (dense patter listening/mix) was intentionally not tuned ahead of G. The existing six-voice /32-cluster architecture and17 optional preloaded clip slots are retained. After acquisition, audition and process first; then validate isolated close contact before testing5/20/50/100 impacts.

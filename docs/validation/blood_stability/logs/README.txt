Logs retained from this implementation pass. Authoritative final runs:
- after.log / after_err.log: final native Compatibility multi-hit benchmark, exit 0.
- verified_stability_native*: final rendered stability fixture, exit 0.
- verified_stability_headless*, verified_stability_repeat*, verified_material*: final ordinary headless runs; functional assertions passed but shutdown exited -1073741819.
- release_stability*, release_material*: diagnostic headless runs with verbose; exit 0, not proof the intermittent shutdown failure is fixed.
- final_blood_phase2*, final_blood_phase21*, final_blood_phase22*, final_blood_phase23*, final_movement_smoke*: earlier completed regressions.
- before.log and warm_control.log: baseline and separate first-draw preparation control.
Other delivery/final logs are retained historical intermediate runs; do not infer final success from those filenames.
See ../teardown_runs.json and ../delivery_summary.json for process status, and the main report for limitations.
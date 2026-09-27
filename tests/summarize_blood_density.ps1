param([string]$Mode='headless')
$path='docs/validation/blood_density'
$data=Get-Content "$path/$Mode.json" -Raw | ConvertFrom-Json
function Stats($values) {
    $a=@($values|Sort-Object)
    if(!$a.Count){return $null}
    return @{mean=($a|Measure-Object -Average).Average/1000;p95=$a[[math]::Ceiling(.95*$a.Count)-1]/1000;peak=$a[-1]/1000}
}
$rows=@($data.rows|ForEach-Object {@{gain=$_.gain;weapon=$_.weapon;victims=$_.victims;events=$_.events;accepted_mass=$_.accepted_mass;representative_peak=$_.peak;streak_peak=$_.trails;streak_demand=$_.demand;surface_peak=$_.surface_peak;quad_area=$_.aftermath.all_active_quad_area;queries=$_.queries;budgets=$_.budgets;physical_cpu_ms=(Stats $_.cpu);stages_cpu_ms=(Stats $_.stage_cpu)}})
$comparison=@($rows|Where-Object {$_.gain -eq 1.5}|ForEach-Object {
    $after=$_;$before=$rows|Where-Object {$_.gain -eq 1 -and $_.weapon -eq $after.weapon -and $_.victims -eq $after.victims}
    @{weapon=$after.weapon;victims=$after.victims;before=$before;after=$after;mass_ratio=$after.accepted_mass/[math]::Max(.00001,$before.accepted_mass);area_ratio=$after.quad_area/[math]::Max(.00001,$before.quad_area)}
})
@{failures=$data.failures;comparison=$comparison}|ConvertTo-Json -Depth 8|Set-Content "$path/${Mode}_summary.json"
$comparison|ForEach-Object {[pscustomobject]@{weapon=$_.weapon;victims=$_.victims;mass_ratio=[math]::Round($_.mass_ratio,2);area_ratio=[math]::Round($_.area_ratio,2);reps_before=$_.before.representative_peak;reps_after=$_.after.representative_peak;mean_before=$_.before.physical_cpu_ms.mean;mean_after=$_.after.physical_cpu_ms.mean}}|Format-Table -AutoSize

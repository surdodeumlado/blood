param([string]$Phase='baseline',[string]$Mode='headless')
$path='docs/validation/blood_weapon_signature'
$data=Get-Content "$path/${Phase}_${Mode}.json" -Raw | ConvertFrom-Json
function Distribution($values) {
    $a=@($values|Sort-Object)
    if (!$a.Count) { return @{n=0} }
    return @{n=$a.Count;p50=$a[[math]::Ceiling(.50*$a.Count)-1];p90=$a[[math]::Ceiling(.90*$a.Count)-1];p99=$a[[math]::Ceiling(.99*$a.Count)-1];max=$a[-1]}
}
$result=@($data.rows | ForEach-Object {
    $r=$_; $hits=@($r.impacts);$births=@($r.births)
    $hist=@(); $edges=@(0,2,5,10,15,[double]::PositiveInfinity)
    for($i=0;$i -lt 5;$i++) {
        $bucket=@($hits|Where-Object {$_.range -ge $edges[$i] -and $_.range -lt $edges[$i+1]})
        $hist+=@{from=$edges[$i];count=$bucket.Count;percent=100*$bucket.Count/[math]::Max(1,$hits.Count);mass=($bucket.mass|Measure-Object -Sum).Sum}
    }
    $major=@($hits|Where-Object {$_.range -ge 5 -and $_.mass -ge .0005 -and ($_.kind -ge 2 -or $_.mass -ge .001) -and $_.relevant -ge .05})
    $poor=@($major|Where-Object {$_.relevant_ratio -lt .1})
    $walls=@($major|Where-Object {$_.wall -or $_.position -match '^\(40\.0,'})
    $wallTrace=@($walls|ForEach-Object {
        $hit=$_
        $stains=@($r.stains|Where-Object {$_.drop -eq $hit.id -and $_.event -eq $hit.event})
        @{id=$hit.id;event=$hit.event;kind=$hit.kind;mass=$hit.mass;speed=$hit.speed;range=$hit.range;life=$hit.life;visible=$hit.visible;camera_relevant=$hit.relevant;visible_ratio=$hit.ratio;relevant_ratio=$hit.relevant_ratio;stain_width=($stains.width|Measure-Object -Maximum).Maximum;matched_stains=$stains.Count}
    })
    $classes=@(2,3,4,5|ForEach-Object {$kind=$_;$b=@($births|Where-Object {$_.kind -eq $kind});@{kind=$kind;count=$b.Count;speed=(Distribution $b.speed);diameter=(Distribution $b.diameter)}})
    $castoff=@($births|Where-Object {$_.castoff})
    $cpu=@($r.cpu|Sort-Object)
    @{weapon=$r.weapon;wall=$r.wall;victims=$r.victims;capture=$r.capture;telemetry=$r.telemetry;birth_count=$births.Count;speed=(Distribution $births.speed);angle=(Distribution $births.angle);range=(Distribution $hits.range);life=(Distribution $hits.life);histogram=$hist;histogram_mass_is_birth_proxy=($Phase -eq 'baseline');classes=$classes;castoff=@{count=$castoff.Count;speed=(Distribution $castoff.speed);angle=(Distribution $castoff.angle)};wall_trace=$wallTrace;major_far=$major.Count;poor_far=$poor.Count;visibility=(Distribution $major.relevant_ratio);coarse_marks=@($r.stains|Where-Object {$_.coarse -and $_.mass -gt 0}).Count;cpu_mean=($cpu|Measure-Object -Average).Average;cpu_p95=$cpu[[math]::Ceiling(.95*$cpu.Count)-1];cpu_peak=$cpu[-1];peak=$r.peak;streak_peak=$r.streak_peak;demand_peak=$r.demand_peak;queries=$r.queries;budgets=$r.budgets;ledger=$r.ledger;sources=$r.sources;source_peak=$r.source_peak}
})
$result|ConvertTo-Json -Depth 8|Set-Content "$path/${Phase}_${Mode}_summary.json"
$result|Where-Object {$_.wall -eq 18}|ForEach-Object {[pscustomobject]@{weapon=$_.weapon;victims=$_.victims;births=$_.birth_count;speed50=$_.speed.p50;speed99=$_.speed.p99;range50=$_.range.p50;range90=$_.range.p90;range99=$_.range.p99;max=$_.range.max;far=$_.major_far;poor=$_.poor_far;coarse=$_.coarse_marks}}|Format-Table -AutoSize

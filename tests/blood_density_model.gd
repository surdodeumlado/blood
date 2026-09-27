extends SceneTree
const OUT := "res://docs/validation/blood_density/"
var failures:Array[String]=[]
func check(ok:bool,why:String)->void:
	if not ok:failures.append(why);push_error(why)
func _initialize()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var rows:Array=[]
	for family in [0,1,3,4]:
		for kill in [false,true]:
			for head in [false,true] if family==0 else [false]:
				var releases:Array[BloodRelease]=[]
				for gain in [1.0,1.5]:
					var cfg:ReservoirConfig=load("res://data/blood/reservoir_defaults.tres").duplicate()
					cfg.blood_quantity_multiplier=gain
					var reservoir:=BloodReservoir.new();reservoir.config=cfg;reservoir.refill()
					var ctx:=BloodContext.make(family,Vector3(0,1.6,0),Vector3.FORWARD,BloodTypes.BodyRegion.HEAD if head else BloodTypes.BodyRegion.TORSO)
					ctx.is_kill=kill;ctx.weapon_velocity_ws=Vector3(10,0,0)
					var rel:=reservoir.withdraw(ctx);releases.append(rel)
					check(absf(reservoir.remaining_blood+rel.blood_mass-cfg.max_blood*gain)<.00001,"reservoir conserves extra mass")
					reservoir.free()
				var a:=releases[0];var b:=releases[1]
				check(is_equal_approx(b.blood_mass,a.blood_mass*1.5),"50 percent real release gain")
				check(is_equal_approx(a.emission_mass(),b.emission_mass()),"launch reference unchanged")
				check(is_equal_approx(a.tissue_mass,b.tissue_mass),"solid material unchanged")
				var samples:Array=[]
				for rel in releases:
					var rng:=RandomNumberGenerator.new();rng.seed=91
					var pattern:=BloodPattern.for_family(family);pattern.begin(rel,Basis.IDENTITY,rng)
					var sample:Array=[]
					for i in 32:
						pattern.sample(BloodTypes.Layer.MEDIUM,float(i)/32)
						sample.append([pattern.out_origin,pattern.out_dir,pattern.out_speed])
					samples.append(sample)
				for i in 32:
					check(Vector3(samples[0][i][0]).distance_to(samples[1][i][0])<.00001 and Vector3(samples[0][i][1]).distance_to(samples[1][i][1])<.00001 and is_equal_approx(samples[0][i][2],samples[1][i][2]),"pattern launch preserved")
				rows.append({"family":family,"kill":kill,"head":head,"before":a.blood_mass,"after":b.blood_mass,"emission_before":a.emission_mass(),"emission_after":b.emission_mass()})
	# Blade load remains the same, increased liquid stays in the impact spray.
	var r:=BloodRelease.make(null,.6);r.quantity_multiplier=1.5
	r.blood_mass-=.02;r.contact_retained_mass=.02
	check(is_equal_approx(r.emission_blood_mass(),.38),"retention sampling reference")
	var file:=FileAccess.open(OUT+"model.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"failures":failures},"\t"));file.close()
	print("DENSITY_MODEL failures=",failures.size());quit(failures.size())

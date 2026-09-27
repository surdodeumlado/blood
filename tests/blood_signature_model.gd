extends SceneTree
var failures:Array[String]=[]
func verify(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:
	# Rotation covariance: the opposite blade motion must rotate the complete
	# physical fan, including its origins, without changing speed or mass.
	var streams:Array=[]
	for side in [1.0,-1.0]:
		var ctx:=BloodContext.make(BloodTypes.DamageType.SLASHING,Vector3.ZERO,Vector3.FORWARD*side,BloodTypes.BodyRegion.TORSO)
		ctx.weapon_velocity_ws=Vector3.RIGHT*10*side
		var rng:=RandomNumberGenerator.new();rng.seed=77
		var p:=SlashingPattern.new()
		p.begin(BloodRelease.make(ctx,.4),Basis(Vector3.UP,0 if side>0 else PI),rng)
		var samples:Array=[]
		var mean:=Vector3.ZERO
		for i in 128:
			p.sample(BloodTypes.Layer.MEDIUM,float(i)/127)
			mean+=p.out_dir
			samples.append([p.out_dir,p.out_origin,p.out_speed])
		verify(mean.normalized().dot(ctx.weapon_velocity_ws.normalized())>.95,"slash mean follows actual blade tangent")
		streams.append(samples)
	for i in 128:
		verify(Vector3(streams[0][i][0]).rotated(Vector3.UP,PI).distance_to(streams[1][i][0])<.00001,"opposite blade fan rotation")
		verify(Vector3(streams[0][i][1]).rotated(Vector3.UP,PI).distance_to(streams[1][i][1])<.00001,"opposite blade origin rotation")
		verify(absf(streams[0][i][2]-streams[1][i][2])<.00001,"opposite blade speed preserved")
	var s:=BloodStabilitySettings.new()
	var major:=BloodFlightPresentation.trail_priority(3,Vector3(20,0,0),400,true,s,.003)
	var noise:=BloodFlightPresentation.trail_priority(2,Vector3(25,0,0),16,true,s,.0001)
	var offscreen:=BloodFlightPresentation.trail_priority(3,Vector3(20,0,0),4,false,s,.003)
	verify(major<noise and major<offscreen,"major far transport not starved by near noise/offscreen")
	var file:=FileAccess.open("res://docs/validation/blood_weapon_signature/model.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"samples":128,"priority_major":major,"priority_noise":noise,"priority_offscreen":offscreen},"\t"));file.close()
	print("SIGNATURE_MODEL failures=",failures.size())
	quit(failures.size())

extends SceneTree
const DEST := "res://docs/validation/blood_trajectory_recovery/"
var failures: Array[String] = []
func verify(ok: bool, why: String) -> void:
	if not ok: failures.append(why); push_error(why)

func old_assist(v: Vector3, y: float, kind: int, dt: float, s: BloodStabilitySettings) -> Vector3:
	if v.y >= -.15: return v
	var target: float = [7,9.5,11,12][kind-2]
	var cap: float = [9,11,13,14][kind-2]
	if v.y > -target: v.y=minf(v.y,maxf(-target,minf(v.y,y)-35*dt))
	v.y=maxf(v.y,-cap)
	return v

func _initialize() -> void:
	var p: BloodPhysicsSettings=load("res://data/blood/blood_physics.tres")
	var s:=BloodStabilitySettings.new()
	var rows: Array=[]
	for kind in [2,3,4,5]:
		var d: float=[.0007,.001985,.0035,.0065][kind-2]
		for launch in [Vector3(8,6,0),Vector3(8,0,0),Vector3(8,-6,0),Vector3(5,14,0),Vector3(10,1,0)]:
			for old in [true,false]:
				var v: Vector3=launch
				var pos:=Vector3.ZERO
				var trace: Array=[]
				var apex:=-1
				var peak_y:=0.0
				for i in 480:
					var previous:=v
					v=BloodFluidModel.advance_velocity(v,d,1.0/120,Vector3.DOWN*9.81,p)
					v=old_assist(v,previous.y,kind,1.0/120,s) if old else BloodFluidModel.assist_descent(v,previous.y,kind,d,1.0/120,s)
					pos+=v/120
					peak_y=maxf(peak_y,pos.y)
					if apex<0 and v.y<0: apex=i
					trace.append({"t":float(i+1)/120,"position":[pos.x,pos.y,pos.z],"v":[v.x,v.y,v.z],"ay":(v.y-previous.y)*120,"turn_degrees":rad_to_deg(previous.angle_to(v)),"weight":(1.0 if v.y<-.15 else 0.0) if old else BloodFluidModel.descent_weight(previous.y)})
				var window:=trace.slice(maxi(0,apex-4),apex+5)
				rows.append({"kind":kind,"diameter":d,"launch":[launch.x,launch.y,launch.z],"old":old,"apex":apex,"peak_y":peak_y,"apex_window":window,"trace":trace,"v_at_300ms_after_apex":trace[mini(apex+36,479)].v[1]})
				if not old:
					verify(absf(peak_y-float(rows[-2].peak_y))<.04,"high arc height preserved within4cm")
					if kind==3: verify(float(trace[apex+36].v[1]) < -8,"medium fast by300ms")
	# Force continuity at both joins and no velocity snap for an over-speed drop.
	for y in [.5,0.0,-3.0,-7.6,-11.0,-13.0]:
		var a:=BloodFluidModel.assist_descent(Vector3(4,y-.00001,2),y-.00001,3,.001985,.001,s)
		var b:=BloodFluidModel.assist_descent(Vector3(4,y+.00001,2),y+.00001,3,.001985,.001,s)
		verify(absf((a.y-y+.00001)-(b.y-y-.00001))<.00001,"continuous force join")
	var fast:=BloodFluidModel.assist_descent(Vector3(4,-25,2),-25,3,.001985,1.0/120,s)
	verify(absf(fast.y+25)<=35.0/120+.0001 and fast.x==4 and fast.z==2,"bounded force, no cap snap, XZ retained")
	var f:=FileAccess.open(DEST+"trajectory_model.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows":rows,"failures":failures},"\t"));f.close()
	print("TRAJECTORY_MODEL_SAVED failures=",failures.size())
	quit(failures.size())

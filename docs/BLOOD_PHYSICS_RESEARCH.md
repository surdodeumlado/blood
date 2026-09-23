# Blood material research and implementation contract

Research date: 21 September 2026. This document was written before the material implementation. It describes a game model, **not forensic validation**, a clinical model, or an instrument for inferring weapons from stains. SI units apply to physical diameter, velocity and fluid properties. Reservoir units remain gameplay quantities; a representative carries a parcel of many equivalent droplets, not one enormous droplet.

## Evidence and uncertainty

The [OSAC proposed methodology](https://www.nist.gov/document/osac-2022-s-0030-standard-methodology-bloodstain-pattern-analysisopen-comment-version) describes examination and interpretation; it is not a numerical fluid specification or certification for this game. The [NIJ black-box study](https://nij.ojp.gov/library/publications/black-box-evaluation-bloodstain-pattern-analysis-conclusions) found consequential errors and disagreement among analysts. Similar patterns can arise from different events. Surface, blood condition, geometry, initial motion, sampling and observer uncertainty matter. We generate plausible forward effects; we do not solve the inverse forensic problem.

The general scientific framework is [Attinger et al., 2013](https://pubmed.ncbi.nlm.nih.gov/23830178/) (review, DOI 10.1016/j.forsciint.2013.04.018). Detailed coefficients below come from narrower experiments or explicitly identified approximations. Abstract-only evidence is identified. Water, simulant and air-jet results are not relabelled as measurements of human blood.

## 1. Rheology

**Measured science.** Blood is a suspension with shear-dependent viscosity. The whole-blood impact experiments and literature table in [Yokoyama, Tanaka and Tagawa](https://arxiv.org/html/2201.06673) report human density about 1050–1063 kg/m³, surface tension about 48–63 mN/m and high-shear viscosity about 3.8–5.6 mPa·s. Their tested fluid was dog blood, not human blood. Rapid spreading can approach an effective Newtonian response; low-shear flow, plasma elasticity, cells, temperature and clotting limit that approximation. Their Weber and Reynolds definitions use **radius**, whereas this implementation uses **diameter**. Numerical thresholds must not be copied without conversion.

**Confidence / relevance.** High confidence in the qualitative distinction; representative constants are not universal biological constants. [Raymond et al.](https://pubmed.ncbi.nlm.nih.gov/8789932/) examine species, temperature and sample-age limitations (abstract consulted). [Stotesbury et al.](https://pubmed.ncbi.nlm.nih.gov/27874180/) support effective-viscosity spreading models under their passive-drop conditions (abstract consulted).

**Game approximation.** Default density 1055 kg/m³, dynamic viscosity 0.0048 Pa·s and surface tension 0.060 N/m; expose all in a resource. Use effective viscosity for fast flight/impact diagnostics. Slow runoff uses wet mass, retention and mobility parameters, not the same Newtonian assumption. No coagulation, hematocrit, infection or temperature simulation.

**Artistic exaggeration.** Reservoir mass is not asserted to be a human body's blood volume. A configurable conversion from reservoir units to kilograms is a gameplay calibration used only for surface retention; representative multiplicity is separate from physical drop size.

## 2. Formation, sheets, ligaments and size distributions

**Measured science.** Inertial liquid motion can form sheets and ligaments, then droplets. Surface tension resists new interface. [NIJ's ultrafast visualization work](https://nij.ojp.gov/library/publications/ultrafast-3d-visualization-and-fluid-dynamic-mechanisms-blood-atomization) studies mechanisms from blunt to projectile events. [Comiskey, Yarin and Attinger, 2019](https://nij.ojp.gov/library/publications/hydrodynamics-forward-blood-spattering-caused-bullet-general-shape) model instability and fragmentation, including ligament viscoelasticity, in forward spatter (primary paper summary consulted).

**Confidence / relevance.** High confidence in fragmentation mechanisms; no universal distribution follows from a weapon label. Tissue geometry, liquid loading and energy coupling are unmeasured in this game.

**Game approximation.** Sample broad, overlapping diameter distributions: fine 0.08–0.35 mm, small 0.35–1 mm, medium 1–2 mm, large 2–4 mm, rare globs 4–8 mm. These bands are chosen simulation bins, not measured forensic categories. Existing pattern axes and local origins supply motion. High-energy/blunt events may assign a small fraction to short ligaments. No sheet solver.

**Artistic exaggeration.** Bounded log-uniform fine/small bands, uniform coarse bands, and event mixture weights are authored. These are not a fitted experimental size distribution. Violent events need not reproduce a particular experiment's counts.

## 3. Flight, drag and gravity

**Measured science.** Aerodynamic deceleration depends strongly on diameter. Gravity curves trajectories. [Laan et al., 2015](https://www.nature.com/articles/srep11461) demonstrate why straight-line assumptions can fail in their controlled patterns. That result does not validate arbitrary reconstruction.

**Game approximation.** Fixed-step swept point trajectories. Read world gravity, without changing player gravity. With air density 1.204 kg/m³ and viscosity 1.81e-5 Pa·s, calculate Re_air = rho_air |v| d / mu_air. Use the Schiller–Naumann sphere approximation: Cd = 24/Re (1 + 0.15 Re^0.687) below Re=1000, otherwise 0.44; see the [OpenFOAM reference implementation](https://cpp.openfoam.org/v12/SchillerNaumann_8C_source.html). Acceleration magnitude is 3 rho_air Cd |v|² / (4 rho_blood d). Apply a non-reversing implicit-speed drag step, then gravity; substep the fixed update. An equivalent drop has mass rho_blood πd³/6, while represented parcel mass determines deposition. A parcel's multiplicity does not increase its equivalent diameter.

**Confidence / limitations.** Established engineering approximation for isolated spheres, not validated for deforming blood packets or dense spray. No collective shielding, wind, droplet coalescence or two-way air coupling. Small droplets should lose launch momentum sooner, irrespective of rendering size.

**Artistic exaggeration.** Initial launch speeds remain family-authored game inputs. Mist density is a visual sampling decision.

## 4. Airborne shape

**Measured science.** Surface tension favours spheres. Formation excites oscillations; aerodynamic forcing can flatten/deform drops rather than simply stretch them into velocity-aligned rods. This [water-drop oscillation study](https://arxiv.org/abs/2003.07785) provides a primary experimental/numerical example (preprint consulted; water, not blood).

**Game approximation.** All airborne liquid uses a unit-diameter low-poly sphere, with smooth normals. Ordinary drops have modest bounded ellipsoidal deformation. Thin ligaments use the same rounded geometry with separately bounded length and short lifetime. Tissue alone uses angular fragments. Physical and rendered diameters are stored separately.

**Artistic exaggeration.** A roughly 8× diameter readability factor, a minimum readable bead size, and modest velocity elongation are deliberate. Hard maximum ordinary diameter 4.5 cm, glob 6 cm, ligament length 12 cm. These are caps, not typical sizes. No ordinary liquid box or unconstrained velocity multiplier is permitted. Velocity elongation is a visual cue, not a claim about measured equilibrium shape.

## 5. Aerodynamic breakup

**Measured science.** Gas Weber number We_air = rho_air v²d/sigma compares air forcing to capillarity. Low-viscosity drop experiments support bag-breakup onset of order We≈12, with dependencies on viscosity, forcing history and flow configuration. [Kulkarni and Sojka](https://arxiv.org/abs/2204.06036) is an air-jet study (preprint consulted). The [Pilch–Erdman engineering implementation](https://cpp.openfoam.org/v10/PilchErdman_8C_source.html) includes Ohnesorge dependence; this is a model reference, not new blood evidence.

**Game approximation.** Use Oh = mu_blood/sqrt(rho_blood sigma d) and a threshold 12(1+1.077 Oh^1.6), with a finite exposure time. Split at most into two children, with a generation limit and free-slot check. Child equivalent volume and represented mass sum to the parent's. Ligaments collapse or split after a brief capillary-inspired lifetime. Failed admission retains the parent's mass.

**Artistic exaggeration / limits.** Two representatives cannot resolve atomization. Ligament formation probability is authored. Air breakup and surface splash use different densities and different criteria; never share their Weber threshold.

## 6. Surface impact and satellites

**Measured science.** Diameter, speed, incidence, viscosity, capillarity and surface properties affect spreading and splash. Whole blood may form fingers without the fine particle ejection seen in some hard-particle simulants ([Yokoyama et al.](https://arxiv.org/html/2201.06673)). Wettability can change splash thresholds even at comparable roughness ([oblique-impact experiments](https://pubmed.ncbi.nlm.nih.gov/26318736/), abstract consulted). There is no universal blood splash constant for all game walls.

**Game approximation.** Compute liquid We_normal = rho_blood v_normal²d/sigma and Re_normal = rho_blood v_normal d/mu_blood. Use bounded spread influenced by capillary/inertial and viscous scales, then classify DEPOSIT, SPREAD, SPLASH, GLANCING or HEAVY_GLOB. The resulting bounded coefficients select a stain morphology and satellite budget. Satellites occur only when the impact/surface criterion is met, and their mass is subtracted from the parent. Each satellite is projected to actual nearby collision geometry; a failed satellite ray returns its mass to the parent.

**Confidence / relevance.** Qualitative dependencies are grounded; thresholds and blending are phenomenological. Crown dynamics, dynamic contact angle and rebound are not simulated. Ordinary blood is assumed to wet these game surfaces rather than bounce elastically.

**Artistic exaggeration.** Parcel stains preserve the existing readable mass-to-area mapping. They are not the literal footprint of a single millimetre drop. Increased irregularity is an atlas choice, not a resolved fluid edge.

## 7. Incidence and stain direction

**Measured science.** Width/length ≈ sin(incidence) is conditional. [Smith, Lockard and Neitzel's controlled study](https://meetings-archive.aps.org/dfd/2015/m32/8/) reports increasing departures at shallow angles and with roughness (conference abstract). [NIJ's inclined-impact project](https://nij.ojp.gov/index.php/library/publications/fluid-dynamics-droplet-impact-inclined-surfaces-application-forensic-blood) used simulants and multiple substrates. Its [later report](https://www.ojp.gov/pdffiles1/nij/grants/310654.pdf) explicitly reports incomplete experimental work and unresolved simulated rebound; it is not a finished calibration dataset.

**Game approximation.** Project incoming velocity onto the surface. Align the long axis with that tangent. Use a regularized, bounded aspect ratio rather than unbounded 1/sin(angle), particularly below 30°. Preserve area by applying sqrt(aspect) and its reciprocal before the independent spread factor. A low-speed normal deposit is near round regardless of weapon family. A glancing impact gets a directional tail only along its incoming tangent.

**Artistic exaggeration.** Bounded tails improve direction readability. At 15° the game deliberately does not infer a forensic angle from an ellipse.

## 8. Surface presets and absorption

**Measured science.** Roughness can encourage irregular boundaries but does not alone determine splash. Porous media add absorption and wicking after initial impact; [Wang et al., 2021](https://nij.ojp.gov/library/publications/fundamental-study-porcine-drip-bloodstains-fabrics-blood-droplet-impact-and-0) distinguish those stages (primary research summary consulted). Porosity does not imply zero initial splash.

**Game approximation.** Three resources: SMOOTH_NONABSORBENT, ROUGH_NONABSORBENT, POROUS_ABSORBENT. Store roughness, effective wetting/spread, absorption rate, contact retention and runoff mobility. A collider can provide a resource; legacy `blood_surface` metadata continues to work. Metal defaults smooth, stone rough, wood porous only if explicitly mapped; painted/sealed wood may be smooth. Absorption transfers local wet stock into retained stock without deleting deposited material.

**Artistic exaggeration.** Porous stains darken; absorption is a first-order decay, not pore-scale transport or realistic drying time.

## 9. Accumulation and pools

**Measured science.** Overlap adds material, not independently visible area. Blood pools can separate and dry nonuniformly; [phase-separation experiments](https://pmc.ncbi.nlm.nih.gov/articles/PMC8175381/) demonstrate complexity omitted here.

**Game approximation.** Keep deposited, wet, absorbed and mobile mass distinct. Local patches accumulate wet mass; existing contamination-cell pooled bases remain bounded visual reinforcement. Pool area remains a stylized mass-to-area relationship. Surface overlap does not create mass. Report summed footprint separately from coarse unique footprint.

**Artistic exaggeration / limits.** No free-surface level, obstacle-aware pool expansion, serum separation or coagulation solver. Large pool quads are a surface representation, not CFD.

## 10. Wall and inclined-surface runoff

**Measured science.** Tangential gravity competes with contact-line retention; contact-angle hysteresis and footprint affect the onset of sliding. [Furmidge Equation Revisited](https://pmc.ncbi.nlm.nih.gov/articles/PMC12080332/) discusses the retention relation and its shape assumptions. A static onset relation does not by itself give a flow rate.

**Game approximation.** Compare wet-mass gravity along the surface to sigma × footprint width × effective adhesion. Resource mobility, slope and remaining mass set a bounded phenomenological speed. Trace the surface as the rivulet advances. Emit overlapping rounded streak segments from the last deposited position to the current one, with a thick source and narrowing tail. Transfer mass out of the wet patch into runoff, then into retained streaks or a terminal drop. Bound active rivulets; suppress runoff where absorption wins. Support slopes as well as vertical walls.

**Artistic exaggeration.** Faster visible runoff than many real deposits, widened streaks and limited lateral variation. Branching is optional and must not invent mass. No precise contact-angle or thin-film solver.

## 11. Cast-off and cutting

**Measured science.** [Williams et al., 2019](https://pubmed.ncbi.nlm.nih.gov/29975993/) observed ligaments leaving a swinging object's distal region and fragmenting; release follows the local trajectory tangent (primary abstract consulted, DOI 10.1111/1556-4029.13855). Geometry and liquid load affect retention. Cutting also exposes a wound which can release/drip independently of later weapon motion.

**Game approximation.** Separate contact release from stored blade load. Track actual weapon-tip velocity and angular motion. Only previously acquired load is eligible for cast-off during a later swing. A capillary/acceleration-inspired release threshold and load budget determine emission; launch tangent to measured motion. Different weapon reach, motion and existing family settings produce different cast-off without weapon-name branches. Reservoir wounds continue to supply wound release.

**Artistic exaggeration / limits.** Blood adhesion and load are normalized gameplay quantities. No blade wetting film or biomechanical cutting model. Cast-off is a presentation effect; damage, reach, attack clocks and gameplay rules must remain unchanged.

## 12. Blunt, ballistic and explosive structure

**Measured science.** Blunt and projectile patterns have overlapping size distributions. [Siu et al., 2017](https://nij.ojp.gov/library/publications/quantitative-differentiation-bloodstain-patterns-resulting-gunshot-and-blunt) found spatial pattern differences more informative than a simple size dichotomy in their experiments (primary summary consulted). Projectile forward/back spatter depends on event geometry; muzzle gas and collective spray effects can matter ([NIJ ultrafast study](https://nij.ojp.gov/library/publications/ultrafast-3d-visualization-and-fluid-dynamic-mechanisms-blood-atomization)).

**Game approximation.** Preserve ballistic forward/back lobes, with more fine representatives in fast forward components; drag then sorts travel distance. Preserve Maul's measured swing-momentum axis and broad contact distribution; add occasional ligaments and mixed tissue. Slashing contact release follows the actual swing plane, separately from cast-off. Explosions retain per-victim outward axes and multiple local origins with a high tissue component.

**Artistic exaggeration / limits.** Family weights and energy coupling are authored. Explosive tissue liberation is a game model, not a blast-injury calculation. No stain size is labelled a diagnostic weapon signature.

## 13. Rendering, causality, scalability and validation contract

**Game approximation.** Batched liquid sphere instances and angular solid tissue, fixed-step arrays, swept collision, bounded breakup and runoff. Track drop ID, parent ID and event ID through deposits. Every simulated physical collision deposits, including low-speed contact. Cosmetic mist has no independent mass: its parcel share is accounted by explicit coarse deposition and must be labelled as such. Quality changes sampling, not released mass. Coarse deposition is an approximation, not a simulated trajectory.

**Artistic exaggeration.** Readability size is separate from physical diameter. Flesh, muted beige fat, dark tissue, stringy tissue and major chunks remain distinct from liquid. Hard bounds and diagnostics expose excessive visual sizes. Existing atlas occupancy compensation, radius-to-diameter correction and surface offsets remain intact.

**Validation plan.** Controlled normal impacts on three surfaces; 90/60/45/30/15° incidence; small/medium/large diameter; low/medium/high speed; smooth/rough vertical and inclined runoff; equal cast-off loads at different angular speeds; blunt +X/−X. Record actual instance dimensions and fixed-camera native Compatibility captures. Test mass conservation, diameter-dependent drag, breakup caps, causal collision records and admission pressure. Benchmark simulation and renderer separately. Rendered captures are necessary evidence; numerical tests alone cannot establish a convincing material.

**Limits.** No CFD, forensic certification, universal splash threshold, biological validation, scientifically calibrated weapon identification, or guarantee of identical frame cost on other hardware. Implementation results and exact artistic parameters belong in the accompanying validation report after measurement.

	REM ==================================================================
	REM  APOLLO - cockpit flight game for Intellivision (ECS optional)
	REM  Stage 1: launch to Earth orbit, flown from the command module
	REM  cockpit. IntyBASIC 1.5.1 + as1600. Graphics: gen_gfx.py, clips:
	REM  gen_clips.ps1.
	REM ==================================================================
	OPTION MAP 2
	INCLUDE "constants.bas"
	INCLUDE "gfx_const.bas"

	' Cockpit screen (FG/BG mode), 20 x 12 cards:
	'   row 0          : stage name, time speed
	'   rows 1-5       : left window cols 1-8, strut 9-10, right window 11-18
	'   row 6          : what to do now (prompt bar)
	'   rows 7-10      : attitude ball 0-2, g dial 3-5 (labels on row 10),
	'                    computer 7-14 (engine-stop gauge on row 10 at the
	'                    end), lights 15-19
	'   row 11         : trip strip, Earth to Moon
	CONST GR = $0800			' GRAM card flag (BACKTAB and SPRITE)
	CONST PNL = FG_BLACK + BG_GREY		' panel lettering
	CONST CXM = 45				' reticle MOB x (left window centre)
	CONST CYM = 33				' reticle MOB y
	CONST V_ORBIT = 25567			' orbit speed, ft/s
	CONST V_TLI = 35500			' speed that reaches the Moon, ft/s
	CONST LAST_STG = 8			' stages built so far
	CONST V_ARR = 8200			' speed arriving at the Moon, ft/s
	CONST V_LO = 5400			' Moon orbit speed, ft/s
	CONST LX = 36				' lander aim point, MOB x
	CONST LY = 30				' lander aim point, MOB y

	' GRAM cards (cm_gram in gfx.bas)
	CONST C_HZ = 0				' 0-7  horizon, k sky rows on top
	CONST C_LIPT = 8			' window top lip
	CONST C_LIPB = 9			' window bottom lip
	CONST C_EDL = 10			' 10-14 window left post, per row
	CONST C_EDR = 15			' 15-19 window right post, per row
	CONST C_EDI = 10			' offset to 20-29: posts for black space
	CONST C_BALL = 30			' 30-38 attitude ball (3x3)
	CONST C_GDL = 39			' 39-47 g-force dial (3x3)
	CONST C_TWR = 48			' 48-49 launch tower (clipped at sill)
	CONST C_RET = 50			' crosshair
	CONST C_DIA = 51			' guidance diamond
	CONST C_FLM = 52			' escape tower motor flame
	CONST C_CLD = 53			' cloud (clipped at sill)
	CONST C_WING = 54			' attitude ball wings
	CONST C_NDL = 55			' engine-stop gauge needle (sprite)
	CONST C_LAMP = 56			' master alarm lamp
	CONST C_SW = 57				' toggle switches
	CONST C_EARTH = 58			' trip strip: Earth, Moon, path, ship
	CONST C_MOON = 59
	CONST C_DOT = 60
	CONST C_LINE = 61
	CONST C_SHR = 62
	CONST C_SHL = 63
	' Lander cards replace the window posts (lm_cards) and the ball (lm_drift)
	CONST C_DS = 10				' 10-11 slanted window edge over sky, L R
	CONST C_DG = 12				' 12-13 slanted window edge over ground, L R
	CONST C_LV = 14				' left window side
	CONST C_RV = 15				' right window side
	CONST C_TP = 16				' 16-24 tape, bar at row 0-7, then no bar
	CONST C_LX = 25				' landing X
	CONST C_LD = 26				' drift dial dot
	CONST C_BLD = 27			' boulders

	SIGNED #ex, #ey, #vx, #vy, #k, #d, #hy, #mx, #my, #vg, #err, #tv
	UNSIGNED #vel

	DIM rowlo(5), rowhi(5)	' last card word drawn in each window row
	DIM crp(4), crt(4), cro(4)	' Moon craters: progress, type, sideways spot

	MODE 1
	WAIT

	REM ===================== TITLE ============================
title:
	GOSUB quiet
	VOICE INIT
	IF VOICE.AVAILABLE THEN VOICE PLAY v_apollo
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	BORDER BORDER_BLACK
	CLS
	FOR n = 0 TO 8
		#d = VARPTR text_ti(0) + n * 20: #p = ti_row(n): #c = ti_col(n): GOSUB text20
	NEXT n
	IF ECS.AVAILABLE THEN PRINT AT 104 COLOR FG_TAN, "ECS SOUND ON"
	auto = 0: st0 = 1
	GOSUB wait_release
	#d = 0
	WHILE 1
		WAIT
		IF FRAME AND 32 THEN PRINT AT 224 COLOR FG_WHITE, "PRESS BUTTON" ELSE PRINT AT 224 COLOR FG_WHITE, "            "
		GOSUB pads
		IF b THEN EXIT WHILE
		' Key check: show that the disc and keypad reach the game
		IF kp THEN
			n = CONT.KEY
			IF n >= 1 AND n <= LAST_STG THEN st0 = n: EXIT WHILE
			PRINT AT 44 COLOR FG_GREEN, "KEYPAD WORKS": #d = 0
		ELSEIF CONT.UP OR CONT.DOWN OR CONT.LEFT OR CONT.RIGHT THEN
			PRINT AT 44 COLOR FG_GREEN, " DISC WORKS ": #d = 0
		END IF
		#d = #d + 1
		IF #d > 900 THEN auto = 1: EXIT WHILE	' 15 s idle: demo flight
	WEND
	GOSUB wait_release

	' Stage by stage: a failed stage is tried again (the demo just ends)
	stg = st0
next_stage:
	s = stg - 1: GOSUB map_show
	GOSUB brief
	IF stg = 1 THEN
		GOSUB fly_launch
	ELSEIF stg = 2 THEN
		GOSUB fly_tli
	ELSEIF stg = 3 THEN
		GOSUB fly_dock
	ELSEIF stg = 4 OR stg = 7 THEN
		GOSUB fly_moon
		IF stg = 7 AND fr = 0 THEN GOSUB fly_home
	ELSEIF stg = 5 THEN
		GOSUB fly_land
	ELSEIF stg = 8 THEN
		GOSUB fly_down
	ELSE
		GOSUB fly_up
	END IF
	GOSUB quiet
	IF fr = 9 THEN GOTO title		' demo cancelled
	IF fr = 0 AND stg = 5 THEN GOSUB base_scene
	IF fr = 0 AND stg = 8 THEN GOSUB sea_scene
	GOSUB results
	GOSUB quiet
	IF fr THEN
		IF auto THEN GOTO title
		GOTO next_stage
	END IF
	stg = stg + 1
	IF stg <= LAST_STG THEN GOTO next_stage
	s = LAST_STG: GOSUB map_show
	GOTO title

	REM ===================== LAUNCH ===========================
fly_launch: PROCEDURE
	GOSUB draw_cockpit
	#ts = 0: sub = 0: ti = 0: tf = 0: dm = 0: comp = 1: ev = 0: fr = 0: thr = 0
	#ex = 0: #ey = 0: #vx = 0: #vy = 0: #dacc = 0
	#ontgt = 0: #tot = 0: pen = 0: ofs = 0
	#tow = 0: #tv = 0: tw_n = 255: cl_on = 0: cl_n = 255: f_on = 0
	fl = 0: shk = 0: bn = 0: bt = 0: cut_on = 0: msg = 0: msgp = 255
	eng_l = 0: les_l = 0: mq_l = 0: orb_l = 0: offs = 0: #mx = 0: #my = 0: #vg = 0
	#sky = BG_CYAN: amp = 0: gs = 0: ev_v = 0: p = 90: bl_n = 22: gd_n = 0
	wx = 8: wy = 8: tx = 8: ty = 8: wt = 30
	#alt = 0: #vel = 0: g10 = 0
	#hy = 76
	GOSUB show_comp
	GOSUB panel
	GOSUB tower_clip
	SOUND 4, 31, $1C		' noise on channel C = engine rumble
	SOUND 9, 28, $1C

	' ---- Countdown: T-10 .. T-0, ignite at T-3 ----
countdown:
	ign = 0
	FOR tc = 10 TO 1 STEP -1
		PRINT AT 187 COLOR FG_GREEN, "T- 0:", <2>tc
		IF tc >= 4 AND VOICE.AVAILABLE THEN VOICE NUMBER tc
		bt = 4: SOUND 0, 112, 10
		FOR cf = 1 TO 60		' frames (draw_window uses j)
			WAIT
			GOSUB read_input
			IF tc <= 3 THEN
				IF ign = 0 THEN
					msg = 13
					IF press THEN ign = 1: msg = 14: amp = 1
				ELSE
					ev_v = 4 + (3 - tc) * 3 + cf / 20	' rumble builds
					IF ev_v > 13 THEN ev_v = 13
					SOUND 2, 1, ev_v: SOUND 7, 1, ev_v: SOUND 6, 2800, ev_v / 2
				END IF
			END IF
			IF fr = 9 THEN RETURN
			IF kpress THEN ms = 0: GOSUB map_pause
			IF tc > 3 THEN msg = 17
			GOSUB beep_tick
			GOSUB show_msg
			GOSUB lights
			GOSUB draw_window
			GOSUB place_sprites
			GOSUB gram_tick
		NEXT cf
	NEXT tc
	IF ign = 0 THEN
		msg = 16: GOSUB show_msg
		FOR j = 1 TO 120: WAIT: NEXT j
		GOTO countdown
	END IF

	' ---- Flight ----
	thr = 1: comp = 4: msg = 15: ev_v = 15
	GOSUB show_comp
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN ms = stg: GOSUB map_pause

		' Mission clock; ti, tf = #ts / 10 and #ts % 10, kept as it ticks
		' (dividing by 10 is a slow subtract loop). Time moves by frames
		' gone by, df, since a busy pass can take more than one frame.
		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60
			sub = sub - 60: #ts = #ts + 1: tf = tf + 1
			IF tf = 10 THEN tf = 0: ti = ti + 1
		WEND
		i = ti: f = tf
		IF i > 70 THEN i = 70: f = 10

		' Flight profile from the tables
		#k = (pitch_t(i) - pitch_t(i + 1)) * f: GOSUB div10: p = pitch_t(i) - #d
		#k = (asc_alt(i + 1) - asc_alt(i)) * f: GOSUB div10: #alt = asc_alt(i) + #d
		#k = (asc_vel(i + 1) - asc_vel(i)) * f: GOSUB div10: #vel = asc_vel(i) + #d
		#k = (gee_t(i + 1) - gee_t(i)) * f: GOSUB div10: g10 = gee_t(i) + #d
		IF thr = 0 THEN g10 = 0

		' Sky darkens with altitude
		IF #alt < 40 THEN
			#sky = BG_CYAN
		ELSEIF #alt < 150 THEN
			#sky = BG_BLUE
		ELSE
			#sky = BG_BLACK
		END IF

		' Events
		IF ev = 0 THEN
			amp = 1: gs = 2
			IF #ts < 20 THEN amp = 2
			IF #ts >= 12 THEN msg = 1
			mq_l = 0
			IF #ts >= 55 AND #ts < 85 THEN msg = 2: mq_l = 1: amp = 2: gs = 5
			IF #ts >= 135 THEN msg = 3
			IF #ts >= 161 THEN
				ev = 1: thr = 0: eng_l = 2: msg = 4: #dl = #ts + 14
				ev_v = 0: amp = 0: gs = 0
			END IF
		ELSEIF ev = 1 THEN
			IF press THEN
				GOSUB do_stage: ev = 2: msg = 5: ev_v = 11
			ELSEIF #ts > #dl THEN
				fr = 1: RETURN
			END IF
		ELSEIF ev = 2 THEN
			gs = 1
			IF #ts >= 197 THEN ev = 3: les_l = 2: msg = 6: #dl = #ts + 14
		ELSEIF ev = 3 THEN
			gs = 1
			IF press OR #ts > #dl THEN
				msg = 7
				IF press = 0 THEN msg = 12: pen = pen + 10
				les_l = 0: fl = 4: #fcol = BG_WHITE: f_on = 1: fy = 40
				bn = 6: ev = 4: comp = 8
				GOSUB show_comp
			END IF
		ELSEIF ev = 4 THEN
			gs = 1
			IF #ts >= 215 THEN msg = 8
			IF #ts >= 500 AND comp = 8 THEN comp = 4: GOSUB show_comp
			IF #ts >= 548 THEN
				ev = 5: thr = 0: eng_l = 2: msg = 4: #dl = #ts + 14
				ev_v = 0: gs = 0
			END IF
		ELSEIF ev = 5 THEN
			IF press THEN
				GOSUB do_stage: ev = 6: msg = 5: ev_v = 9
			ELSEIF #ts > #dl THEN
				fr = 2: RETURN
			END IF
		ELSEIF ev = 6 THEN
			gs = 1
			IF #ts >= 560 THEN msg = 9
			IF #ts >= 680 THEN
				ev = 7: comp = 1: cut_on = 1: msg = 10
				#cv = asc_vel(68): cvf = 0: #vg = V_ORBIT - #cv
				GOSUB show_comp
			END IF
		ELSEIF ev = 7 THEN
			gs = 1
			cvf = cvf + 22 * df		' third stage: about 22 ft/s per second
			WHILE cvf >= 60: cvf = cvf - 60: #cv = #cv + 1: WEND
			#vel = #cv
			#vg = V_ORBIT - #cv
			IF press THEN
				#err = 0 - #vg: thr = 0: ev_v = 0: cut_on = 0: orb_l = 1
				IF ABS(#err) > 64 THEN fr = 3
				RETURN
			END IF
			IF #vg < -120 THEN #err = 0 - #vg: fr = 3: RETURN
		END IF

		' Attitude: guidance error drifts with the pitch program and gusts
		IF thr THEN
			#dacc = #dacc + (pitch_t(i) - pitch_t(i + 1)) * comp
			IF #dacc >= 60 THEN #dacc = #dacc - 60: #vy = #vy + 1
			GOSUB wander
			IF gs THEN
				IF (RAND AND 7) = 0 THEN #vx = #vx + (RAND % (gs * 2 + 1)) - gs
				IF (RAND AND 7) = 0 THEN #vy = #vy + (RAND % (gs * 2 + 1)) - gs
			END IF
		END IF
		GOSUB attitude
		#hy = 20 + p * 5 / 8 + #my

		' Attitude ball: horizon 0-22 px down the ball (nose up = all sky)
		#k = p * 11 / 90 + (#my + 16) / 2 + 3
		IF #k < 0 THEN #k = 0
		IF #k > 22 THEN #k = 22
		bl_n = #k

		' Score: frames with the diamond on the crosshair
		IF thr THEN
			#tot = #tot + 1
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
		END IF
		' Off the window for 2.5 s = course lost
		IF offs THEN
			ofs = ofs + 1
			IF ofs > 150 THEN fr = 4: RETURN
			IF msg <> 4 AND msg <> 6 AND msg <> 10 THEN msg = 11
		ELSE
			ofs = 0
			IF msg = 11 THEN msg = 1
		END IF

		' Tower falls away below after liftoff; clouds stream past
		IF tw_n THEN #tv = #tv + 1: #tow = #tow + #tv: GOSUB tower_clip
		GOSUB cloud_move
		IF f_on THEN
			fy = fy - 3
			IF fy < 18 THEN f_on = 0
		END IF

		' Shake
		IF thr = 0 THEN amp = 0
		IF ev >= 2 AND ev <> 3 THEN amp = 0
		IF shk THEN shk = shk - 1: amp = 3

		' Sound
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
			IF bn = 0 THEN SOUND 4, 31, $1C
		ELSE
			IF #ts > 30 AND ev = 0 THEN ev_v = 13
			SOUND 2, 1, ev_v: SOUND 7, 1, ev_v: SOUND 6, 2800, ev_v / 2
		END IF
		IF eng_l = 2 OR les_l = 2 OR msg = 10 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF
		GOSUB beep_tick

		' Display
		GOSUB draw_window
		GOSUB place_sprites
		GOSUB show_msg
		IF cut_on THEN GOSUB cut_gauge
		GOSUB panel_step
		GOSUB gram_tick
	WEND
	END

	' The Earth ahead: land sprites over the disc, kept inside the window
place_earth: PROCEDURE
	x = 40 + #mx + ox
	#k = 28 + #my + oy
	IF lm_n > 2 THEN
		IF x < 24 THEN x = 24
		IF x > 56 THEN x = 56
		IF #k < 24 THEN #k = 24
		IF #k > 32 THEN #k = 32
		x = x - 8: #k = #k - 8 + ZOOMY4 + DOUBLEY: #p = VISIBLE + ZOOMX2: j = 16
	ELSE
		IF #k < 16 THEN #k = 16
		IF #k > 40 THEN #k = 40
		#k = #k + ZOOMY2 + DOUBLEY: #p = VISIBLE: j = 8
	END IF
	SPRITE 2, x + #p, #k, GR + 32 + SPR_GREEN
	SPRITE 3, x + j + #p, #k, GR + 48 + SPR_GREEN
	SPRITE 4, x + #p, #k, GR + SPR_BLUE
	SPRITE 7, x + j + #p, #k, GR + 16 + SPR_BLUE
	END

earth_z:	DATA 0,0,1,2,3,4,5,5
home_s:	DATA 43,66,85,54,73,96

	REM ===================== STAGE 8: RE-ENTRY ===============
	' Drop the engine section, turn the heat shield forward, then hold the
	' needle in the green through the fire: too steep burns you up, too flat
	' skips you off the air. Then the chutes, when told.
	' ev: 0 falling, 1 drop engines, 2 turning, 3 air ahead, 4 fire,
	' 5 radio back, 6 small chutes, 7 on them, 8 big chutes, 9 floating down.
	' #alt = thousands of feet, #tv = the speed being slowed to.
fly_down: PROCEDURE
	GOSUB draw_cockpit
	GOSUB fly_zero
	comp = 4: msg = 62: #hy = 22: #alt = 900: #vel = 36000: #tv = 440
	ct = 0: fw = 0: ph = 0: eg = 0: vc = 0: vt = 0: cdf = 0: #err = 0: cl_n = 255
	GOSUB show_comp
	GOSUB panel
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN
			ms = stg: GOSUB map_pause
			cdf = 1
		END IF

		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND
		IF down_r(ev) THEN #alt = down_b(ev) - #ts * down_r(ev)
		amp = 0

		IF ev = 0 THEN
			IF #ts >= 12 THEN ev = 1: msg = 67: eng_l = 2: #dl = #ts + 24
		ELSEIF ev = 1 THEN
			IF press THEN
				GOSUB do_stage
				thr = 0: ev = 2: ct = 0: msg = 72
			ELSEIF #ts > #dl THEN
				fr = 16: RETURN
			END IF
		ELSEIF ev = 2 THEN
			' The whole ship swings round: Earth out of the window and back
			ct = ct + df: al = 1
			IF ct < 75 THEN #hy = 22 + ct ELSE #hy = 172 - ct
			IF ct >= 150 THEN
				ev = 3: #ts = 0: sub = 0: msg = 73: cut_on = 1: #ey = -320
			END IF
		ELSEIF ev = 3 THEN
			#hy = 22 + #my
			IF #ts >= 20 THEN
				ev = 4: #ts = 0: sub = 0: msg = 34: bn = 8: #hy = 60: mq_l = 1: cl_on = 0
			END IF
		ELSEIF ev = 4 THEN
			n = #ts / 16
			IF n >= 9 THEN
				ev = 5: #ts = 0: sub = 0: msg = 74: cut_on = 0: fw = 0: vt = 3
				#sky = BG_BLUE: mq_l = 0: cdf = 1: bt = 30: gs = 0: ofs = 0
				SOUND 0, 90, 10
			ELSE
				j = fire_b(n)
				g10 = fire_g(n) + (fire_g(n + 1) - fire_g(n)) * (#ts AND 15) / 16
				gs = j / 2 + 1
				IF #vel > 3000 THEN #vel = #vel - (g10 / 2) * df
				' Falling pulls you steeper, then the air lifts you flatter
				IF #ts < 72 THEN #ey = #ey - (j / 2 + 1) * df ELSE #ey = #ey + (j / 2 + 1) * df
				#tot = #tot + 1
				IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
				IF #my < -8 OR #my > 8 THEN
					ofs = ofs + df
					eg = eg + df
					IF eg >= 60 THEN eg = 0: #err = #err + 1
					IF #my < 0 THEN
						msg = 70: j = 3
						IF ofs > 180 THEN fr = 17: RETURN
					ELSE
						msg = 71
						IF ofs > 180 THEN fr = 18: RETURN
					END IF
				ELSE
					IF ofs >= df * 2 THEN ofs = ofs - df * 2 ELSE ofs = 0
					IF #ts >= 12 THEN msg = 73
				END IF
				' The fire in the window, hottest when you come in too steep
				ph = ph XOR 1
				#sky = fire_bg(j * 2 + (FRAME / 16 AND 1))
				fw = fire_fg(j)
				amp = j: vt = 6 + j * 3
			END IF
		ELSEIF ev = 5 OR ev = 7 THEN
			IF #ts >= 14 THEN
				ev = ev + 1: msg = 65 + ev / 2: #sky = BG_CYAN: #hy = 38: #dl = #ts + 20
			END IF
		ELSEIF ev = 6 OR ev = 8 THEN
			IF press THEN
				ev = ev + 1: #ts = 0: sub = 0: bn = 6: shk = 15: g10 = 30: #tv = 32: msg = 75: cdf = 1
				IF ev = 7 THEN #tv = 260: msg = 78
			ELSEIF #ts > #dl THEN
				fr = 19: RETURN
			END IF
		ELSE
			#hy = 38 - #ts / 2 - #ts / 4: #alt = 10 - #ts / 3
			vt = 2
			IF #ts >= 28 THEN RETURN
		END IF

		' Aim until the fire is out, slowing down after
		IF ev < 5 THEN
			IF ev <> 2 THEN
				GOSUB wander
				GOSUB attitude
				#vg = 128 + #my * 16
			END IF
			#k = (#my + 16) / 2 + 3
			IF #k < 0 THEN #k = 0
			IF #k > 22 THEN #k = 22
			bl_n = #k
			IF ev < 4 THEN GOSUB cloud_move
		ELSE
			IF #vel > #tv THEN #vel = #vel - (#vel - #tv) / 16
			IF g10 > 10 THEN g10 = g10 - 1
			bl_n = 11
		END IF
		IF shk THEN shk = shk - 1: amp = 2

		' Sound: the roar swells and fades (no sudden jumps)
		vc = vc + df
		IF vc >= 4 THEN
			vc = 0
			IF ev_v < vt THEN ev_v = ev_v + 1 ELSE IF ev_v > vt THEN ev_v = ev_v - 1
		END IF
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
		ELSE
			GOSUB eng_snd
			IF ev = 4 THEN
				SOUND 7, 1, ev_v
			END IF
		END IF
		IF msg >= 67 AND msg <= 71 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF
		GOSUB beep_tick

		GOSUB draw_window
		GOSUB place_sprites
		GOSUB down_sprites
		GOSUB show_msg
		IF cut_on THEN GOSUB cut_gauge
		GOSUB panel_step

		' One GRAM change a frame: flames, the chutes' card, or the dials
		IF ev = 4 AND ph THEN
			eo = (eo + 1) AND 3
			DEFINE 0, 1, VARPTR flame_f(eo * 4)
		ELSEIF cdf THEN
			cdf = 0
			IF ev >= 9 THEN
				DEFINE C_TWR, 2, chute_c
			ELSEIF ev >= 5 THEN
				DEFINE C_TWR, 2, drogue_c
			END IF
		ELSE
			GOSUB gram_tick
		END IF
	WEND
	END

	' Helpers, briefing and trip map in segment 3 ($2100): IntyBASIC
	' switches the ECS ROM off at boot, so its address ranges are free
	SEGMENT 3

	' Every flight in the command module starts from this
fly_zero: PROCEDURE
	#ts = 0: sub = 0: ev = 0: fr = 0: thr = 0
	#ex = 0: #ey = 0: #vx = 0: #vy = 0: #dacc = 0
	#ontgt = 0: #tot = 0: pen = 0: ofs = 0: offs = 0
	tw_n = 0: tw_d = 0: cl_on = 0: f_on = 0: g10 = 0
	fl = 0: shk = 0: bn = 0: bt = 0: cut_on = 0: msgp = 255
	eng_l = 0: les_l = 0: mq_l = 0: orb_l = 0
	#sky = BG_BLACK: amp = 0: ev_v = 0: gd_n = 0
	wx = 8: wy = 8: tx = 8: ty = 8: wt = 30: gs = 0
	END

	' Stage 8's sprites over place_sprites': a bold crosshair and <> that
	' show up against the fire, then two small chutes or three big ones on one fan of lines,
	' swaying together, with no aim marks
down_sprites: PROCEDURE
	IF ev >= 5 THEN
		SPRITE 0, 0: SPRITE 1, 0
		IF ev < 7 THEN RETURN
		' The fan of lines, then the canopies on top of it, swaying as one
		#k = 48 + ((FRAME / 32) AND 1) + ox + VISIBLE + ZOOMX2
		#p = 17 + oy + ZOOMY4
		#d = 33 + oy + ZOOMY4
		SPRITE 0, #k - 16, #d + FLIPX, GR + (C_TWR + 1) * 8 + SPR_WHITE
		SPRITE 1, #k, #d, GR + (C_TWR + 1) * 8 + SPR_WHITE
		IF ev < 9 THEN
			SPRITE 2, #k - 16, #p, GR + C_TWR * 8 + SPR_ORANGE
			SPRITE 3, #k, #p, GR + C_TWR * 8 + SPR_WHITE
		ELSE
			SPRITE 2, #k - 24, #p, GR + C_TWR * 8 + SPR_ORANGE
			SPRITE 3, #k - 8, #p, GR + C_TWR * 8 + SPR_WHITE
			SPRITE 4, #k + 8, #p, GR + C_TWR * 8 + SPR_ORANGE
		END IF
		RETURN
	END IF
	IF #sky = BG_BLACK THEN
		#c = SPR_WHITE: #d = SPR_YELLOW
	ELSE
		#c = SPR_BLACK: #d = SPR_BLUE
	END IF
	SPRITE 0, CXM - 4 + ox + VISIBLE + ZOOMX2, CYM - 4 + oy + ZOOMY4, GR + C_RET * 8 + #c
	IF blk = 0 THEN SPRITE 1, CXM + #mx + ox + VISIBLE, CYM + #my + oy + ZOOMY2, GR + C_DIA * 8 + #d
	END

	' Staging: flash, bang, shake, kick
do_stage: PROCEDURE
	eng_l = 0: thr = 1: fl = 6: #fcol = BG_ORANGE: bn = 10: shk = 30
	#vy = #vy + 12
	END

	' Wandering push on the nose: every 1-2 s pick a new drift (bigger
	' with gs), ease toward it, and add it straight to the aim error, so
	' the player has to keep correcting. wx,wy,tx,ty are 8 = no drift.
wander: PROCEDURE
	IF wt <= df THEN
		wt = 50 + (RAND AND 63)
		wm = gs + 3
		tx = 8 - wm + ((RAND AND 15) + 1) * wm / 8
		ty = 8 - wm + ((RAND AND 15) + 1) * wm / 8
	ELSE
		wt = wt - df
	END IF
	IF (RAND AND 7) = 0 THEN
		IF wx < tx THEN wx = wx + 1 ELSE IF wx > tx THEN wx = wx - 1
		IF wy < ty THEN wy = wy + 1 ELSE IF wy > ty THEN wy = wy - 1
	END IF
	#ex = #ex + (wx - 8) * df
	IF FRAME AND 1 THEN #ey = #ey + (wy - 8) * df
	END

	' Integrate attitude error; #mx,#my = diamond offset in pixels
attitude: PROCEDURE
	IF al THEN #vx = #vx + 3
	IF ar THEN #vx = #vx - 3
	IF au THEN #vy = #vy + 3
	IF ad THEN #vy = #vy - 3
	IF #vx > 0 THEN #vx = #vx - (#vx + 7) / 8
	IF #vx < 0 THEN #vx = #vx + (7 - #vx) / 8
	IF #vy > 0 THEN #vy = #vy - (#vy + 7) / 8
	IF #vy < 0 THEN #vy = #vy + (7 - #vy) / 8
	IF #vx > 24 THEN #vx = 24
	IF #vx < -24 THEN #vx = -24
	IF #vy > 24 THEN #vy = 24
	IF #vy < -24 THEN #vy = -24
	#ex = #ex + #vx: #ey = #ey + #vy
	IF #ex > 1200 THEN #ex = 1200
	IF #ex < -1200 THEN #ex = -1200
	IF #ey > 1200 THEN #ey = 1200
	IF #ey < -1200 THEN #ey = -1200
	#k = #ex: GOSUB px32: #mx = #d
	#k = #ey: GOSUB px32: #my = #d
	offs = 0
	IF #mx > 20 THEN #mx = 20: offs = 1
	IF #mx < -20 THEN #mx = -20: offs = 1
	IF #my > 14 THEN #my = 14: offs = 1
	IF #my < -14 THEN #my = -14: offs = 1
	END

	' #d = #k / 10 for the flight tables, by shifts (0.4% low), signed
div10: PROCEDURE
	IF #k < 0 THEN #k = 0 - #k: GOSUB div10: #d = 0 - #d: RETURN
	#d = #k / 16 + #k / 32 + #k / 256 + #k / 512
	END

	' #d = #k / 32 rounded toward zero (signed)
px32: PROCEDURE
	IF #k >= 0 THEN #d = #k / 32 ELSE #d = 0 - ((0 - #k) / 32)
	END

	' Both hand controllers: b = side button held, kp = keypad key held.
	' A side button sets two of bits 5-7 and a keypad key just one, so
	' they can't be mistaken for each other (CONT.BUTTON also fires on
	' keypad keys).
pads: PROCEDURE
	b = 0: kp = 0
	pc = CONT1 AND $E0
	IF pc = $A0 OR pc = $60 OR pc = $C0 THEN b = 1
	IF pc = $80 OR pc = $40 OR pc = $20 THEN kp = 1
	pc = CONT2 AND $E0
	IF pc = $A0 OR pc = $60 OR pc = $C0 THEN b = 1
	IF pc = $80 OR pc = $40 OR pc = $20 THEN kp = 1
	END

	' Controller, with edge-detected button and keypad (kpress opens the
	' trip map). In demo mode an autopilot flies and any real press
	' cancels the demo.
read_input: PROCEDURE
	press = 0: kpress = 0: al = 0: ar = 0: au = 0: ad = 0
	GOSUB pads
	IF auto THEN
		IF b OR kp THEN fr = 9: RETURN
		IF #mx < -2 THEN al = 1
		IF #mx > 2 THEN ar = 1
		IF #my > 2 THEN ad = 1
		IF #my < -2 THEN au = 1
		IF msg = 13 OR msg = 4 OR msg = 6 OR msg = 21 OR msg = 30 OR (msg >= 67 AND msg <= 69) THEN
			IF (FRAME AND 60) = 0 THEN press = 1
		END IF
		IF ((stg = 3 AND ev = 2) OR (stg = 6 AND ev = 7)) AND #vg < 6 THEN
			IF (FRAME AND 60) = 0 THEN press = 1
		END IF
		IF msg = 10 THEN
			IF #vg <= 0 THEN press = 1
		END IF
		' Show the trip map once, 100 s into the launch
		IF dm = 0 AND stg = 1 AND #ts >= 100 THEN dm = 1: kpress = 1
		RETURN
	END IF
	IF b THEN
		IF pb = 0 THEN press = 1
	END IF
	IF kp THEN
		IF kpp = 0 THEN kpress = 1
	END IF
	pb = b: kpp = kp
	' Keypad keys also look like disc directions: no steering while held
	IF kp = 0 THEN
		IF CONT.LEFT THEN al = 1
		IF CONT.RIGHT THEN ar = 1
		IF CONT.UP THEN au = 1
		IF CONT.DOWN THEN ad = 1
	END IF
	END

wait_release: PROCEDURE
	DO
		WAIT
		GOSUB pads
	LOOP WHILE b OR kp
	pb = 0: kpp = 0
	END

	' Wait for a button press, blinking "PRESS BUTTON" at #p (5 s in demo)
wait_button: PROCEDURE
	GOSUB wait_release
	#d = 0
	DO
		WAIT
		IF FRAME AND 32 THEN PRINT AT #p COLOR FG_WHITE, "PRESS BUTTON" ELSE PRINT AT #p COLOR FG_WHITE, "            "
		#d = #d + 1
		IF auto AND #d > 300 THEN EXIT DO
		GOSUB pads
	LOOP UNTIL b
	GOSUB wait_release
	END

	REM ===================== BRIEFING =========================
brief: PROCEDURE
	CLS
	n = brief_pg(stg)
	GOSUB brief_page
	IF stg = 1 THEN
		CLS
		n = 1
		GOSUB brief_page
	END IF
	END

	' Show briefing page n and wait for the button. Colours go by row; page 1
	' (the cockpit guide) has its own.
brief_page: PROCEDURE
	#d = VARPTR text_page(0) + n * 220
	FOR i = 0 TO 10
		IF n = 1 THEN #c = brief_c1(i) ELSE #c = brief_c0(i)
		#p = i * 20
		GOSUB text20
		#d = #d + 20
	NEXT i
	#p = 224: GOSUB wait_button
	END

	SEGMENT 4			' $7100, also freed from the ECS ROM

	REM ===================== TRIP MAP =========================
	' s = stages done (0 = on the pad)
map_show: PROCEDURE
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	BORDER BORDER_BLACK
	CLS
	DEFINE 0, 16, map_gram
	WAIT
	DEFINE 16, 16, VARPTR map_gram(64)
	WAIT
	DEFINE 32, 16, VARPTR map_gram(128)
	WAIT
	DEFINE 48, 16, VARPTR map_gram(192)
	WAIT
	PRINT AT 2 COLOR FG_WHITE, "TRIP TO THE MOON"
	PRINT AT 120 COLOR FG_TAN, "EARTH"
	PRINT AT 135 COLOR FG_TAN, "MOON"
	#p = map_pts(s * 3 + 2)
	FOR i = 0 TO MAP_E - 1
		#k = map_bt(i * 3 + 2)
		#d = map_bt(i * 3 + 1)
		IF #k THEN
			IF #k <= #p THEN #d = #d + FG_YELLOW ELSE #d = #d + FG_WHITE
		END IF
		#BACKTAB(map_bt(i * 3)) = #d
	NEXT i
	' Where you are now (red, like the marker), then what's next
	#p = 160: #k = s * 20 + 180: #c = FG_RED: GOSUB print_txt
	n = s + 1
	IF n > 8 THEN
		PRINT AT 182 COLOR FG_GREEN, "MISSION COMPLETE"
	ELSE
		PRINT AT 180 COLOR FG_YELLOW, "NEXT: STAGE ", <1>n, " OF 8"
		#p = 200: #k = n * 20: #c = FG_WHITE: GOSUB print_txt
	END IF

	' You-are-here ring on the craft's position, "YOU" above it (below
	' it near the top edge). The letters are GROM cards used as sprites.
	x = map_pts(s * 3): y = map_pts(s * 3 + 1)
	SPRITE 0, x + 5 + VISIBLE, y + 5 + ZOOMY2, GR + MAP_N * 8 + SPR_RED
	SPRITE 1, 16 + VISIBLE, MAP_LY + 8 + ZOOMY2 + DOUBLEY, GR + MAP_L * 8 + SPR_GREEN
	SPRITE 5, 24 + VISIBLE, MAP_LY + 8 + ZOOMY2 + DOUBLEY, GR + (MAP_L + 2) * 8 + SPR_GREEN
	SPRITE 6, 32 + VISIBLE, MAP_LY + 8 + ZOOMY2 + DOUBLEY, GR + (MAP_L + 4) * 8 + SPR_GREEN
	SPRITE 7, 16 + MAP_LX + VISIBLE, MAP_LY + 24 + ZOOMY2, GR + (MAP_L + 6) * 8 + SPR_GREEN
	IF x < 12 THEN lx = 0 ELSE lx = x - 12
	IF lx > 136 THEN lx = 136
	IF y < 22 THEN ly = y + 5 ELSE ly = y - 13
	SPRITE 2, lx + 8 + VISIBLE, ly + 8 + ZOOMY2, 57 * 8 + SPR_RED		' Y
	SPRITE 3, lx + 16 + VISIBLE, ly + 8 + ZOOMY2, 47 * 8 + SPR_RED		' O
	SPRITE 4, lx + 24 + VISIBLE, ly + 8 + ZOOMY2, 53 * 8 + SPR_RED		' U
	GOSUB wait_release
	#d = 0
	DO
		WAIT
		IF FRAME AND 32 THEN PRINT AT 224 COLOR FG_WHITE, "PRESS BUTTON" ELSE PRINT AT 224 COLOR FG_WHITE, "            "
		#d = #d + 1
		IF auto AND #d > 300 THEN EXIT DO
		GOSUB pads
	LOOP UNTIL b
	GOSUB wait_release
	GOSUB hide_sprites
	END

	' Keypad during a stage: the game pauses and a small trip map covers
	' the windows (ms = 0 on the pad, else the stage being flown). The map
	' borrows the window art's GRAM cards; the panel keeps its own.
map_pause: PROCEDURE
	GOSUB quiet
	SCROLL 0, 0, 0
	FOR i = 0 TO 7: SPRITE i, 0: NEXT i
	SPRITE 5, 12 + VISIBLE + ZOOMX2, 75 + ZOOMY2, GR + C_WING * 8 + SPR_ORANGE
	IF cut_on THEN SPRITE 6, 64 + nx + VISIBLE, 88 + ZOOMY2, GR + C_NDL * 8 + SPR_WHITE
	FOR i = 20 TO 119: #BACKTAB(i) = BG_BLACK: NEXT i
	DEFINE 0, 15, ov_gram
	WAIT
	DEFINE 15, 15, VARPTR ov_gram(60)
	WAIT
	DEFINE 48, 6, VARPTR ov_gram(120)
	WAIT
	DEFINE 56, 2, VARPTR ov_gram(144)
	WAIT
	#p = ov_pts(ms * 3 + 2)
	FOR i = 0 TO OV_E - 1
		#k = ov_bt(i * 3 + 2)
		#d = ov_bt(i * 3 + 1)
		IF #k THEN
			IF #k <= #p THEN #d = #d + FG_YELLOW ELSE #d = #d + FG_WHITE
		END IF
		#BACKTAB(ov_bt(i * 3)) = #d
	NEXT i
	IF ms THEN #k = ms * 20 + 340 ELSE #k = 180
	#p = 20: #c = FG_RED: GOSUB print_txt
	PRINT AT 120 COLOR FG_WHITE, "PAUSED  KEY: RESUME "
	x = ov_pts(ms * 3): y = ov_pts(ms * 3 + 1)
	SPRITE 0, x + 5 + VISIBLE, y + 5 + ZOOMY2, GR + 56 * 8 + SPR_RED
	SPRITE 1, 12 + VISIBLE, 32 + ZOOMY2 + DOUBLEY, GR + 24 * 8 + SPR_GREEN
	SPRITE 2, 20 + VISIBLE, 32 + ZOOMY2 + DOUBLEY, GR + 26 * 8 + SPR_GREEN
	GOSUB wait_release
	#d = 0
	DO
		WAIT
		#d = #d + 1
		IF auto AND #d > 180 THEN EXIT DO
		GOSUB pads
		IF auto AND (b OR kp) THEN fr = 9
	LOOP UNTIL b OR kp
	GOSUB wait_release

	' Back to the cockpit: windows, strut, prompt and sound come back
	SPRITE 0, 0: SPRITE 1, 0: SPRITE 2, 0
	FOR i = 20 TO 119: #BACKTAB(i) = BG_BLACK: NEXT i
	DEFINE 0, 15, cm_gram
	WAIT
	DEFINE 15, 15, VARPTR cm_gram(60)
	WAIT
	DEFINE 48, 6, VARPTR cm_gram(192)
	WAIT
	DEFINE 56, 2, VARPTR cm_gram(224)
	WAIT
	FOR i = 20 TO 119: #BACKTAB(i) = BG_GREY: NEXT i
	#BACKTAB(89) = GR + C_SW * 8 + BG_GREY
	#BACKTAB(90) = GR + C_SW * 8 + BG_GREY
	FOR i = 0 TO 4: rowlo(i) = 255: rowhi(i) = 255: NEXT i
	IF tw_n THEN tw_d = 1
	cl_n = 255: msgp = 255
	SOUND 4, 31, $1C
	SOUND 9, 28, $1C
	lf = FRAME
	END

	' Print 20 characters of txt(#k..) at #p in colour #c
print_txt: PROCEDURE
	FOR j = 0 TO 19: #BACKTAB(#p + j) = txt(#k + j) * 8 + #c: NEXT j
	END

	SEGMENT 1

	REM ===================== COCKPIT DRAWING ==================
load_cm: PROCEDURE
	DEFINE 0, 16, cm_gram
	WAIT
	DEFINE 16, 16, VARPTR cm_gram(64)
	WAIT
	DEFINE 32, 16, VARPTR cm_gram(128)
	WAIT
	DEFINE 48, 16, VARPTR cm_gram(192)
	WAIT
	bl_s = 22: gd_s = 0: tw_d = 0
	END

draw_cockpit: PROCEDURE
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	GOSUB load_cm
	BORDER BORDER_GREY
	FOR i = 0 TO 239: #BACKTAB(i) = BG_GREY: NEXT i
	n = stg - 1
	IF n > 3 THEN n = n - 2
	#d = VARPTR text_st(0) + n * 20: #p = 0: #c = PNL: GOSUB text20
	#BACKTAB(89) = GR + C_SW * 8 + BG_GREY
	#BACKTAB(90) = GR + C_SW * 8 + BG_GREY
	FOR i = 120 TO 139: #BACKTAB(i) = BG_BLACK: NEXT i
	FOR i = 0 TO 3
		IF i < 3 THEN
			FOR j = 0 TO 2
				#BACKTAB(140 + i * 20 + j) = GR + (C_BALL + i * 3 + j) * 8 + FG_WHITE
				#BACKTAB(143 + i * 20 + j) = GR + (C_GDL + i * 3 + j) * 8 + FG_WHITE
			NEXT j
		END IF
		FOR j = 7 TO 14: #BACKTAB(140 + i * 20 + j) = BG_BLACK: NEXT j
	NEXT i
	PRINT AT 200 COLOR PNL, "AIM"
	PRINT AT 204 COLOR PNL, "G"
	GOSUB trip_strip
	FOR i = 0 TO 4: rowlo(i) = 255: rowhi(i) = 255: NEXT i
	END

	' Bottom row: Earth ... Moon, ship at trip_col(stg)
trip_strip: PROCEDURE
	#BACKTAB(220) = GR + C_EARTH * 8 + FG_BLUE
	#BACKTAB(239) = GR + C_MOON * 8 + FG_WHITE
	n = trip_col(stg)
	FOR i = 1 TO 18
		IF stg < 6 THEN dn = (i < n) ELSE dn = (i > n)
		IF dn THEN #BACKTAB(220 + i) = GR + C_LINE * 8 + FG_YELLOW ELSE #BACKTAB(220 + i) = GR + C_DOT * 8 + FG_TAN
	NEXT i
	IF stg < 6 THEN #BACKTAB(220 + n) = GR + C_SHR * 8 + FG_YELLOW ELSE #BACKTAB(220 + n) = GR + C_SHL * 8 + FG_YELLOW
	END

	' Time speed in the top-right corner ("DEMO" in demo mode)
show_comp: PROCEDURE
	IF auto THEN PRINT AT 16 COLOR FG_RED + BG_GREY, "DEMO": RETURN
	PRINT AT 18 COLOR PNL, <1>comp, "X"
	END

	' Windows: sky above the horizon, Earth below. #hy = horizon line in
	' window pixels (0 = top, 40 = sill). A row is redrawn when it changes.
	' The slanted posts hold sky or Earth, whichever fills most of the card.
draw_window: PROCEDURE
	IF fl THEN fl = fl - 1: #c = #fcol ELSE #c = #sky
	FOR i = 0 TO 4
		#k = #hy - i * 8
		IF #k >= 8 THEN
			#d = #c
			IF fw THEN #d = GR + fw + #c		' card 0: flames
			IF i = 0 THEN #d = GR + C_LIPT * 8 + #c
			IF i = 4 THEN #d = GR + C_LIPB * 8 + #c
		ELSEIF #k <= 0 THEN
			#d = BG_BLUE			' plain, so clouds behind it show
			IF i = 0 THEN #d = GR + C_LIPT * 8 + BG_BLUE
			IF i = 4 THEN #d = GR + C_LIPB * 8 + BG_BLUE
		ELSE
			#d = GR + (C_HZ + #k) * 8 + FG_BLUE + #c
		END IF
		IF (#d AND 255) <> rowlo(i) OR (#d / 256) <> rowhi(i) THEN
			rowlo(i) = #d AND 255: rowhi(i) = #d / 256
			IF #k >= 4 THEN #k = #c ELSE #k = BG_BLUE
			' Black posts vanish against black space: use the grey ones
			IF #k = BG_BLACK THEN #k = GR + C_EDI * 8 + BG_GREY ELSE #k = GR + #k
			#p = i * 20 + 21
			#BACKTAB(#p) = (C_EDL + i) * 8 + #k
			#BACKTAB(#p + 7) = (C_EDR + i) * 8 + #k
			#BACKTAB(#p + 10) = (C_EDL + i) * 8 + #k
			#BACKTAB(#p + 17) = (C_EDR + i) * 8 + #k
			FOR j = 1 TO 6: #BACKTAB(#p + j) = #d: #BACKTAB(#p + j + 10) = #d: NEXT j
		END IF
	NEXT i
	END

	' Sprites, offset by the current shake
place_sprites: PROCEDURE
	IF amp THEN
		IF FRAME AND 1 THEN ox = RAND % (amp + 1): oy = RAND % (amp + 1)
	ELSE
		ox = 0: oy = 0
	END IF
	SCROLL ox, oy, 0
	SPRITE 0, CXM + ox + VISIBLE, CYM + oy + ZOOMY2, GR + C_RET * 8 + SPR_WHITE
	blk = 0
	IF offs THEN IF FRAME AND 8 THEN blk = 1
	IF blk THEN
		SPRITE 1, 0
	ELSE
		SPRITE 1, CXM + #mx + ox + VISIBLE, CYM + #my + oy + ZOOMY2, GR + C_DIA * 8 + SPR_GREEN
	END IF
	IF tw_n THEN
		SPRITE 2, 126 + ox + VISIBLE + ZOOMX2, 16 + #tow / 256 + oy + ZOOMY8 + DOUBLEY, GR + BEHIND + C_TWR * 8 + SPR_RED
	ELSE
		SPRITE 2, 0
	END IF
	IF cl_on THEN
		SPRITE 3, clx + ox + VISIBLE + ZOOMX2, cly + oy + ZOOMY4, GR + BEHIND + C_CLD * 8 + SPR_WHITE
	ELSE
		SPRITE 3, 0
	END IF
	IF f_on THEN
		SPRITE 4, CXM + ox + VISIBLE, fy + oy + ZOOMY2, GR + BEHIND + C_FLM * 8 + SPR_ORANGE
	ELSE
		SPRITE 4, 0
	END IF
	SPRITE 5, 12 + ox + VISIBLE + ZOOMX2, 75 + oy + ZOOMY2, GR + C_WING * 8 + SPR_ORANGE
	IF cut_on THEN
		SPRITE 6, 64 + nx + ox + VISIBLE, 88 + oy + ZOOMY2, GR + C_NDL * 8 + SPR_WHITE
	ELSE
		SPRITE 6, 0
	END IF
	END

hide_sprites: PROCEDURE
	FOR i = 0 TO 7: SPRITE i, 0: NEXT i
	END

	' One GRAM update per frame (only the last DEFINE in a frame counts):
	' tower first, then the attitude ball, then the g dial.
gram_tick: PROCEDURE
	IF tw_d THEN tw_d = 0: DEFINE C_TWR, 2, VARPTR twr_clips(tw_n * 8): RETURN
	IF bl_n <> bl_s THEN bl_s = bl_n: DEFINE C_BALL, 9, VARPTR ball_f(bl_s * 36): RETURN
	IF gd_n <> gd_s THEN gd_s = gd_n: DEFINE C_GDL, 9, VARPTR gdial_f(gd_s * 36)
	END

	' Launch tower: 16-row sprite at 4 px per row, cut off at the sill
tower_clip: PROCEDURE
	#k = 8 + #tow / 256
	IF #k >= 46 THEN n = 0 ELSE n = (46 - #k) / 4
	IF n > 16 THEN n = 16
	IF n = tw_n THEN RETURN
	tw_n = n: tw_d = 1
	END

	' One cloud at a time, in either window: streaming down past you while
	' low in the atmosphere, or over the Earth below while in orbit
	' (starting under the horizon's card row, where nothing hides it)
cloud_move: PROCEDURE
	IF cl_on = 0 THEN
		IF stg = 1 THEN
			IF #alt >= 70 OR #ts <= 2 OR RAND >= 8 THEN RETURN
			cly = 16
		ELSE
			IF #hy < 0 OR #hy > 23 OR RAND >= 12 THEN RETURN
			cly = #hy / 8 * 8 + 24
		END IF
		cl_on = 1: clx = 24 + RAND % 32: cl_n = 255
		IF RAND AND 1 THEN clx = clx + 80
	END IF
	IF stg = 1 THEN cly = cly + 1 + #alt / 12 ELSE cly = cly + (FRAME AND 1)
	#k = cly - 8
	IF #k >= 46 THEN cl_on = 0: RETURN
	n = (46 - #k) / 2
	IF n > 8 THEN n = 8
	IF n = cl_n THEN RETURN
	cl_n = n
	DEFINE ALTERNATE C_CLD, 1, VARPTR cld_clips(n * 4)
	END

	' Computer readout, g value, lights
panel: PROCEDURE
	FOR pn = 0 TO 3: GOSUB panel_line: NEXT pn
	END

	' The flight loops update one panel line a frame, so no frame has to
	' print all of them
panel_step: PROCEDURE
	pn = (pn + 1) AND 3
	GOSUB panel_line
	END

panel_line: PROCEDURE
	IF stg = 3 AND pn <> 2 THEN
		' Docking: gap in feet, closing speed (green = safe), bumps
		IF pn = 0 THEN
			#k = #alt / 10		' under 100 turns: the gap is at most 99.9 ft
			PRINT AT 147 COLOR FG_GREEN, "GAP", <.3>#k, "FT"
		ELSEIF pn = 1 THEN
			IF #vg > 10 THEN
				#c = FG_RED
			ELSEIF #vg >= 3 THEN
				#c = FG_GREEN
			ELSE
				#c = FG_TAN
			END IF
			IF #vg < 0 THEN
				#k = 0 - #vg
				PRINT AT 167 COLOR #c, "SPD-", <1>#k / 10, ".", <1>#k % 10, " "
			ELSE
				PRINT AT 167 COLOR #c, "SPD ", <1>#vg / 10, ".", <1>#vg % 10, " "
			END IF
		ELSE
			PRINT AT 207 COLOR FG_GREEN, "BUMPS  ", <1>bumps
			gd_n = 0
			GOSUB lights
		END IF
	ELSEIF stg = 7 AND ev >= 8 AND pn = 0 THEN
		PRINT AT 147 COLOR FG_GREEN, "HOME", <.3>#alt, "K"
	ELSEIF stg = 8 AND pn = 0 THEN
		PRINT AT 147 COLOR FG_GREEN, "FEET", <.3>#alt, "K"
	ELSEIF stg = 8 AND pn = 2 AND cut_on THEN
		PRINT AT 187 COLOR FG_YELLOW, "SKIP"
		PRINT AT 191 COLOR FG_RED, "BURN"
	ELSEIF pn = 0 THEN
		#k = #alt / 8 - #alt / 128 - #alt / 256 + #alt / 1024	' to miles
		PRINT AT 147 COLOR FG_GREEN, "ALT", <.3>#k, "MI"
	ELSEIF pn = 1 THEN
		' ft/s to mph (x 0.6816) with shifts only: dividing by any other
		' constant compiles to a subtract loop, 10,000 turns at Moon speed
		#k = #vel / 2 + #vel / 8 + #vel / 16 - #vel / 128 + #vel / 512
		PRINT AT 167 COLOR FG_GREEN, "MPH", <.5>#k
	ELSEIF pn = 2 THEN
		IF (stg = 2 OR ((stg = 4 OR stg = 7) AND ev = 3)) AND thr = 0 AND #ts < 60 THEN
			#k = 60 - #ts
			PRINT AT 187 COLOR FG_GREEN, "T- ", <1>#k / 60, ":", <2>#k % 60, " "
		ELSE
			PRINT AT 187 COLOR FG_GREEN, "T+", <.2>#ts / 60, ":", <2>#ts % 60, " "
		END IF
	ELSE
		IF cut_on = 0 THEN PRINT AT 207 COLOR FG_GREEN, "G    ", <1>g10 / 10, ".", <1>g10 % 10
		n = g10 * 3 / 10
		IF n > 15 THEN n = 15
		gd_n = n
		GOSUB lights
	END IF
	END

	' Prompt bar. Urgent prompts blink yellow/red.
show_msg: PROCEDURE
	IF msg <> vmsg THEN vmsg = msg: GOSUB say_msg
	IF msg = 4 OR msg = 6 OR msg = 10 OR msg = 11 OR msg = 13 OR msg = 21 OR msg = 24 OR msg = 30 OR msg = 34 OR msg = 64 OR (msg >= 38 AND msg <= 41) OR (msg >= 67 AND msg <= 71) THEN
		IF FRAME AND 16 THEN #c = FG_RED ELSE #c = FG_YELLOW
		IF (FRAME AND 15) <> 0 AND msg = msgp THEN RETURN
	ELSE
		#c = FG_YELLOW
		IF msg = msgp THEN RETURN
	END IF
	msgp = msg
	#d = VARPTR text_msg(0) + msg * 20: #p = 120: GOSUB text20
	END

beep_tick: PROCEDURE
	IF bt THEN
		bt = bt - 1
		IF bt = 0 THEN SOUND 0, 1, 0
	END IF
	END

quiet: PROCEDURE
	SOUND 0, 1, 0: SOUND 1, 1, 0: SOUND 2, 1, 0: SOUND 4, 31, $38
	SOUND 5, 1, 0: SOUND 6, 1, 0: SOUND 7, 1, 0: SOUND 9, 31, $38
	END

	REM ===================== RESULTS ==========================
	' Shown over the windows
results: PROCEDURE
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	FOR i = 20 TO 119: #BACKTAB(i) = BG_BLACK: NEXT i
	IF #tot > 100 THEN #k = #ontgt / (#tot / 100) ELSE #k = 0
	IF #k > 100 THEN #k = 100
	IF #k > pen THEN #k = #k - pen ELSE #k = 0
	IF VOICE.AVAILABLE THEN
		IF fr THEN
			VOICE PLAY v_abort
		ELSEIF stg = 1 OR stg = 4 THEN
			VOICE PLAY v_orbit
		ELSEIF stg = 8 THEN
			VOICE PLAY v_welcome
		ELSEIF stg >= 6 THEN
			VOICE PLAY v_home
		ELSEIF stg <> 5 THEN
			VOICE PLAY v_moon
		END IF
	END IF
	IF fr THEN
		PRINT AT 22 COLOR FG_RED, "MISSION ABORTED"
		#d = VARPTR text_res(0) + (fr - 1) * 40
		#p = 60: #c = FG_WHITE: GOSUB text20
		#d = #d + 20
		#p = 80: #c = FG_TAN: GOSUB text20
	ELSE
		#d = VARPTR text_res(0) + (stg + 18) * 40
		#p = 20: #c = FG_GREEN: GOSUB text20
		#d = #d + 20
		#p = 40: #c = FG_WHITE: GOSUB text20
		n = 2
		IF stg = 3 OR stg = 6 THEN
			PRINT AT 43 COLOR FG_WHITE, "BUMPS: ", <>bumps
			PRINT AT 82 COLOR FG_WHITE, "CONTACT ", <1>#err / 10, ".", <1>#err % 10, " FT/S"
			IF #k >= 70 AND bumps = 0 AND #err <= 6 THEN
				n = 0
			ELSEIF #k >= 50 AND bumps <= 1 THEN
				n = 1
			END IF
		ELSEIF stg = 5 THEN
			PRINT AT 62 COLOR FG_WHITE, "TOUCHDOWN ", <>#err / 64, " FT/S"
			PRINT AT 82 COLOR FG_WHITE, "FUEL LEFT ", <>#cv / 32, "%"
			IF #err <= 192 AND #k >= 50 THEN
				n = 0
			ELSEIF #err <= 320 THEN
				n = 1
			END IF
		ELSE
			IF stg = 8 THEN
				PRINT AT 81 COLOR FG_WHITE, "OUT OF GREEN ", <>#err, " S"
			ELSEIF ABS(#err) <= 8 THEN
				PRINT AT 81 COLOR FG_WHITE, "PERFECT ENGINE STOP"
			ELSEIF #err < 0 THEN
				PRINT AT 81 COLOR FG_WHITE, "TOO SLOW BY ", <>(0 - #err), " FT/S"
			ELSE
				PRINT AT 81 COLOR FG_WHITE, "TOO FAST BY ", <>#err, " FT/S"
			END IF
			IF #k >= 70 AND ABS(#err) <= 8 THEN
				n = 0
			ELSEIF #k >= 50 THEN
				n = 1
			END IF
		END IF
		IF stg = 5 THEN
			PRINT AT 43 COLOR FG_WHITE, "ON THE X ", <>#k, "%"
		ELSE
			PRINT AT 63 COLOR FG_WHITE, "ON COURSE ", <>#k, "%"
		END IF
		#d = VARPTR text_res(0) + (n + 54) * 20
		#p = 100: #c = FG_YELLOW: GOSUB text20
	END IF
	msgp = 255: msg = 0: GOSUB show_msg
	IF fr THEN PRINT AT 120 COLOR FG_YELLOW, "BUTTON: TRY AGAIN" ELSE PRINT AT 120 COLOR FG_YELLOW, "BUTTON: CONTINUE"
	GOSUB wait_release
	#d = 0
	DO
		WAIT
		#d = #d + 1
		IF auto AND #d > 300 THEN RETURN
		GOSUB pads
	LOOP UNTIL b
	GOSUB wait_release
	END

	REM ===================== STAGE 6: LIFT OFF AND MEET UP ===
	' Wait on the Moon for the Command Module to come overhead, lift off when
	' told, hold the aim up to orbit, stop in the green, then look up through
	' the overhead window: slow down and dock. ev (shared with place_lm's
	' meanings): 5 on the Moon, 1 climbing, 6 coasting, 7 docking, 8 docked.
fly_up: PROCEDURE
	GOSUB draw_lm
	DEFINE C_BLD, 2, flag_f
	WAIT
	#ts = 0: sub = 0: comp = 1: ev = 5: fr = 0: thr = 0
	#ex = 200: #ey = -120: #vx = 0: #vy = 0
	#ontgt = 0: #tot = 0: pen = 0: ofs = 0: offs = 0
	tw_n = 0: tw_d = 0: cl_on = 0: f_on = 0: cut_on = 0
	bn = 0: shk = 0: amp = 0: ox = 0: oy = 0: ct = 0: pn = 0
	tp = 0: bmt = 0: bumps = 0: lm_n = 0: lm_s = 255: dcx = 40
	wx = 8: wy = 8: tx = 8: ty = 8: wt = 30: gs = 0
	#cv = 3200: #alt = 0: #vel = 0: #vg = 0: #tv = 0: #err = 0
	#hy = 10: ev_v = 0: msg = 52: msgp = 255: #dl = 99
	bq = 255: ci = 99: ap = 255: dp = 255: ctc = 0
	bl_n = bl_s: gd_n = 15
	FOR i = 0 TO 3: crp(i) = i * 16: crt(i) = i AND 1: cro(i) = 8 + i * 4: NEXT i
	crr = 0: ph = 0: gp = 255
	SOUND 4, 31, $1C
	GOSUB show_comp
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN
			ms = stg: GOSUB map_pause
			GOSUB load_lm
			DEFINE C_BLD, 2, flag_f
			WAIT
			gp = 255: ap = 255: dp = 255: lm_s = 255
			IF ev >= 7 THEN GOSUB draw_up
		END IF

		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND

		IF ev = 5 THEN
			IF msg = 52 THEN
				' Counting down to the ship coming overhead
				IF #ts >= 8 THEN
					msg = 13: #dl = #ts + 10
				ELSE
					n = 8 - #ts
					PRINT AT 139 COLOR FG_WHITE, <1>n
					IF n <= 5 AND n <> ci THEN
						ci = n
						IF VOICE.AVAILABLE THEN VOICE NUMBER n
					END IF
				END IF
			ELSEIF press THEN
				IF #ts > #dl - 7 THEN pen = pen + 10
				ev = 1: comp = 8: #ts = 0: sub = 0: msg = 15: ev_v = 10
				bn = 10: shk = 30: ct = 0: gs = 2
				SOUND 9, 28, $1C
				GOSUB show_comp
			ELSEIF #ts > #dl THEN
				fr = 15: RETURN
			END IF
		ELSEIF ev = 1 THEN
			' The bottom half stays behind and the ground falls away
			IF ct < 160 THEN
				ct = ct + df
			ELSEIF msg = 15 THEN
				msg = 53
			END IF
			#hy = 10 + ct / 8
			#vel = #ts * 22
			#alt = #ts * 200
			#cv = 3200 - #ts * 8
			IF cut_on THEN
				#vg = V_LO - #vel
				GOSUB cut_gauge
				IF press THEN
					#err = 0 - #vg: ev = 6: ct = 0: cut_on = 0: ev_v = 0: comp = 1
					msg = 54: bn = 6: #vg = 0: #hy = 30
					IF ABS(#err) > 64 THEN fr = 3: RETURN
					GOSUB show_comp
				ELSEIF #vg < -120 THEN
					#err = 0 - #vg: fr = 3: RETURN
				END IF
			ELSE
				#vg = -6400
				IF #ts >= 227 THEN
					cut_on = 1: comp = 4: msg = 10: #vg = V_LO - #vel
					GOSUB show_comp
				END IF
			END IF
		ELSEIF ev = 6 THEN
			ct = ct + df
			IF ct >= 120 THEN
				ev = 7: ct = 0: msg = 55: #alt = 4000: #vg = 300: #tv = 0
				#ex = 200: #ey = -120: #vx = 0: #vy = 0: gs = 1: ofs = 0
				lm_s = 255: dp = 255: ap = 255
				GOSUB draw_up
			END IF
		ELSEIF ev = 7 THEN
			' Hold a lower button to slow down; tap the top one to move in
			#d = #alt / 8 + 10
			bk = 0
			IF auto THEN
				IF #vg > #d - 8 THEN bk = 1
			ELSE
				IF CONT.B1 OR CONT.B2 THEN bk = 1
			END IF
			IF bk THEN
				IF press THEN #vg = #vg - 2
				ct = ct + df
				IF ct >= 3 THEN ct = ct - 3: #vg = #vg - 2
				tp = 4
			ELSEIF press THEN
				#vg = #vg + 2: tp = 6
			END IF
			IF #vg > 300 THEN #vg = 300
			IF #vg < -10 THEN #vg = -10
			#tv = #tv + #vg * df
			WHILE #tv >= 60
				#tv = #tv - 60
				IF #alt THEN #alt = #alt - 1
			WEND
			WHILE #tv <= -60: #tv = #tv + 60: #alt = #alt + 1: WEND
			IF #alt > 6000 THEN fr = 7: RETURN
			IF bmt THEN
				bmt = bmt - 1
			ELSEIF offs = 0 THEN
				IF #vg > #d THEN
					msg = 24
				ELSEIF #vg >= 3 THEN
					msg = 25
				ELSE
					msg = 23
				END IF
			END IF
			IF #alt = 0 THEN
				#err = #vg
				IF #vg <= 10 AND ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN
					ev = 8: ct = 0: msg = 56: bn = 6: shk = 10: #vg = 0: comp = 1
					GOSUB show_comp
				ELSE
					bumps = bumps + 1: pen = pen + 10: bn = 10: shk = 25: bmt = 120
					IF #vg > 10 THEN msg = 27 ELSE msg = 28
					IF #vg > 30 OR bumps >= 3 THEN fr = 6: RETURN
					#vg = -3: #alt = 30: #tv = 0: #vx = #vx + 20
				END IF
			END IF
		ELSE
			ct = ct + df
			IF ct >= 150 THEN msg = 57
			IF ct >= 240 THEN RETURN
		END IF

		' Aim, scored on the climb and the approach
		IF ev = 1 OR ev = 7 THEN
			GOSUB wander
			GOSUB attitude
			#tot = #tot + 1
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
			IF offs THEN
				ofs = ofs + 1
				IF ofs > 150 THEN fr = 4: RETURN
				IF msg <> 10 AND bmt = 0 THEN msg = 11
			ELSE
				ofs = 0
				IF msg = 11 AND ev = 1 THEN msg = 53
			END IF
		END IF

		' The Command Module's size from the gap
		#k = #alt + 57: #d = 1824 / #k
		IF #d < 6 THEN
			n = 0
		ELSEIF #d < 18 THEN
			n = (#d - 4) / 2
		ELSE
			n = 7 + (#d - 18) / 4
		END IF
		IF n > 10 THEN n = 10
		lm_n = n

		' Sound: bangs, thrusters, then the engine; the alarm tone
		amp = 0
		IF shk THEN shk = shk - 1: amp = 2
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
		ELSEIF tp THEN
			tp = tp - 1: SOUND 2, 1, 10: SOUND 4, 1, $1C
		ELSEIF ev = 5 OR ev = 6 THEN
			SOUND 2, 1, 0: SOUND 7, 1, 0: SOUND 6, 2800, 0
		ELSE
			GOSUB eng_snd
		END IF
		IF msg = 13 OR msg = 11 OR msg = 24 OR msg = 10 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF

		IF ev >= 7 THEN
			GOSUB place_dock
			GOSUB show_msg
			GOSUB lm_panel
			GOSUB dock_gram
		ELSE
			GOSUB draw_lm_win
			GOSUB place_lm
			' The flag falls away with the ground; the needle while stopping
			IF #hy < 17 THEN
				#k = 34 + (#hy - 10) * 2 + oy
				SPRITE 5, 26 + ox + VISIBLE, #k + ZOOMY2, GR + C_BLD * 8 + SPR_RED
				SPRITE 6, 26 + ox + VISIBLE, #k + ZOOMY2, GR + (C_BLD + 1) * 8 + SPR_BLUE
			ELSEIF cut_on THEN
				SPRITE 6, 104 + nx + VISIBLE, 88 + ZOOMY2, GR + C_NDL * 8 + SPR_WHITE
			END IF
			GOSUB show_msg
			GOSUB lm_panel
			n = ph / 2
			IF n <> gp AND crr THEN
				gp = n: DEFINE C_HZ, 1, VARPTR moon_g(n * 4)
			ELSE
				GOSUB gram_tick
			END IF
		END IF
	WEND
	END

	SEGMENT 2

	REM ===================== STAGE 2: LEAVE EARTH ORBIT ======
	' Coast in orbit and point along your path; at T-0 light the engine;
	' hold the aim while speed builds from orbit speed to Moon speed; stop
	' the engine in the green. ev: 0 point, 1 wait, 2 light it, 3 burn,
	' 4 engine-stop gauge.
fly_tli: PROCEDURE
	GOSUB draw_cockpit
	GOSUB fly_zero
	comp = 4: hold = 0: #ex = 480: #ey = -320: cl_n = 255: msg = 18: orb_l = 1: p = 0
	#cv = V_ORBIT: cvf = 0: #vg = V_TLI - #cv: #err = 0: vn = 0
	#alt = 1018: #vel = #cv
	GOSUB attitude
	#hy = 22 + #my
	GOSUB show_comp
	GOSUB panel
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN ms = stg: GOSUB map_pause

		' Time moves by frames gone by (see fly_launch)
		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND

		IF ev <= 1 THEN
			IF #ts >= 48 AND #ts < 60 THEN
				n = (63 - #ts) / 4
				IF n <> vn THEN vn = n: IF VOICE.AVAILABLE THEN VOICE NUMBER n
			END IF
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN
				IF hold < 60 THEN hold = hold + 1
			ELSE
				hold = 0
			END IF
			IF ev = 0 AND hold >= 60 THEN ev = 1: msg = 19
			IF #ts >= 60 THEN ev = 2: msg = 13: #dl = #ts + 10
		ELSEIF ev = 2 THEN
			IF press THEN
				' Ignition: the clock now counts the burn
				ev = 3: thr = 1: msg = 14: orb_l = 0: comp = 8
				bn = 10: shk = 20: ev_v = 11: #ts = 0: sub = 0
				SOUND 9, 28, $1C
				GOSUB show_comp
			ELSEIF #ts > #dl THEN
				fr = 5: RETURN
			END IF
		ELSE
			' Burning: about 29 ft/s faster every second
			#k = cvf + 29 * comp * df
			WHILE #k >= 60: #k = #k - 60: #cv = #cv + 1: WEND
			cvf = #k
			#vel = #cv
			#vg = V_TLI - #cv
			#alt = 1018 + (#cv - V_ORBIT) / 16 + (#cv - V_ORBIT) / 64
			g10 = 7 + (#cv - V_ORBIT) / 1024
			IF ev = 3 THEN
				IF msg = 14 AND #ts >= 20 THEN msg = 20
				IF #vg < 450 THEN
					ev = 4: comp = 1: cut_on = 1: msg = 10
					GOSUB show_comp
				END IF
			ELSE
				IF press THEN
					#err = 0 - #vg: thr = 0: ev_v = 0: cut_on = 0
					IF ABS(#err) > 64 THEN fr = 3
					RETURN
				END IF
				IF #vg < -120 THEN #err = 0 - #vg: fr = 3: RETURN
			END IF
		END IF

		' Attitude: the nose wanders slowly, faster while the engine burns
		IF ev >= 1 THEN
			IF thr THEN #ey = #ey + 1 ELSE IF FRAME AND 1 THEN #ey = #ey + 1
		END IF
		IF (RAND AND 31) = 0 THEN #vx = #vx + (RAND % 5) - 2
		IF ev >= 1 THEN
			gs = thr: GOSUB wander		' a little stronger while burning
		END IF
		GOSUB attitude
		#hy = 22 + (#cv - V_ORBIT) / 1024 + #my
		#k = (#my + 16) / 2 + 3
		IF #k < 0 THEN #k = 0
		IF #k > 22 THEN #k = 22
		bl_n = #k

		' Score from the first wait to engine stop; off course 2.5 s = lost
		IF ev >= 1 THEN
			#tot = #tot + 1
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
		END IF
		IF offs AND ev >= 1 THEN
			ofs = ofs + 1
			IF ofs > 150 THEN fr = 4: RETURN
			IF msg <> 13 AND msg <> 10 THEN msg = 11
		ELSE
			ofs = 0
			IF msg = 11 THEN
				IF ev = 1 THEN msg = 19 ELSE msg = 20
			END IF
		END IF
		GOSUB cloud_move

		' Shake only at ignition; engine sound and the alarm tone
		amp = 0
		IF shk THEN shk = shk - 1: amp = 2
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
			IF bn = 0 THEN SOUND 4, 31, $1C
		ELSE
			SOUND 2, 1, ev_v: SOUND 7, 1, ev_v: SOUND 6, 2800, ev_v / 2
		END IF
		IF msg = 13 OR msg = 10 OR msg = 11 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF

		GOSUB draw_window
		GOSUB place_sprites
		GOSUB show_msg
		IF cut_on THEN GOSUB cut_gauge
		GOSUB panel_step
		GOSUB gram_tick
	WEND
	END

	REM ===================== STAGE 3: DOCK WITH THE LM =======
	' The lander rides on top of the rocket. Separate, turn round (the
	' Earth swings through the window), then close in on the lander
	' nose-on: the disc keeps its docking target on the crosshair, the top
	' button adds 0.2 ft/s, a lower button brakes. Touch at 1.0 ft/s or
	' less, lined up, to latch; faster or off to one side bumps you back.
	' 3 bumps = failed.
	' ev: 0 riding on the rocket, 1 turning round, 2 closing in, 3 docked.
	' #alt = gap in tenths of a foot, #vg = closing speed in tenths of
	' ft/s (below 0 = drifting apart), #tv = gap remainder.
fly_dock: PROCEDURE
	GOSUB draw_cockpit
	dcx = 0
	#ts = 0: sub = 0: comp = 1: ev = 0: fr = 0: thr = 0
	#ex = 0: #ey = 0: #vx = 0: #vy = 0: #dacc = 0
	#ontgt = 0: #tot = 0: pen = 0: ofs = 0
	tw_n = 0: tw_d = 0: cl_on = 0: f_on = 0
	fl = 0: shk = 0: bn = 0: bt = 0: cut_on = 0: msg = 21: msgp = 255
	eng_l = 2: les_l = 0: mq_l = 0: orb_l = 0: offs = 0: #mx = 0: #my = 0
	#sky = BG_BLACK: amp = 0: ev_v = 0: gd_n = 0: bl_n = 11
	wx = 8: wy = 8: tx = 8: ty = 8: wt = 30: gs = 1
	#alt = 400: #vg = 0: #err = 0: #tv = 0: #vel = 0: g10 = 0
	bumps = 0: ct = 0: bmt = 0: tp = 0: lm_n = 0: lm_s = 255
	#hy = 30
	SOUND 4, 31, $1C
	GOSUB show_comp
	GOSUB panel
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN ms = stg: GOSUB map_pause: lm_s = 255

		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND

		IF ev = 0 THEN
			' Still on the rocket: separate when ready
			IF press THEN ev = 1: ct = 0: eng_l = 0: msg = 22: bn = 10: shk = 20
		ELSEIF ev = 1 THEN
			' Turning round: the Earth swings up into the window and away
			ct = ct + df
			IF ct < 90 THEN #hy = 30 - ct / 6 ELSE #hy = 15 + (ct - 90) / 2
			IF ct >= 180 THEN
				ev = 2: #hy = 60: comp = 4: msg = 23: #vg = -2
				#ex = 384: #ey = -224
				GOSUB show_comp
			END IF
		ELSEIF ev = 2 THEN
			' Closing in: top button adds 0.2 ft/s toward the lander, a lower
			' button takes 0.2 off (and can back you away, up to 1.0 ft/s)
			IF press THEN
				tp = 6
				IF CONT.B1 OR CONT.B2 THEN #vg = #vg - 2 ELSE #vg = #vg + 2
				IF #vg > 30 THEN #vg = 30
				IF #vg < -10 THEN #vg = -10
			END IF
			#tv = #tv + #vg * comp * df
			WHILE #tv >= 60
				#tv = #tv - 60
				IF #alt THEN #alt = #alt - 1
			WEND
			WHILE #tv <= -60: #tv = #tv + 60: #alt = #alt + 1: WEND
			IF #alt > 999 THEN fr = 7: RETURN
			IF bmt THEN
				bmt = bmt - 1
			ELSEIF offs = 0 THEN
				IF #vg > 10 THEN
					msg = 24
				ELSEIF #vg >= 3 THEN
					msg = 25
				ELSE
					msg = 23
				END IF
			END IF
			IF #alt = 0 THEN
				#err = #vg
				IF #vg <= 10 AND ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN
					' Latched
					ev = 3: ct = 0: msg = 26: bn = 6: shk = 10: #vg = 0: comp = 1
					GOSUB show_comp
				ELSE
					' Bump: knocked back and aside
					bumps = bumps + 1: pen = pen + 10: bn = 10: shk = 25: bmt = 120
					IF #vg > 10 THEN msg = 27 ELSE msg = 28
					#vg = -3: #alt = 30: #tv = 0: #vx = #vx + 20
					IF bumps >= 3 THEN fr = 6: RETURN
				END IF
			END IF
		ELSE
			' Docked: latches hold, then the lander is pulled free
			ct = ct + df
			IF ct >= 150 THEN msg = 29
			IF ct >= 240 THEN RETURN
		END IF

		' Aim: the lander drifts about; steer to keep it on the crosshair
		IF ev = 2 THEN
			GOSUB wander
			GOSUB attitude
			#k = (#my + 16) / 2 + 3
			IF #k < 0 THEN #k = 0
			IF #k > 22 THEN #k = 22
			bl_n = #k
			#tot = #tot + 1
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
			IF offs THEN
				ofs = ofs + 1
				IF ofs > 150 THEN fr = 4: RETURN
				IF bmt = 0 THEN msg = 11
			ELSE
				ofs = 0
			END IF
		END IF

		' Lander size from the gap: 4 px at 40 ft, 32 px at contact
		#k = #alt + 57: #d = 1824 / #k
		IF #d < 6 THEN
			n = 0
		ELSEIF #d < 18 THEN
			n = (#d - 4) / 2
		ELSE
			n = 7 + (#d - 18) / 4
		END IF
		IF n > 10 THEN n = 10
		lm_n = n

		' Shake, thruster puffs, bangs and the alarm tone
		amp = 0
		IF shk THEN shk = shk - 1: amp = 2
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
			IF bn = 0 THEN SOUND 4, 31, $1C
		ELSEIF tp THEN
			tp = tp - 1: SOUND 2, 1, 10: SOUND 4, 1, $1C
			IF tp = 0 THEN SOUND 4, 31, $1C
		ELSEIF ev = 2 AND (al OR ar OR au OR ad) THEN
			' Maneuvering thrusters: softer and fluttering while you steer
			SOUND 4, 3, $1C
			IF FRAME AND 4 THEN SOUND 2, 1, 8 ELSE SOUND 2, 1, 5
		ELSE
			SOUND 2, 1, 0
		END IF
		IF msg = 21 OR msg = 24 OR msg = 11 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF

		GOSUB draw_window
		GOSUB place_dock
		GOSUB show_msg
		GOSUB panel_step
		GOSUB dock_gram
	WEND
	END

	' Docking sprites: bold 2x crosshair, the yellow <> on the docking
	' target, the dark lander (2, 3) in front of the rocket's grey top
	' (4, 7), so the two things to line up stand out. Lander 2x when close.
place_dock: PROCEDURE
	IF amp THEN
		IF FRAME AND 1 THEN ox = RAND % (amp + 1): oy = RAND % (amp + 1)
	ELSE
		ox = 0: oy = 0
	END IF
	SCROLL ox, oy, 0
	SPRITE 0, CXM - 4 + dcx + ox + VISIBLE + ZOOMX2, CYM - 4 + oy + ZOOMY4, GR + C_RET * 8 + SPR_WHITE
	IF ev >= 2 THEN
		blk = 0
		IF offs THEN IF FRAME AND 8 THEN blk = 1
		IF blk THEN
			SPRITE 1, 0
		ELSE
			SPRITE 1, CXM + dcx + #mx + ox + VISIBLE, CYM + #my + oy + ZOOMY2, GR + C_DIA * 8 + SPR_YELLOW
		END IF
		x = 40 + dcx + #mx + ox: y = 28 + #my + oy
		IF stg = 6 THEN #c = SPR_BLACK ELSE #c = SPR_BROWN
		IF lm_n > 6 THEN
			SPRITE 2, x - 8 + VISIBLE + ZOOMX2, y - 8 + ZOOMY4 + DOUBLEY, GR + #c
			SPRITE 3, x + 8 + VISIBLE + ZOOMX2, y - 8 + ZOOMY4 + DOUBLEY, GR + 16 + #c
			SPRITE 4, x - 8 + VISIBLE + ZOOMX2, y - 8 + ZOOMY4 + DOUBLEY, GR + 32 + SPR_GREY
			SPRITE 7, x + 8 + VISIBLE + ZOOMX2, y - 8 + ZOOMY4 + DOUBLEY, GR + 48 + SPR_GREY
		ELSE
			SPRITE 2, x + VISIBLE, y + ZOOMY2 + DOUBLEY, GR + #c
			SPRITE 3, x + 8 + VISIBLE, y + ZOOMY2 + DOUBLEY, GR + 16 + #c
			SPRITE 4, x + VISIBLE, y + ZOOMY2 + DOUBLEY, GR + 32 + SPR_GREY
			SPRITE 7, x + 8 + VISIBLE, y + ZOOMY2 + DOUBLEY, GR + 48 + SPR_GREY
		END IF
	ELSE
		SPRITE 1, 0: SPRITE 2, 0: SPRITE 3, 0: SPRITE 4, 0: SPRITE 7, 0
	END IF
	IF stg = 3 THEN SPRITE 5, 12 + ox + VISIBLE + ZOOMX2, 75 + oy + ZOOMY2, GR + C_WING * 8 + SPR_ORANGE ELSE SPRITE 5, 0
	SPRITE 6, 0
	END

	' Lander frames go into GRAM 0-7 (the horizon cards, unused once the
	' window is all black space); otherwise the usual ball/dial updates
dock_gram: PROCEDURE
	n = lm_n
	IF n > 6 THEN n = n - 4
	IF ev >= 2 AND n <> lm_s THEN
		lm_s = n
		IF stg = 6 THEN DEFINE 0, 8, VARPTR cm_f(n * 32) ELSE DEFINE 0, 8, VARPTR lm_f(n * 32)
		RETURN
	END IF
	GOSUB gram_tick
	END

	REM ===================== STAGE 4: BRAKE AT THE MOON =====
	' The Moon grows ahead; turn round so the engine faces forward; the
	' Moon's edge rises and the Earth sets behind it, which cuts the radio;
	' light the engine alone, hold the aim while speed falls to orbit
	' speed, and stop in the green: early = fly past, late = hit the Moon.
	' Then the Earth rises over the Moon. ev: 0 approach, 1 wait to turn,
	' 2 turning, 3 behind the Moon, 4 light it, 5 burn, 6 engine-stop
	' gauge, 7 Earthrise.
fly_moon: PROCEDURE
	GOSUB draw_cockpit
	GOSUB fly_zero
	comp = 8: #ex = 256: #ey = -160: msg = 32: p = 0: bl_n = 11
	#cv = V_ARR: cvf = 0: #vg = V_ARR - V_LO: #err = 0: vn = 0
	#alt = 8700: #vel = 3000: g10 = 0
	lm_n = 0: lm_s = 255: cd = 1: hz = 0: eo = 0: et = 34: ct = 0: en = 0: es = 255
	#hy = 60
	' Right-window craters wait: the Earth needs their sprites until it sets
	crp(0) = 0: crp(1) = 32: crp(2) = 224: crp(3) = 192: crr = 0: ph = 0: gp = 0
	FOR i = 0 TO 3: crt(i) = i AND 1: cro(i) = 8 + i * 4: NEXT i
	bm = 35
	IF stg = 7 THEN
		ev = 3: #ts = 40: comp = 4: msg = 34: hz = 1: #hy = 16: orb_l = 1: bm = 20
		#cv = 6600: #vg = 1200: #vel = 5400: #alt = 609: #ey = 160
	END IF
	SOUND 4, 31, $1C
	GOSUB attitude
	GOSUB show_comp
	GOSUB panel
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN
			ms = stg: GOSUB map_pause
			lm_s = 255: cd = 1: es = 255: gp = 255
			IF ev >= 3 THEN hz = 1
		END IF

		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND

		IF ev = 0 THEN
			' Falling toward the Moon: closer, faster, bigger in the window
			#alt = 8700 - #ts * 81
			#vel = 3000 + #ts * 54
			n = #ts / 9
			IF n > 10 THEN n = 10
			lm_n = n
			IF #ts >= 96 THEN ev = 1: msg = 30: #dl = #ts + 80
		ELSEIF ev = 1 THEN
			IF press THEN
				ev = 2: ct = 0: msg = 31: comp = 1
				GOSUB show_comp
			ELSEIF #ts > #dl THEN
				fr = 11: RETURN
			END IF
		ELSEIF ev = 2 THEN
			' The Moon slides out of the window as the ship swings round
			ct = ct + df
			IF ct >= 120 THEN
				ev = 3: hz = 1: eo = 1: et = 34: #ts = 0: sub = 0: comp = 4: msg = 33
				#ex = 320: #ey = 160: #vel = V_ARR: #alt = 870
				GOSUB show_comp
			END IF
		ELSEIF ev = 3 THEN
			' Behind the Moon: its edge rises, the Earth sets, radio gone
			IF #ts < 44 THEN #hy = 60 - #ts ELSE #hy = 16
			' Static burst, then nothing: the radio is gone
			IF #ts >= 44 AND eo = 1 THEN eo = 0: msg = 34: bn = 8
			IF #ts >= 48 AND #ts < 60 THEN
				n = (63 - #ts) / 4
				IF n <> vn THEN vn = n: IF VOICE.AVAILABLE THEN VOICE NUMBER n
			END IF
			IF #ts >= 60 THEN ev = 4: msg = 13: #dl = #ts + 20
		ELSEIF ev = 4 THEN
			IF press THEN
				ev = 5: thr = 1: msg = bm: comp = 8
				bn = 10: shk = 20: ev_v = 11: #ts = 0: sub = 0
				SOUND 9, 28, $1C
				GOSUB show_comp
			ELSEIF #ts > #dl THEN
				fr = 5: RETURN
			END IF
		ELSEIF ev <= 6 THEN
			' Burning: about 8 ft/s slower every second
			#k = cvf + 8 * comp * df
			WHILE #k >= 60: #k = #k - 60: #cv = #cv - 1: WEND
			cvf = #k
			#vel = #cv
			#vg = #cv - V_LO
			IF #vg >= 0 THEN #alt = 609 + #vg / 16 + #vg / 32 ELSE #alt = 609
			IF stg = 7 THEN #vel = 12000 - #cv: #alt = 1368 - #alt
			g10 = 3 + (V_ARR - #cv) / 1024
			IF ev = 5 THEN
				IF #vg < 450 THEN
					ev = 6: comp = 4: cut_on = 1: msg = 10
					GOSUB show_comp
				END IF
			ELSE
				IF press THEN
					#err = #vg: thr = 0: ev_v = 0: cut_on = 0: g10 = 0
					IF stg = 7 AND ABS(#err) > 64 THEN fr = 3: RETURN
					IF #err > 64 THEN fr = 8: RETURN
					IF #err < -64 THEN fr = 10: RETURN
					ev = 7: ct = 0: et = 44: comp = 1: msg = 37: orb_l = 1
					IF stg = 7 THEN msg = 54: orb_l = 0
					GOSUB show_comp
				ELSEIF #vg < -120 THEN
					#err = #vg
					IF stg = 7 THEN fr = 3 ELSE fr = 10
					RETURN
				END IF
			END IF
		ELSE
			' In orbit: the nose lifts, right-window craters run out, and then
			' the Earth comes up over the Moon with the radio back
			ct = ct + df
			IF ct >= 110 AND eo = 0 THEN eo = 1: msg = 36
			IF eo THEN IF (FRAME AND 3) = 0 AND et > 26 THEN et = et - 1
			IF ct >= 240 THEN RETURN
		END IF

		' Aim: gentle while coasting, rougher while the engine burns
		IF ev <> 2 AND ev < 7 THEN
			gs = thr * 2
			GOSUB wander
			GOSUB attitude
			#k = (#my + 16) / 2 + 3
			IF #k < 0 THEN #k = 0
			IF #k > 22 THEN #k = 22
			bl_n = #k
		END IF
		' Horizon follows the aim; after engine stop it sinks for the Earthrise
		IF ev >= 4 THEN
			IF ev = 7 THEN #k = 28 ELSE #k = 16 + #my
			IF ev < 7 OR (FRAME AND 3) = 0 THEN
				IF #hy < #k THEN #hy = #hy + 1 ELSE IF #hy > #k THEN #hy = #hy - 1
			END IF
		END IF

		' Score from behind the Moon to engine stop; off course 2.5 s = lost
		IF ev >= 3 AND ev < 7 THEN
			#tot = #tot + 1
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
			IF offs THEN
				ofs = ofs + 1
				IF ofs > 150 THEN fr = 4: RETURN
				IF msg <> 13 AND msg <> 10 THEN msg = 11
			ELSE
				ofs = 0
				IF msg = 11 THEN
					IF ev = 5 THEN
						msg = bm
					ELSEIF eo THEN
						msg = 33
					ELSE
						msg = 34
					END IF
				END IF
			END IF
		END IF

		' The Earth's rows below the Moon's edge are cut off (2 px a row)
		#k = et - #hy
		IF #k <= 0 THEN
			en = 0
		ELSEIF #k >= 15 THEN
			en = 8
		ELSE
			en = (#k + 1) / 2
		END IF

		' Shake only at ignition; radio hiss until the Earth sets and after
		' it rises; maneuvering thrusters while coasting
		amp = 0
		IF shk THEN shk = shk - 1: amp = 2
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
			IF bn = 0 THEN SOUND 4, 31, $1C
		ELSEIF thr THEN
			SOUND 2, 1, ev_v
		ELSEIF ev = 2 OR ((al OR ar OR au OR ad) AND ev < 7) THEN
			SOUND 4, 3, $1C
			IF FRAME AND 4 THEN SOUND 2, 1, 8 ELSE SOUND 2, 1, 5
		ELSEIF eo OR ev < 3 THEN
			SOUND 4, 1, $1C: SOUND 2, 1, 2
		ELSE
			SOUND 2, 1, 0
		END IF
		' Mission Control muttering on the radio: bursts of wandering tones
		IF eo OR ev < 3 THEN
			IF (FRAME AND 7) = 0 THEN
				IF (FRAME AND 64) AND (RAND AND 3) THEN SOUND 0, 100 + (RAND AND 63), 5 ELSE SOUND 0, 1, 0
			END IF
		ELSE
			SOUND 0, 1, 0
		END IF
		SOUND 7, 1, ev_v: SOUND 6, 2800, ev_v / 2
		IF msg = 30 OR msg = 13 OR msg = 10 OR msg = 11 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF

		GOSUB draw_moon
		GOSUB place_moon
		GOSUB show_msg
		IF cut_on THEN GOSUB cut_gauge
		GOSUB panel_step
		GOSUB moon_gram
	WEND
	END

	' Windows over the Moon: like draw_window, but grey ground. Foreground
	' cards can't be grey, so the ground is the card background and the
	' horizon cards (moon_hz) paint the sky black on top of it, with a bumpy
	' edge and speckles so it doesn't read as more window frame.
draw_moon: PROCEDURE
	FOR i = 0 TO 4
		#k = #hy - i * 8
		IF #k >= 8 THEN
			#d = BG_BLACK
			IF i = 0 THEN #d = GR + C_LIPT * 8 + BG_BLACK
			IF i = 4 THEN #d = GR + C_LIPB * 8 + BG_BLACK
		ELSEIF #k <= 0 THEN
			#d = GR + C_HZ * 8 + BG_GREY
			IF i = 0 THEN #d = GR + C_LIPT * 8 + BG_GREY
			IF i = 4 THEN #d = GR + C_LIPB * 8 + BG_GREY
		ELSE
			#d = GR + (C_HZ + #k) * 8 + BG_GREY
		END IF
		IF (#d AND 255) <> rowlo(i) OR (#d / 256) <> rowhi(i) THEN
			rowlo(i) = #d AND 255: rowhi(i) = #d / 256
			IF #k >= 4 THEN #k = GR + C_EDI * 8 + BG_GREY ELSE #k = GR + BG_GREY
			#p = i * 20 + 21
			#BACKTAB(#p) = (C_EDL + i) * 8 + #k
			#BACKTAB(#p + 7) = (C_EDR + i) * 8 + #k
			#BACKTAB(#p + 10) = (C_EDL + i) * 8 + #k
			#BACKTAB(#p + 17) = (C_EDR + i) * 8 + #k
			FOR j = 1 TO 6: #BACKTAB(#p + j) = #d: #BACKTAB(#p + j + 10) = #d: NEXT j
		END IF
	NEXT i
	END

	' Sprites: bold crosshair and yellow <> (as in docking); the Moon ahead
	' (2, 3), or a crater (2) once low over it; the Earth (7) and its land
	' (4), clipped at the horizon in GRAM; 6 is the engine-stop needle.
place_moon: PROCEDURE
	IF amp THEN
		IF FRAME AND 1 THEN ox = RAND % (amp + 1): oy = RAND % (amp + 1)
	ELSE
		ox = 0: oy = 0
	END IF
	SCROLL ox, oy, 0
	' White and yellow wash out on the grey ground: red and blue over it
	IF #hy < 24 THEN
		#c = SPR_RED: #d = SPR_BLUE
	ELSE
		#c = SPR_WHITE: #d = SPR_YELLOW
	END IF
	SPRITE 0, CXM - 4 + ox + VISIBLE + ZOOMX2, CYM - 4 + oy + ZOOMY4, GR + C_RET * 8 + #c
	blk = 0
	IF offs THEN IF FRAME AND 8 THEN blk = 1
	IF blk OR ev = 2 OR ev = 7 THEN
		SPRITE 1, 0
	ELSE
		SPRITE 1, CXM + #mx + ox + VISIBLE, CYM + #my + oy + ZOOMY2, GR + C_DIA * 8 + #d
	END IF
	IF ev >= 8 THEN
		GOSUB place_earth
	ELSEIF ev >= 3 THEN
		GOSUB place_craters
	ELSE
		SPRITE 3, 0
		x = 40 + #mx + ox
		#k = 28 + #my + oy
		IF ev = 2 THEN #k = #k - ct / 2
		IF #k < 18 THEN
			SPRITE 2, 0
		ELSEIF lm_n > 6 THEN
			SPRITE 2, x - 8 + VISIBLE + ZOOMX2, #k - 8 + ZOOMY4 + DOUBLEY, GR + SPR_GREY
			SPRITE 3, x + 8 + VISIBLE + ZOOMX2, #k - 8 + ZOOMY4 + DOUBLEY, GR + 16 + SPR_GREY
		ELSE
			SPRITE 2, x + VISIBLE, #k + ZOOMY2 + DOUBLEY, GR + SPR_GREY
			SPRITE 3, x + 8 + VISIBLE, #k + ZOOMY2 + DOUBLEY, GR + 16 + SPR_GREY
		END IF
	END IF
	IF eo THEN
		SPRITE 4, 120 + ox + VISIBLE + ZOOMX2, et + oy + ZOOMY4, GR + (C_TWR + 1) * 8 + SPR_GREEN
		SPRITE 7, 120 + ox + VISIBLE + ZOOMX2, et + oy + ZOOMY4, GR + C_TWR * 8 + SPR_BLUE
	ELSEIF ev < 3 THEN
		SPRITE 4, 0: SPRITE 7, 0
	END IF
	SPRITE 5, 12 + ox + VISIBLE + ZOOMX2, 75 + oy + ZOOMY2, GR + C_WING * 8 + SPR_ORANGE
	IF cut_on THEN
		SPRITE 6, 64 + nx + ox + VISIBLE, 88 + oy + ZOOMY2, GR + C_NDL * 8 + SPR_WHITE
	ELSE
		SPRITE 6, 0
	END IF
	END

	' Four craters, two to a window (one each side while the Earth is up);
	' two get moved and drawn each pass to save time. Black and BEHIND, so they
	' vanish into the sky above and the prompt bar below. Farther down the
	' window: bigger, and moving away from the middle. Finished ones come back
	' with a new size and spot, except on the right after engine stop, because
	' the Earth needs those sprites.
place_craters: PROCEDURE
	crr = crr XOR 1
	IF thr OR ev = 7 THEN cs = 2 ELSE cs = 1
	IF cs = 2 OR crr THEN ph = (ph + 1) AND 15
	FOR i = crr TO crr + 2 STEP 2
		IF i < 2 OR eo = 0 THEN
			IF crp(i) <> 64 THEN crp(i) = crp(i) + cs
			IF crp(i) >= 64 AND crp(i) < 128 THEN
				IF ev = 7 AND i >= 2 THEN
					crp(i) = 64
				ELSE
					crp(i) = 0
					n = RAND AND 3
					IF n = 3 THEN n = 1
					crt(i) = n
					cro(i) = RAND AND 31
				END IF
			END IF
			j = i + 2
			IF i = 3 THEN j = 7
			#k = 99
			IF crp(i) < 64 THEN #k = 16 + #hy + crater_y(crp(i)) + oy
			IF #k < 56 THEN
				n = crater_b(crp(i))
				x = crater_l(crt(i) * 5 + n)
				n = n + 2
				#d = cro(i) * n / 8 - n * 2 + ox - crater_w(x)
				IF i < 2 THEN #d = #d + 48 ELSE #d = #d + 128
				SPRITE j, #d + VISIBLE + crater_zx(x), #k + crater_zy(x), GR + BEHIND + crater_cd(x) * 8 + SPR_BLACK
			ELSE
				SPRITE j, 0
			END IF
		END IF
	NEXT i
	END

	' Craters: pixels below the horizon and distance band, by progress
crater_y:	DATA 0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1
	DATA 2,2,2,2,3,3,3,4,4,4,5,5,6,6,7,7
	DATA 8,8,9,9,10,10,11,11,12,13,13,14,15,15,16,17
	DATA 18,18,19,20,21,21,22,23,24,25,26,27,28,29,30,31
crater_b:	DATA 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	DATA 0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1
	DATA 1,1,2,2,2,2,2,2,2,3,3,3,3,3,3,3
	DATA 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
	' Drawn size for each type (small, medium, large) and distance band
crater_l:	DATA 0,0,0,1,1
	DATA 0,1,2,2,4
	DATA 1,2,3,5,6
	' Each drawn size: width zoom, height zoom, card, half width
crater_zx:	DATA 0,0,ZOOMX2,0,ZOOMX2,0,ZOOMX2
crater_zy:	DATA 0,ZOOMY2,ZOOMY2,0,ZOOMY4,ZOOMY2,ZOOMY2
crater_cd:	DATA C_FLM,C_FLM,C_FLM,C_CLD,C_FLM,C_CLD,C_CLD
crater_w:	DATA 2,2,4,4,4,4,8

	' One GRAM change a frame: the craters (C_FLM, C_CLD); the Earth clipped at the
	' horizon (C_TWR, +1); the Moon in GRAM 0-3 while the window is black,
	' then the grey-ground horizon cards there instead.
moon_gram: PROCEDURE
	IF cd THEN cd = 0: DEFINE C_FLM, 2, moon_x: RETURN
	IF hz THEN hz = 0: DEFINE 0, 10, moon_hz: RETURN
	IF eo AND en <> es THEN es = en: DEFINE C_TWR, 2, VARPTR earth_f(en * 8): RETURN
	IF ev >= 3 THEN
		n = ph / 2
		IF n <> gp THEN gp = n: DEFINE C_HZ, 1, VARPTR moon_g(n * 4): RETURN
	END IF
	IF ev < 3 THEN
		n = lm_n
		IF n > 6 THEN n = n - 4
		IF n <> lm_s THEN lm_s = n: DEFINE 0, 4, VARPTR moon_f(n * 16): RETURN
	END IF
	GOSUB gram_tick
	END

	REM ===================== STAGE 5: LAND ON THE MOON ========
	' The lander: slanted windows looking down, drift dial, height and speed
	' tapes (A, D), fuel dial. Light the engine and hold the aim while it brakes; clear
	' a computer alarm; tip over and see the ground; boulders at the landing X
	' move it, so steer back onto it; at 400 ft you fly: hold the button to
	' slow your fall and touch down gently on the X before the fuel runs out.
	' ev: 0 light it, 1 braking, 2 tipping over, 3 computer flying,
	' 4 you fly, 5 landed, 6 crashed.
	' #alt = feet, #vg = falling speed in 1/64 ft/s (+ = down), #tv = part of a
	' foot, #cv = fuel (3200 full, 32 = 1%).
fly_land: PROCEDURE
	GOSUB draw_lm
	#ts = 0: sub = 0: comp = 1: ev = 0: fr = 0: thr = 0
	#ex = 256: #ey = -160: #vx = 0: #vy = 0
	#ontgt = 0: #tot = 0: pen = 0: ofs = 0: offs = 0
	tw_n = 0: tw_d = 0: cl_on = 0: f_on = 0: cut_on = 0
	bn = 0: shk = 0: amp = 0: ox = 0: oy = 0: ct = 0: pn = 0
	wx = 8: wy = 8: tx = 8: ty = 8: wt = 30: gs = 0
	#cv = 3200: #alt = 50000: #vel = 5500: #vg = 0: #tv = 0: #err = 0
	#hy = 30: ev_v = 0: msg = 13: msgp = 255: #dl = 10
	bq = 255: cf = 0: ci = 0: tq = 0: ap = 255: dp = 255: ak = 0: ctc = 0
	bl_n = bl_s: gd_n = 15
	FOR i = 0 TO 3: crp(i) = i * 16: crt(i) = i AND 1: cro(i) = 8 + i * 4: NEXT i
	crr = 0: ph = 0: gp = 255
	SOUND 4, 31, $1C
	GOSUB show_comp
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN
			ms = stg: GOSUB map_pause
			GOSUB load_lm
			gp = 255: ap = 255: dp = 255
		END IF

		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND

		IF ev = 0 THEN
			IF press THEN
				ev = 1: comp = 8: #ts = 0: sub = 0: msg = 35: ev_v = 10
				bn = 10: shk = 20
				SOUND 9, 28, $1C
				GOSUB show_comp
			ELSEIF #ts > #dl THEN
				fr = 5: RETURN
			END IF
		ELSEIF ev = 1 THEN
			' Braking on the way down, ground just showing below the windows
			#alt = 50000 - #ts * 179
			#vel = 5500 - #ts * 22
			#cv = 3200 - #ts * 4
			#vg = 6400
			IF #ts >= 130 AND ak = 0 THEN ak = 1: msg = 38: #dl = #ts + 40
			IF msg = 38 THEN
				IF auto THEN IF (FRAME AND 60) = 0 THEN press = 1
				IF press THEN
					msg = 35
				ELSEIF #ts > #dl THEN
					msg = 35: pen = pen + 10
				END IF
			END IF
			IF #ts >= 240 THEN
				ev = 2: ct = 0: comp = 1: msg = 43
				GOSUB show_comp
			END IF
		ELSEIF ev = 2 THEN
			' The ship tips over and the ground comes up into the windows
			ct = ct + df
			IF ct < 160 THEN #hy = 30 - ct / 8 ELSE #hy = 10
			IF ct >= 180 THEN
				ev = 3: #ts = 0: sub = 0: comp = 8: msg = 44
				#ex = 200: #ey = -100: #vx = 0: #vy = 0
				GOSUB show_comp
			END IF
		ELSEIF ev = 3 THEN
			' The computer flies down to the X; boulders there, so the X moves
			#alt = 7040 - #ts * 40
			#vel = 220 - #ts
			#vg = (20 + (166 - #ts) / 2) * 64
			#cv = 2240 - #ts / 2
			IF #ts >= 100 AND bq = 255 THEN bq = 0
			IF #ts >= 124 AND bq = 0 THEN bq = 16: #ex = #ex + 512: msg = 40: ofs = 0
			IF #ts >= 166 THEN
				ev = 4: comp = 1: #ts = 0: sub = 0: ct = 0: msg = 45
				#alt = 400: #vg = 1280: #tv = 0: #cv = 2160
				GOSUB show_comp
			END IF
		ELSEIF ev = 4 THEN
			' You fly. The button slows your fall; the Moon pulls you down.
			IF ct < 240 THEN ct = ct + df
			#d = #alt * 4 + 192		' a safe falling speed for this height
			IF auto THEN
				IF #vg > #d - 64 THEN tq = 1
				IF #vg < #d - 112 THEN tq = 0
			ELSE
				tq = b
			END IF
			IF #cv = 0 THEN tq = 0
			IF tq THEN
				#vg = #vg - 13 * df
				IF #cv > df THEN #cv = #cv - df ELSE #cv = 0
			END IF
			#vg = #vg + 6 * df
			IF #vg < -640 THEN #vg = -640
			IF #vg > 3840 THEN #vg = 3840
			#tv = #tv + #vg * df
			WHILE #tv >= 3840
				#tv = #tv - 3840
				IF #alt > 0 THEN #alt = #alt - 1
			WEND
			WHILE #tv <= -3840
				#tv = #tv + 3840
				IF #alt < 999 THEN #alt = #alt + 1
			WEND
			#vel = #alt / 8

			' Heights called out, like the voice in the real cockpit
			IF #alt <= lm_call(ci) THEN
				IF VOICE.AVAILABLE THEN VOICE NUMBER lm_call(ci)
				ci = ci + 1
			END IF

			IF #alt <= 5 THEN
				ctc = 1: msg = 48
			ELSEIF #vg > #d + 256 THEN
				msg = 39
			ELSEIF msg = 39 AND #vg > #d THEN
				msg = 39
			ELSEIF #cv < 640 THEN
				msg = 41
			ELSEIF ct < 240 THEN
				msg = 45
			ELSEIF #alt < 60 THEN
				msg = 47
			ELSE
				msg = 46
			END IF

			IF #alt = 0 AND #vg > 0 THEN
				#err = #vg: ev_v = 0: ct = 0
				IF #vg > 448 THEN
					IF #cv = 0 THEN cf = 14 ELSE cf = 12
				ELSEIF ABS(#mx) > 8 OR ABS(#my) > 8 THEN
					cf = 13
				END IF
				IF cf THEN
					ev = 6: shk = 60
				ELSE
					ev = 5: msg = 49
				END IF
			END IF
		ELSEIF ev = 5 THEN
			' Engine off, a beat of silence, then the famous line
			ct = ct + df
			IF ct >= 40 AND ci < 99 THEN
				ci = 99
				IF VOICE.AVAILABLE THEN VOICE INIT: VOICE PLAY v_eagle
			END IF
			IF ct >= 240 THEN RETURN
		ELSE
			ct = ct + df
			IF ct >= 60 THEN fr = cf: RETURN
		END IF

		' Aim: rougher while the engine is braking
		IF ev <> 2 AND ev < 5 THEN
			IF ev = 1 THEN gs = 2 ELSE gs = 1
			IF ev = 0 THEN gs = 0
			GOSUB wander
			GOSUB attitude
		END IF

		' Score the flying; off course 2.5 s = lost, until the boulders
		IF ev = 1 OR ev = 3 OR ev = 4 THEN
			#tot = #tot + 1
			IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
		END IF
		IF ev = 1 OR (ev = 3 AND bq < 16) THEN
			IF offs THEN
				ofs = ofs + 1
				IF ofs > 150 THEN fr = 4: RETURN
				IF msg <> 38 THEN msg = 11
			ELSE
				ofs = 0
				IF msg = 11 THEN
					IF ev = 1 THEN msg = 35 ELSE msg = 44
				END IF
			END IF
		END IF

		' Sound: engine louder with the button, thruster hiss when steering
		amp = 0
		IF shk THEN
			shk = shk - 1: amp = 2
		ELSEIF ev = 4 AND tq AND #alt < 30 THEN
			amp = 1
		END IF
		IF bn THEN
			bn = bn - 1: SOUND 2, 1, 15: SOUND 4, 8, $1C
		ELSEIF ev = 6 THEN
			SOUND 2, 1, 15: SOUND 4, 20, $1C
		ELSEIF ev = 5 THEN
			SOUND 2, 1, 0
		ELSE
			IF ev = 4 THEN
				' The engine swells and fades, so tapping the button can't rattle
				eg = eg + df
				IF #cv = 0 THEN
					ev_v = 0
				ELSEIF tq THEN
					IF eg >= 3 THEN
						eg = 0
						IF ev_v < 12 THEN ev_v = ev_v + 1
					END IF
				ELSEIF eg >= 12 THEN
					eg = 0
					IF ev_v > 6 THEN ev_v = ev_v - 1
				END IF
			END IF
			GOSUB eng_snd
		END IF
		IF bn OR ev >= 5 THEN SOUND 7, 1, ev_v: SOUND 6, 2800, ev_v / 2
		SOUND 0, 1, 0
		IF msg = 13 OR msg = 11 OR (msg >= 38 AND msg <= 41) THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF

		GOSUB draw_lm_win
		GOSUB place_lm
		GOSUB show_msg
		GOSUB lm_panel
		' One GRAM change a frame: ground dots, then the dials
		n = ph / 2
		IF n <> gp AND crr THEN
			gp = n: DEFINE C_HZ, 1, VARPTR moon_g(n * 4)
		ELSE
			GOSUB gram_tick
		END IF
	WEND
	END

	' The engine holds a steady note; steering adds a hiss on the ECS sound
	' chip beside it, so the engine is never interrupted. With the engine
	' off, the hiss flutters on the main chip, as in docking.
eng_snd: PROCEDURE
	IF ev_v THEN
		SOUND 4, 24, $1C: SOUND 2, 1, ev_v
		IF al OR ar OR au OR ad THEN
			SOUND 9, 3, $1C: SOUND 7, 1, 6
		ELSE
			SOUND 9, 28, $1C: SOUND 7, 1, ev_v
		END IF
	ELSEIF al OR ar OR au OR ad THEN
		SOUND 4, 3, $1C
		IF FRAME AND 4 THEN SOUND 2, 1, 8 ELSE SOUND 2, 1, 5
		SOUND 7, 1, 0
	ELSE
		SOUND 2, 1, 0: SOUND 7, 1, 0
	END IF
	SOUND 6, 2800, ev_v / 2
	END

	' Lander graphics, on top of the command module's set
load_lm: PROCEDURE
	DEFINE C_DS, 18, lm_cards
	WAIT
	DEFINE C_BALL, 9, lm_drift
	WAIT
	DEFINE C_FLM, 2, moon_x
	WAIT
	DEFINE 0, 10, moon_hz
	WAIT
	END

draw_lm: PROCEDURE
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	GOSUB load_cm
	GOSUB load_lm
	BORDER BORDER_GREY
	FOR i = 0 TO 239: #BACKTAB(i) = BG_GREY: NEXT i
	#d = VARPTR text_msg(0) + (stg + 45) * 20: #p = 0: #c = PNL: GOSUB text20
	FOR i = 120 TO 139: #BACKTAB(i) = BG_BLACK: NEXT i
	FOR i = 0 TO 2
		FOR j = 0 TO 2
			#BACKTAB(140 + i * 20 + j) = GR + (C_BALL + i * 3 + j) * 8 + FG_WHITE
			#BACKTAB(149 + i * 20 + j) = GR + (C_GDL + i * 3 + j) * 8 + FG_WHITE
		NEXT j
	NEXT i
	FOR i = 0 TO 3
		FOR j = 12 TO 19: #BACKTAB(140 + i * 20 + j) = BG_BLACK: NEXT j
	NEXT i
	PRINT AT 200 COLOR PNL, "DRIFT"
	PRINT AT 206 COLOR PNL, "AD"
	GOSUB trip_strip
	FOR i = 0 TO 4: rowlo(i) = 255: rowhi(i) = 255: NEXT i
	END

	' The two slanted windows: each row is one card shorter than the last. A
	' row is redrawn when it changes. Sky above #hy, grey ground below it.
draw_lm_win: PROCEDURE
	FOR i = 0 TO 4
		#k = #hy - i * 8
		IF #k >= 8 THEN
			#d = BG_BLACK
		ELSEIF #k <= 0 THEN
			#d = GR + C_HZ * 8 + BG_GREY
		ELSE
			#d = GR + (C_HZ + #k) * 8 + BG_GREY
		END IF
		IF (#d AND 255) <> rowlo(i) OR (#d / 256) <> rowhi(i) THEN
			rowlo(i) = #d AND 255: rowhi(i) = #d / 256
			n = 8 - i
			#p = i * 20 + 20
			IF #k >= 4 THEN #k = C_DS ELSE #k = C_DG
			#BACKTAB(#p + n) = GR + #k * 8 + BG_GREY
			#BACKTAB(#p + 19 - n) = GR + (#k + 1) * 8 + BG_GREY
			#BACKTAB(#p) = GR + C_LV * 8 + BG_GREY
			#BACKTAB(#p + 19) = GR + C_RV * 8 + BG_GREY
			FOR j = 1 TO n - 1
				#BACKTAB(#p + j) = #d
				#BACKTAB(#p + 19 - j) = #d
			NEXT j
			IF i = 0 THEN #BACKTAB(37) = GR + C_EARTH * 8 + FG_BLUE
		END IF
	NEXT i
	END

	' Sprites: 0 aim, 1 the <> or the landing X, 2 3 4 7 craters, 5 boulders,
	' 6 the drift dial's dot.
place_lm: PROCEDURE
	IF amp THEN
		IF FRAME AND 1 THEN ox = RAND % (amp + 1): oy = RAND % (amp + 1)
	ELSE
		ox = 0: oy = 0
	END IF
	SCROLL ox, oy, 0
	IF #hy < 24 THEN
		#c = SPR_RED: #d = SPR_BLUE
	ELSE
		#c = SPR_WHITE: #d = SPR_YELLOW
	END IF
	IF ev >= 5 THEN
		SPRITE 0, 0: SPRITE 1, 0: SPRITE 5, 0: SPRITE 6, 0
	ELSE
		SPRITE 0, LX - 4 + ox + VISIBLE + ZOOMX2, LY - 4 + oy + ZOOMY4, GR + C_RET * 8 + #c
		blk = 0
		IF offs THEN IF FRAME AND 8 THEN blk = 1
		IF blk OR ev = 2 THEN
			SPRITE 1, 0
		ELSEIF ev >= 3 THEN
			SPRITE 1, LX + #mx + ox + VISIBLE, LY + #my + oy + ZOOMY2, GR + C_LX * 8 + #d
		ELSE
			SPRITE 1, LX + #mx + ox + VISIBLE, LY + #my + oy + ZOOMY2, GR + C_DIA * 8 + #d
		END IF
		' Boulders stay where the first X was
		#k = LY + #my + oy
		#d = LX + #mx - bq + ox - 4
		IF bq < 255 AND #alt >= 100 AND #d >= 16 AND #d + #k <= 72 THEN
			SPRITE 5, #d + VISIBLE + ZOOMX2, #k + ZOOMY2, GR + C_BLD * 8 + SPR_BLACK
		ELSE
			SPRITE 5, 0
		END IF
		' Drift dot: how fast the X is sliding, centred on the dial
		#d = #vx / 2 + (wx - 8) * 2
		IF #d > 10 THEN #d = 10
		IF #d < -10 THEN #d = -10
		#k = #vy / 2 + wy - 8
		IF #k > 10 THEN #k = 10
		IF #k < -10 THEN #k = -10
		SPRITE 6, 19 + #d + VISIBLE, 75 + #k + ZOOMY2, GR + C_LD * 8 + SPR_ORANGE
	END IF
	GOSUB lm_craters
	END

	' Craters come down the windows, two moved and drawn a pass. They stop as
	' you come to a hover; low down the ground dots turn to rushing dust.
lm_craters: PROCEDURE
	crr = crr XOR 1
	IF ev >= 5 OR #alt < 40 THEN
		cs = 0
	ELSEIF #vel > 40 THEN
		cs = 2
	ELSE
		cs = 1
	END IF
	IF ev < 5 THEN
		IF #alt < 60 THEN
			ph = (ph + 2) AND 15
		ELSEIF cs = 2 OR crr THEN
			ph = (ph + 1) AND 15
		END IF
	END IF
	FOR i = crr TO crr + 2 STEP 2
		crp(i) = crp(i) + cs
		IF crp(i) >= 64 THEN
			crp(i) = 0
			n = RAND AND 3
			IF n = 3 THEN n = 1
			IF #alt < 200 THEN n = 2
			crt(i) = n
			cro(i) = RAND AND 31
		END IF
		j = i + 2
		IF i = 3 THEN j = 7
		#k = 16 + #hy + crater_y(crp(i)) + oy
		IF #k < 56 THEN
			n = crater_b(crp(i))
			x = crater_l(crt(i) * 5 + n)
			y = 72 - #k - crater_w(x) * 2
			#d = cro(i) * y / 32 + #mx / 2
			IF #d < 0 THEN #d = 0
			IF #d > y THEN #d = y
			IF i < 2 THEN #d = #d + 16 ELSE #d = #d + 87 + #k
			SPRITE j, #d + ox + VISIBLE + crater_zx(x), #k + crater_zy(x), GR + BEHIND + crater_cd(x) * 8 + SPR_BLACK
		ELSE
			SPRITE j, 0
		END IF
	NEXT i
	END

	' Panel: one line a pass. Green computer, tapes, fuel, lights, alarm lamp.
lm_panel: PROCEDURE
	pn = (pn + 1) AND 3
	IF ev >= 7 AND pn < 3 THEN GOSUB up_panel: RETURN
	IF pn = 0 THEN
		PRINT AT 152 COLOR FG_GREEN, "ALT", <.5>#alt
	ELSEIF pn = 1 THEN
		IF cut_on THEN RETURN
		#c = FG_GREEN
		IF ev = 4 AND #vg > #alt * 4 + 320 THEN #c = FG_RED
		IF #vg < 0 THEN
			#k = (0 - #vg) / 64
			PRINT AT 172 COLOR #c, "UP  ", <.4>#k
			n = 0
		ELSE
			#k = #vg / 64
			PRINT AT 172 COLOR #c, "DOWN", <.4>#k
			IF #k > 23 THEN n = 23 ELSE n = #k
		END IF
		IF n <> dp OR ev = 4 THEN dp = n: #p = 147: GOSUB lm_tape
	ELSEIF pn = 2 THEN
		PRINT AT 192 COLOR FG_GREEN, "FWD ", <.4>#vel
		#k = #alt / 16
		IF #k > 23 THEN n = 0 ELSE n = 23 - #k
		IF n <> ap THEN ap = n: #p = 146: #c = FG_YELLOW: GOSUB lm_tape
	ELSE
		IF #cv < 640 THEN #c = FG_RED ELSE #c = FG_GREEN
		#k = #cv / 32
		IF cut_on = 0 THEN PRINT AT 212 COLOR #c, "FUEL", <.3>#k, "%"
		n = #cv / 256 + #cv / 1024
		IF n > 15 THEN n = 15
		gd_n = n
		IF ev >= 7 THEN RETURN
		' Lights: low fuel blinks, contact is blue like the real one
		#c = PNL
		IF #cv < 640 AND ev < 5 THEN
			IF FRAME AND 16 THEN #c = FG_BLACK + BG_RED
		END IF
		PRINT AT 86 COLOR #c, "LOW FUEL"
		IF ctc THEN #c = FG_WHITE + BG_BLUE ELSE #c = PNL
		PRINT AT 106 COLOR #c, "CONTACT"
		#c = BG_BLACK
		IF msg = 13 OR msg = 11 OR (msg >= 38 AND msg <= 41) THEN
			IF FRAME AND 8 THEN #c = BG_RED
		END IF
		#BACKTAB(49) = GR + C_LAMP * 8 + #c
		#BACKTAB(50) = GR + C_LAMP * 8 + #c
	END IF
	END

	' Draw a tape (3 cards tall from BACKTAB #p) with its bar n pixels down
lm_tape: PROCEDURE
	FOR i = 0 TO 2
		IF n / 8 = i THEN
			#BACKTAB(#p + i * 20) = GR + (C_TP + (n AND 7)) * 8 + #c
		ELSE
			#BACKTAB(#p + i * 20) = GR + (C_TP + 8) * 8 + #c
		END IF
	NEXT i
	END

lm_call:	DATA 300, 200, 100, 50, 20, 0

	' Stage 4 briefing
	REM ===================== DATA =============================

	' Commanded pitch, degrees above the horizon, every 10 s (interpretive)
pitch_t:
	DATA 90,90,86,80,74,68,63,58,54,50
	DATA 47,44,41,38,35,32,30,29,28,27
	DATA 26,25,25,24,24,23,23,22,22,21
	DATA 21,20,20,19,19,18,18,17,17,16
	DATA 16,15,15,14,14,13,13,13,12,12
	DATA 12,12,11,11,11,10,10,9,9,8
	DATA 8,7,7,6,6,5,5,4,4,3
	DATA 3,2

	' Acceleration in tenths of g, every 10 s (interpretive shape:
	' stage 1 to 3.8 g, stage 2 0.9-1.8 g, stage 3 0.6-0.8 g)
gee_t:
	DATA 12,13,14,15,16,17,18,19,20,22
	DATA 23,25,27,29,31,34,38,9,9,10
	DATA 10,10,11,11,11,12,12,12,13,13
	DATA 13,13,14,14,14,15,15,15,16,16
	DATA 16,17,17,17,18,18,14,14,15,15
	DATA 15,15,16,16,16,6,6,6,6,6
	DATA 6,7,7,7,7,7,7,7,8,8
	DATA 8,8

	' Re-entry: height at the start of each event and its fall per tick
down_b:	DATA 900, 900, 0, 600, 400, 108, 0, 24, 0, 0
down_r:	DATA 8, 8, 0, 10, 2, 6, 0, 1, 0, 0
	' The fire, every 16 ticks: g in tenths, heat band
fire_g:	DATA 3, 10, 25, 45, 65, 50, 30, 20, 12, 10
fire_b:	DATA 0, 1, 2, 2, 3, 3, 2, 1, 0
	' Heat band: card background (flickers between two), flame colour
fire_bg:	DATA BG_BLACK, BG_BLACK, BG_RED, BG_RED, BG_ORANGE, BG_RED, BG_YELLOW, BG_ORANGE
fire_fg:	DATA FG_RED, FG_YELLOW, FG_YELLOW, FG_WHITE

	' Engine-stop gauge zone colours
zone_bg:
	DATA BG_BLACK,BG_BLACK,BG_BLACK,BG_BLACK,BG_YELLOW,BG_GREEN,BG_GREEN,BG_RED
	DATA BG_RED,BG_YELLOW,BG_GREEN,BG_GREEN,BG_GREEN,BG_GREEN,BG_YELLOW,BG_RED

	' Trip strip column of the ship during stage 1-8
trip_col:
	DATA 0,1,3,6,16,18,18,16,1

	' Stage names (0-8), where you are after each stage (0-8), then during
	' each stage (1-8), 20 characters each
txt:
	DATA "ON THE LAUNCH PAD   "
	DATA "LIFTOFF             "
	DATA "LEAVE EARTH ORBIT   "
	DATA "DOCK WITH THE LM    "
	DATA "BRAKE AT THE MOON   "
	DATA "LAND ON THE MOON    "
	DATA "LIFT OFF AND MEET UP"
	DATA "HEAD HOME           "
	DATA "RE-ENTRY            "
	DATA "YOU: ON THE PAD     "
	DATA "YOU: IN EARTH ORBIT "
	DATA "YOU: FLYING TO MOON "
	DATA "YOU: FLYING TO MOON "
	DATA "YOU: IN MOON ORBIT  "
	DATA "YOU: ON THE MOON    "
	DATA "YOU: IN MOON ORBIT  "
	DATA "YOU: FLYING HOME    "
	DATA "YOU: HOME!          "
	DATA "YOU: GOING TO ORBIT "
	DATA "YOU: LEAVING ORBIT  "
	DATA "YOU: DOCKING        "
	DATA "YOU: BRAKING AT MOON"
	DATA "YOU: LANDING        "
	DATA "YOU: LIFTING OFF    "
	DATA "YOU: HEADING HOME   "
	DATA "YOU: COMING DOWN    "

	INCLUDE "ascent.bas"

	REM ===================== SPOKEN CALLOUTS ==================
	' Intellivoice, if plugged in. Phrases are built from the speech chip's
	' basic sounds. Segment 4 ($7100) is free once the ECS ROM is off.
	SEGMENT 4

	' Say the prompt that just appeared (only the ones that need you)
say_msg: PROCEDURE
	IF VOICE.AVAILABLE = 0 THEN RETURN
	IF msg = 13 THEN VOICE INIT: VOICE PLAY v_ignition
	IF msg = 15 THEN VOICE PLAY v_liftoff
	IF msg = 4 THEN VOICE INIT: VOICE PLAY v_staging
	IF msg = 6 THEN VOICE INIT: VOICE PLAY v_tower
	IF msg = 10 THEN VOICE INIT: VOICE PLAY v_stop
	IF msg = 11 THEN
		IF VOICE.PLAYING = 0 THEN VOICE PLAY v_course
	END IF
	IF msg = 21 THEN VOICE INIT: VOICE PLAY v_separate
	IF msg = 24 THEN VOICE INIT: VOICE PLAY v_toofast
	IF msg = 27 OR msg = 28 THEN VOICE INIT: VOICE PLAY v_bump
	IF msg = 26 THEN VOICE INIT: VOICE PLAY v_docked
	IF msg = 30 THEN VOICE INIT: VOICE PLAY v_turn
	IF msg = 34 THEN VOICE INIT: VOICE PLAY v_radio
	IF msg = 36 THEN VOICE INIT: VOICE PLAY v_earth
	IF msg = 38 THEN VOICE INIT: VOICE PLAY v_alarm
	IF msg = 39 THEN
		IF VOICE.PLAYING = 0 THEN VOICE PLAY v_toofast
	END IF
	IF msg = 40 THEN VOICE INIT: VOICE PLAY v_boulders
	IF msg = 41 THEN VOICE INIT: VOICE PLAY v_lowfuel
	IF msg = 45 THEN VOICE INIT: VOICE PLAY v_youfly
	IF msg = 48 THEN VOICE INIT: VOICE PLAY v_contact
	IF msg = 55 THEN VOICE INIT: VOICE PLAY v_ship
	IF msg = 56 THEN VOICE INIT: VOICE PLAY v_docked
	IF msg = 64 THEN VOICE INIT: VOICE PLAY v_fix
	IF msg = 66 THEN VOICE INIT: VOICE PLAY v_lined
	IF msg = 67 THEN VOICE INIT: VOICE PLAY v_separate
	IF msg = 68 OR msg = 69 THEN VOICE INIT: VOICE PLAY v_chutes
	IF msg = 70 THEN
		IF VOICE.PLAYING = 0 THEN VOICE PLAY v_steep
	END IF
	IF msg = 71 THEN
		IF VOICE.PLAYING = 0 THEN VOICE PLAY v_flat
	END IF
	IF msg = 74 THEN VOICE INIT: VOICE PLAY v_houston
	END

v_apollo:	VOICE AX, PA2, PP, AA, LL, OW, PA1, 0
v_ignition:	VOICE IH, GG1, PA1, NN1, IH, IH, SH, AX, NN1, PA1, 0
v_liftoff:	VOICE LL, IH, FF, PA2, TT2, AO, AO, FF, PA1, 0
v_staging:	VOICE SS, PA3, TT2, EY, PA1, JH, IH, NG1, PA1, 0
v_tower:	VOICE DD2, RR1, AA, PP, PA2, TT2, AW, ER1, PA1, 0
v_stop:		VOICE SS, PA3, TT2, AA, PP, PA2, EH, NN1, JH, IH, NN1, PA1, 0
v_course:	VOICE AO, AO, FF, PA2, KK3, OR2, SS, PA1, 0
v_orbit:	VOICE OR2, PA2, BB2, IH, TT2, PA1, 0
v_moon:		VOICE AA, NN1, PA2, TT2, UW2, PA1, DH1, AX, PA1, MM, UW2, NN1, PA1, 0
v_abort:	VOICE AX, PA2, BB2, OR2, TT2, PA1, 0
v_separate:	VOICE SS, EH, EH, PA2, PP, ER1, EY, PA2, TT2, PA1, 0
v_toofast:	VOICE TT2, UW2, PA1, FF, AE1, AE1, SS, PA2, TT2, PA1, 0
v_bump:		VOICE BB2, AX, AX, MM, PA2, PP, PA1, 0
v_docked:	VOICE DD2, AA, AA, PA2, KK2, PA1, TT2, PA1, 0
v_turn:		VOICE TT2, ER1, NN1, PA2, ER1, AW, NN1, DD1, PA1, 0
v_radio:	VOICE RR1, EY, PA1, DD2, IY, OW, PA2, LL, AO, SS, PA2, TT2, PA1, 0
v_earth:	VOICE ER1, TH, PA2, RR1, AY, ZZ, PA1, 0
v_alarm:	VOICE AX, LL, AR, MM, PA1, 0
v_boulders:	VOICE BB2, OW, LL, DD1, ER1, ZZ, PA1, 0
v_lowfuel:	VOICE LL, OW, PA2, FF, YY2, UW2, EL, PA1, 0
v_youfly:	VOICE YY2, UW2, PA2, FF, LL, AY, PA1, 0
v_contact:	VOICE KK3, AA, NN1, PA1, TT2, AE1, KK2, PA1, TT2, PA2, LL, AY, PA1, TT2, PA1, 0
v_base:	VOICE WW, EH, EH, LL, PA1, KK1, AX, MM, PA2, TT2, UW2, PA2, TT2, RR1, AE1, NG1, KK1, WH, IH, LL, IH, TT2, IY, PA2, BB2, EY, SS, PA1, 0
v_ship:	VOICE MM, AA, PA1, JH, UW2, EL, PA2, AX, HH1, EH, EH, DD1, PA1, 0
v_home:	VOICE WW, IY, PA2, AR, PA2, GG1, OW, IH, NG1, PA2, HH1, OW, MM, PA1, 0
v_fix:	VOICE KK3, OR2, SS, PA2, KK1, ER1, EH, KK2, SH, AX, NN1, PA1, 0
v_lined:	VOICE LL, AY, NN1, DD1, PA2, AX, PP, PA1, 0
v_chutes:	VOICE SH, UW2, UW2, PA2, TT2, SS, PA1, 0
v_steep:	VOICE TT2, UW2, PA1, SS, PA3, TT2, IY, IY, PA2, PP, PA1, 0
v_flat:		VOICE TT2, UW2, PA1, FF, LL, AE1, AE1, PA2, TT2, PA1, 0
v_houston:	VOICE HH1, YY2, UW2, SS, PA2, TT2, AX, NN1, PA1, 0
v_splash:	VOICE SS, PA3, PP, LL, AE1, AE1, SH, PA2, DD2, AW, NN1, PA1, 0
v_welcome:	VOICE WW, EH, EH, LL, PA1, KK1, AX, MM, PA2, HH1, OW, MM, PA1, 0
v_eagle:	VOICE DH1, AX, PA2, IY, IY, PA1, GG1, EL, PA3, HH1, AE1, ZZ, PA2, LL, AE1, AE1, NN1, DD1, IH, DD2, PA1, 0

	' The overhead window, for docking: a square of black sky over the panel
draw_up: PROCEDURE
	FOR i = 20 TO 119: #BACKTAB(i) = BG_GREY: NEXT i
	FOR i = 1 TO 5
		#p = i * 20
		FOR j = 5 TO 14: #BACKTAB(#p + j) = BG_BLACK: NEXT j
		#BACKTAB(#p + 4) = GR + C_LV * 8 + BG_GREY
		#BACKTAB(#p + 15) = GR + C_RV * 8 + BG_GREY
	NEXT i
	FOR i = 0 TO 5: #BACKTAB(up_s(i)) = 14 * 8 + FG_WHITE: NEXT i
	#BACKTAB(33) = GR + C_EARTH * 8 + FG_BLUE
	GOSUB hide_sprites
	END

up_s:	DATA 26, 47, 72, 93, 107, 113

	' Lander computer while docking: gap, closing speed, bumps, and the tapes
up_panel: PROCEDURE
	IF pn = 0 THEN
		#k = #alt / 10
		PRINT AT 152 COLOR FG_GREEN, "GAP ", <.4>#k
	ELSEIF pn = 1 THEN
		#c = FG_GREEN
		IF #vg > #alt / 8 + 10 THEN #c = FG_RED
		IF #vg < 0 THEN #k = 0 - #vg: #c = FG_YELLOW ELSE #k = #vg
		PRINT AT 172 COLOR #c, "SPD", <.3>#k / 10, ".", <1>#k % 10
		n = #k / 10
		IF n > 23 THEN n = 23
		IF n <> dp THEN dp = n: #p = 147: GOSUB lm_tape
	ELSE
		PRINT AT 192 COLOR FG_GREEN, "BUMPS ", <.2>bumps
		n = 23 - #alt / 256
		IF n <> ap THEN ap = n: #p = 146: #c = FG_YELLOW: GOSUB lm_tape
	END IF
	END

	' The landing celebration, once a frame during the base scene: a crowd
	' roar (noise) that swells and fades, a fanfare on two tones, and the
	' headline changing colour. cel counts in steps of 4 frames.
cheer: PROCEDURE
	IF FRAME AND 3 THEN RETURN
	cel = cel + 1
	IF cel > 130 THEN cel = 0: GOSUB quiet: RETURN

	IF cel < 14 THEN
		n = cel
	ELSEIF cel > 104 THEN
		n = (130 - cel) / 2
	ELSE
		n = 13
	END IF
	IF n > 1 THEN n = n - (RAND AND 1)
	SOUND 4, 6 + (RAND AND 7), $1C: SOUND 2, 1, n
	SOUND 9, 9 + (RAND AND 7), $1C: SOUND 7, 1, n

	i = cel / 2
	IF i < 26 THEN
		j = 13
		IF i >= 22 THEN j = 13 - (i - 22) * 3
		IF fan_a(i) = 0 THEN j = 0
		SOUND 0, fan_a(i), j
		IF j > 2 THEN SOUND 1, fan_b(i), j - 2 ELSE SOUND 1, 1, 0
		j = fan_c(i AND 3)
	ELSE
		SOUND 0, 1, 0: SOUND 1, 1, 0
		j = FG_YELLOW
	END IF
	FOR i = 42 TO 57: #BACKTAB(i) = (#BACKTAB(i) AND $FFF8) + j: NEXT i
	END

	REM ===================== SPLASHDOWN =====================
	' The end of the trip: the capsule floats down under three chutes, hits
	' the sea, the chutes fall away, and the helicopter comes in from the
	' ship while the crowd roars. #tv counts frames.
sea_scene: PROCEDURE
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	BORDER BORDER_BLACK
	CLS
	DEFINE 10, SEA_N, sea_c
	WAIT
	FOR i = 0 TO 79: #BACKTAB(i) = BG_BLUE: NEXT i
	FOR i = 80 TO 159: #BACKTAB(i) = BG_CYAN: NEXT i
	FOR i = 160 TO 239: #BACKTAB(i) = GR + (10 + (i AND 1)) * 8 + FG_WHITE + BG_BLUE: NEXT i
	FOR i = 0 TO SEA_E - 1: #BACKTAB(sea_bt(i * 2)) = sea_bt(i * 2 + 1): NEXT i
	cel = 0: #tv = 0: x = 168
	GOSUB wait_release
	DO
		WAIT
		#tv = #tv + 1
		' The waves roll; the helicopter's rotor spins
		i = #tv AND 7
		IF i = 0 THEN
			#k = (#tv / 8) AND 3
			DEFINE 10, 2, VARPTR wave_f(#k * 8)
		ELSEIF (i AND 1) THEN
			DEFINE 12, 1, VARPTR heli_f((i / 2 AND 1) * 4)
		END IF
		IF #tv < 280 THEN
			' Down under the chutes, wind only
			SOUND 4, 28, $1C: SOUND 2, 1, 4
			y = 16 + #tv / 8
			cn = y
		ELSE
			y = 51 + ((#tv / 32) AND 1)
			IF #tv = 280 THEN
				SOUND 4, 14, $1C: SOUND 2, 1, 15: SOUND 7, 1, 15
				IF VOICE.AVAILABLE THEN VOICE INIT: VOICE PLAY v_splash
				#d = VARPTR text_msg(0) + 76 * 20: #p = 20: #c = FG_WHITE + BG_BLUE: GOSUB text20
				#d = #d + 20: #p = 40: #c = FG_YELLOW + BG_BLUE: GOSUB text20
			END IF
			IF #tv < 320 THEN cn = 51 + (#tv - 280) / 2 ELSE cn = 99
		END IF
		' Spray, then the crowd and the fanfare
		IF #tv >= 280 AND #tv < 340 THEN
			SPRITE 5, 72 + VISIBLE + ZOOMX2, 58 + ((#tv - 280) / 16) + ZOOMY4, GR + 14 * 8 + SPR_WHITE
			IF #tv < 330 AND (#tv AND 3) = 0 THEN SOUND 2, 1, 15 - (#tv - 280) / 5: SOUND 7, 1, 15 - (#tv - 280) / 5
		ELSE
			SPRITE 5, 0
		END IF
		IF #tv = 340 THEN cel = 1
		IF cel THEN GOSUB cheer
		SPRITE 1, 72 + VISIBLE + ZOOMX2, y + 16 + ZOOMY2, GR + 13 * 8 + SPR_WHITE
		IF cn < 70 THEN
			SPRITE 2, 56 + VISIBLE + ZOOMX2, cn - 16 + ZOOMY4, GR + 16 * 8 + SPR_ORANGE
			SPRITE 3, 72 + VISIBLE + ZOOMX2, cn - 16 + ZOOMY4, GR + 16 * 8 + SPR_WHITE
			SPRITE 4, 88 + VISIBLE + ZOOMX2, cn - 16 + ZOOMY4, GR + 16 * 8 + SPR_ORANGE
			' The lines meet on top of the capsule until it hits the water
			IF #tv < 280 THEN
				SPRITE 0, 64 + VISIBLE + ZOOMX2, cn + ZOOMY4 + FLIPX, GR + 17 * 8 + SPR_WHITE
				SPRITE 7, 80 + VISIBLE + ZOOMX2, cn + ZOOMY4, GR + 17 * 8 + SPR_WHITE
			ELSE
				SPRITE 0, 0: SPRITE 7, 0
			END IF
		ELSE
			SPRITE 2, 0: SPRITE 3, 0: SPRITE 4, 0: SPRITE 0, 0: SPRITE 7, 0
		END IF
		IF #tv >= 340 THEN
			IF x > 96 AND (#tv AND 7) = 0 THEN x = x - 1
			SPRITE 6, x + VISIBLE + ZOOMX2, 40 + ZOOMY2, GR + 12 * 8 + SPR_BLACK
			IF (#tv AND 31) = 0 THEN
				IF #tv AND 32 THEN #d = VARPTR text_msg(0) + 58 * 20 ELSE #d = VARPTR text_msg(0) + 61 * 20
				#p = 220: #c = FG_WHITE + BG_BLUE: GOSUB text20
			END IF
		END IF
		IF auto AND #tv > 900 THEN EXIT DO
		GOSUB pads
	LOOP UNTIL #tv >= 120 AND b
	GOSUB wait_release
	cel = 0
	GOSUB quiet
	GOSUB hide_sprites
	CLS
	END

	' Tone periods, 8 frames a note; 0 = rest
fan_a:	DATA 285, 0, 285, 0, 214, 0, 170, 0, 143, 143, 143, 0, 170, 0, 143, 143, 143, 143, 107, 107, 107, 107, 107, 107, 107, 107
fan_b:	DATA 428, 0, 428, 0, 285, 0, 214, 0, 170, 170, 170, 0, 214, 0, 170, 170, 170, 170, 143, 143, 143, 143, 143, 143, 143, 143
fan_c:	DATA FG_YELLOW, FG_WHITE, FG_GREEN, FG_RED

	SEGMENT 2

	' Launch tower and cloud, pre-clipped at the window sill
	INCLUDE "clips.bas"

	' Cockpit cards, ball and dial frames, trip map
	INCLUDE "gfx.bas"

	REM ===================== TRANQUILITY BASE =================
	' The reward for landing: the lander on the Moon, a waving flag, one
	' astronaut saluting and one waving, the Earth overhead, the welcome,
	' then the fanfare and the crowd. GRAM 10-47 are free here: whatever
	' comes next reloads its own cards.
base_scene: PROCEDURE
	GOSUB hide_sprites
	SCROLL 0, 0, 0
	BORDER BORDER_BLACK
	CLS
	DEFINE 10, 6, flag_a
	WAIT
	DEFINE 16, 2, ast_f
	WAIT
	DEFINE 18, 2, VARPTR ast_f(16)
	WAIT
	DEFINE 20, 2, earth_f
	WAIT
	DEFINE 22, 16, base_c
	WAIT
	DEFINE 38, BASE_N - 16, VARPTR base_c(64)
	WAIT
	FOR i = 140 TO 219: #BACKTAB(i) = GR + C_HZ * 8 + BG_GREY: NEXT i
	FOR i = 220 TO 239: #BACKTAB(i) = BG_GREY: NEXT i
	#BACKTAB(162) = GR + C_FLM * 8 + BG_GREY
	#BACKTAB(189) = GR + (C_FLM + 1) * 8 + BG_GREY
	#BACKTAB(205) = GR + C_FLM * 8 + BG_GREY
	#BACKTAB(173) = GR + C_FLM * 8 + BG_GREY
	FOR i = 0 TO BASE_E - 1: #BACKTAB(base_bt(i * 2)) = base_bt(i * 2 + 1): NEXT i
	#d = VARPTR text_msg(0) + 59 * 20: #p = 20: #c = FG_WHITE: GOSUB text20
	#d = #d + 20: #p = 40: #c = FG_YELLOW: GOSUB text20
	SPRITE 1, 42 + VISIBLE + ZOOMX2, 46 + ZOOMY4 + DOUBLEY, GR + 16 * 8 + SPR_WHITE
	SPRITE 2, 84 + VISIBLE + ZOOMX2, 46 + ZOOMY4 + DOUBLEY, GR + 18 * 8 + SPR_WHITE
	SPRITE 3, 62 + VISIBLE + ZOOMX2, 44 + ZOOMY4 + DOUBLEY, GR + 14 * 8 + SPR_BLUE
	SPRITE 4, 62 + VISIBLE + ZOOMX2, 44 + ZOOMY4 + DOUBLEY, GR + 12 * 8 + SPR_RED
	SPRITE 5, 62 + VISIBLE + ZOOMX2, 44 + ZOOMY4 + DOUBLEY, GR + 10 * 8 + SPR_WHITE
	SPRITE 6, 16 + VISIBLE + ZOOMX2, 36 + ZOOMY4, GR + 21 * 8 + SPR_GREEN
	SPRITE 7, 16 + VISIBLE + ZOOMX2, 36 + ZOOMY4, GR + 20 * 8 + SPR_BLUE
	IF VOICE.AVAILABLE THEN VOICE INIT: VOICE PLAY v_base
	cel = 0: #tv = 0: n = 0
	GOSUB wait_release
	DO
		WAIT
		#tv = #tv + 1
		' One GRAM change a frame: flag ripple, then the two astronauts
		i = #tv AND 15
		IF (i AND 7) = 0 THEN
			j = (#tv / 8) % 3
			DEFINE 10, 6, VARPTR flag_a(j * 24)
		ELSEIF i = 4 THEN
			IF #tv >= 80 THEN DEFINE 16, 2, VARPTR ast_f(8)
		ELSEIF i = 12 THEN
			IF (#tv / 16) AND 1 THEN DEFINE 18, 2, VARPTR ast_f(24) ELSE DEFINE 18, 2, VARPTR ast_f(16)
		END IF
		IF #tv = 170 THEN cel = 1
		IF cel THEN GOSUB cheer
		IF (#tv AND 31) = 0 THEN
			IF #tv AND 32 THEN #d = VARPTR text_msg(0) + 58 * 20 ELSE #d = VARPTR text_msg(0) + 61 * 20
			#p = 220: #c = PNL: GOSUB text20
		END IF
		IF auto AND #tv > 600 THEN EXIT DO
		GOSUB pads
	LOOP UNTIL b
	GOSUB wait_release
	cel = 0
	GOSUB quiet
	GOSUB hide_sprites
	CLS
	END

	REM ===================== STAGE 7: HEAD HOME ==============
	' fly_moon flies the far side: light the engine, stop in the green, see
	' the Earth rise. Then this: the Earth ahead grows. Twice the ship slips
	' off the line home: hold the button to burn, let go in the green.
	' ev: 8 coasting, 9 correcting, 10 lined up. #alt = thousand miles to Earth.
fly_home: PROCEDURE
	ev = 8: #hy = 60: eo = 0: comp = 8: #ts = 0: sub = 0: msg = 63: g10 = 0
	#alt = 240: #ex = 480: #ey = -200: ofs = 0: cn = 0: tq = 0: eg = 0: ct = 0
	lm_n = 0: lm_s = 255
	GOSUB show_comp
	lf = FRAME
	WHILE 1
		WAIT
		GOSUB read_input
		IF fr THEN RETURN
		IF kpress THEN
			ms = stg: GOSUB map_pause
			lm_s = 255
		END IF

		df = FRAME - lf: lf = FRAME
		IF df > 4 THEN df = 1
		sub = sub + comp * df
		WHILE sub >= 60: sub = sub - 60: #ts = #ts + 1: WEND

		' The Earth grows, and you speed up as it pulls you in
		#k = #ts + #ts / 2
		IF #k > 235 THEN #k = 235
		#alt = 240 - #k
		#vel = 6600 + #k * 120
		lm_n = earth_z(#k / 32)
		eg = eg + df
		IF ev = 8 THEN
			IF cn THEN #dl = 165 ELSE #dl = 70
			IF #k >= #dl THEN
				ev = 9: cut_on = 1: msg = 64
				#vg = 256 - cn * 96 + (RAND AND 31)
				#dl = #dl + 70
			END IF
		ELSEIF ev = 9 THEN
			IF auto THEN
				IF #vg > 3 THEN tq = 1 ELSE tq = 0
			ELSE
				tq = b
			END IF
			IF tq THEN
				#vg = #vg - (3 + cn) * df
				msg = 65
				IF #vg < -120 THEN #err = 0 - #vg: fr = 3: RETURN
			ELSEIF msg = 65 THEN
				IF #vg < -56 THEN #err = 0 - #vg: fr = 3: RETURN
				IF #vg > 64 THEN
					msg = 64
				ELSE
					#err = 0 - #vg: cut_on = 0: cn = cn + 1
					IF cn >= 2 THEN ev = 10: msg = 66 ELSE ev = 8: msg = 63
				END IF
			END IF
			IF ev = 9 AND #k >= #dl THEN fr = 5: RETURN
		ELSE
			ct = ct + df
			IF ct >= 150 THEN RETURN
		END IF
		' The little burn swells and fades (see fly_land)
		IF tq THEN
			IF ev_v < 9 THEN ev_v = ev_v + 1
		ELSEIF ev_v > 0 AND eg >= 6 THEN
			eg = 0: ev_v = ev_v - 1
		END IF

		gs = cn + tq
		GOSUB wander
		GOSUB attitude
		#k = (#my + 16) / 2 + 3
		IF #k < 0 THEN #k = 0
		IF #k > 22 THEN #k = 22
		bl_n = #k

		' Off course 2.5 s = lost
		#tot = #tot + 1
		IF ABS(#mx) <= 3 AND ABS(#my) <= 3 THEN #ontgt = #ontgt + 1
		IF offs THEN
			ofs = ofs + 1
			IF ofs > 150 THEN fr = 4: RETURN
			IF msg = 63 THEN msg = 11
		ELSE
			ofs = 0
			IF msg = 11 THEN msg = 63
		END IF

		amp = tq
		GOSUB eng_snd
		IF msg = 64 OR msg = 11 THEN
			IF FRAME AND 16 THEN SOUND 1, 180, 9 ELSE SOUND 1, 140, 9
		ELSE
			SOUND 1, 1, 0
		END IF

		GOSUB draw_moon
		FOR i = 0 TO 5: #BACKTAB(home_s(i)) = 14 * 8 + FG_WHITE: NEXT i
		GOSUB place_moon
		GOSUB show_msg
		IF cut_on THEN GOSUB cut_gauge
		GOSUB panel_step

		' One GRAM change a frame: the Earth's next size (and the ship moves
		' on the trip strip), otherwise the dials
		IF lm_n <> lm_s THEN
			lm_s = lm_n
			n = lm_n
			IF n > 2 THEN n = n - 3
			DEFINE 0, 8, VARPTR earth_g(n * 32)
			i = 16 - lm_n * 3
			#BACKTAB(220 + i) = GR + C_SHL * 8 + FG_YELLOW
			FOR j = 1 TO 3: #BACKTAB(220 + i + j) = GR + C_LINE * 8 + FG_YELLOW: NEXT j
		ELSE
			GOSUB gram_tick
		END IF
	WEND
	END

	REM ===================== TEXT TABLES ======================
	' Fixed text, 20 characters a line: much smaller than PRINT statements.
	SEGMENT 5

lights: PROCEDURE
	blk = FRAME AND 8
	IF eng_l = 1 OR (eng_l = 2 AND blk) THEN #c = FG_BLACK + BG_RED ELSE #c = PNL
	PRINT AT 155 COLOR #c, "STAGE"
	IF les_l = 1 OR (les_l = 2 AND blk) THEN #c = FG_BLACK + BG_YELLOW ELSE #c = PNL
	PRINT AT 175 COLOR #c, "TOWER"
	IF mq_l THEN #c = FG_BLACK + BG_YELLOW ELSE #c = PNL
	PRINT AT 195 COLOR #c, "ROUGH"
	IF orb_l THEN #c = FG_BLACK + BG_GREEN ELSE #c = PNL
	PRINT AT 215 COLOR #c, "ORBIT"
	' Master alarm lamp on the strut blinks while you're needed
	#c = BG_BLACK
	IF msg = 4 OR msg = 6 OR msg = 10 OR msg = 11 OR msg = 13 OR msg = 21 OR msg = 24 OR msg = 30 OR (msg >= 67 AND msg <= 71) THEN IF blk THEN #c = BG_RED
	#BACKTAB(49) = GR + C_LAMP * 8 + #c
	#BACKTAB(50) = GR + C_LAMP * 8 + #c
	END

	' Engine-stop gauge on the computer's bottom line: the needle (sprite 6)
	' reaches pixel 48 at orbit speed. Green band (cards 5-6) is +64..-56
	' ft/s around it.
cut_gauge: PROCEDURE
	#k = #vg: GOSUB px8
	#k = 48 - #d
	IF #k < 0 THEN #k = 0
	IF #k > 63 THEN #k = 63
	nx = #k
	IF stg = 6 THEN j = 212 ELSE j = 207
	n = 0
	IF stg = 8 THEN n = 8
	FOR i = 0 TO 7: #BACKTAB(j + i) = zone_bg(i + n): NEXT i
	END

	' #d = #k / 8 rounded toward zero (signed)
px8: PROCEDURE
	IF #k >= 0 THEN #d = #k / 8 ELSE #d = 0 - ((0 - #k) / 8)
	END

	' Draw 20 characters from address #d at BACKTAB #p in colour #c
text20: PROCEDURE
	FOR j = 0 TO 19: #BACKTAB(#p + j) = PEEK(#d + j) * 8 + #c: NEXT j
	END

brief_pg:	DATA 0, 0, 2, 3, 4, 5, 6, 7, 8	' page for each stage

	' Title screen: rows, colours, text
ti_row:	DATA 0, 20, 60, 80, 120, 140, 160, 180, 200
ti_col:	DATA FG_TAN, FG_YELLOW, FG_WHITE, FG_WHITE, FG_GREEN, FG_GREEN, FG_GREEN, FG_TAN, FG_TAN
text_ti:
	DATA " KEYPAD 1-8 = STAGE "
	DATA "    A P O L L O     "
	DATA "  FLY TO THE MOON   "
	DATA "  AND BACK          "
	DATA " DISC    STEER      "
	DATA " BUTTON  WHEN TOLD  "
	DATA " KEYPAD  TRIP MAP   "
	DATA " PC: ARROWS + SPACE "
	DATA "    M KEY = TRIP MAP"

	' Stage names on the command module's panel: stages 1-4, 7, 8
text_st:
	DATA "1/8 LIFTOFF         "
	DATA "2/8 LEAVE ORBIT     "
	DATA "3/8 DOCKING         "
	DATA "4/8 MOON BRAKE      "
	DATA "7/8 HEAD HOME       "
	DATA "8/8 RE-ENTRY        "
brief_c0:	DATA FG_YELLOW, FG_WHITE, FG_WHITE, FG_TAN, FG_TAN, FG_TAN, FG_GREEN, FG_GREEN, FG_WHITE, FG_WHITE, FG_WHITE
brief_c1:	DATA FG_YELLOW, FG_WHITE, FG_WHITE, FG_WHITE, FG_GREEN, FG_GREEN, FG_YELLOW, FG_RED, FG_TAN, FG_BLUE, FG_WHITE

	' Results: two lines per failure code, two per stage won, three ratings
text_res:
	DATA " STAGE 1 NOT DROPPED"
	DATA "EMPTY STAGES MUST GO"
	DATA " STAGE 2 NOT DROPPED"
	DATA "EMPTY STAGES MUST GO"
	DATA " MISSED ENGINE STOP "
	DATA " STOP IN GREEN ZONE "
	DATA " LOST COURSE        "
	DATA " KEEP <> ON CROSS   "
	DATA " MISSED THE BURN    "
	DATA " LIGHT IT WHEN TOLD "
	DATA " TOO MANY BUMPS     "
	DATA " COME IN SLOWER     "
	DATA " DRIFTED AWAY       "
	DATA " TAP TO MOVE IN     "
	DATA " FLEW PAST THE MOON "
	DATA " STOP IN GREEN ZONE "
	DATA "                    "
	DATA "                    "
	DATA " HIT THE MOON       "
	DATA " STOP IN GREEN ZONE "
	DATA " DID NOT TURN AROUND"
	DATA " PRESS WHEN TOLD    "
	DATA "  HIT TOO HARD      "
	DATA " HOLD BUTTON TO SLOW"
	DATA "  LANDED ON ROCKS   "
	DATA "  STAY OVER THE X   "
	DATA "  OUT OF FUEL       "
	DATA "  LAND SOONER       "
	DATA "  MISSED RENDEZVOUS "
	DATA " LIFT OFF WHEN TOLD "
	DATA " ENGINES NOT DROPPED"
	DATA "PRESS BUTTON IN TIME"
	DATA "  BURNED UP         "
	DATA " CAME IN TOO STEEP  "
	DATA " SKIPPED OFF THE AIR"
	DATA " CAME IN TOO FLAT   "
	DATA "  NO CHUTES OPENED  "
	DATA " PRESS WHEN TOLD    "
	DATA "   ORBIT REACHED!   "
	DATA "   117 MILES UP     "
	DATA " LEFT EARTH ORBIT!  "
	DATA " 3 DAYS TO THE MOON "
	DATA "LUNAR MODULE DOCKED!"
	DATA "                    "
	DATA "   IN MOON ORBIT!   "
	DATA "  70 MILES ABOVE    "
	DATA "    ON THE MOON!    "
	DATA "                    "
	DATA "MET COMMAND MODULE! "
	DATA "                    "
	DATA "  HEADED FOR HOME!  "
	DATA " RE-ENTRY IS NEXT   "
	DATA "    SPLASHDOWN!     "
	DATA "  MISSION COMPLETE  "
	DATA "   RATING: ACE      "
	DATA "   RATING: GOOD     "
	DATA "   RATING: MADE IT  "

	SEGMENT 1
	' Prompt bar, by msg number
text_msg:
	DATA "                    "
	DATA "KEEP <> ON THE CROSS"
	DATA "BUMPY AIR: HOLD AIM "
	DATA "STAGE 1 FUEL LOW    "
	DATA "BUTTON: DROP STAGE! "
	DATA "NEXT STAGE FIRING   "
	DATA "BUTTON: DROP TOWER! "
	DATA "ESCAPE TOWER GONE   "
	DATA "STAGE 2: KEEP AIM   "
	DATA "STAGE 3: TO ORBIT   "
	DATA "STOP ENGINE IN GREEN"
	DATA "OFF COURSE! STEER   "
	DATA "TOWER LATE: -10 PTS "
	DATA "BUTTON: LIGHT ENGINE"
	DATA "ENGINES STARTING    "
	DATA "LIFTOFF!            "
	DATA "TOO LATE: TRY AGAIN "
	DATA "KEYPAD = TRIP MAP   "
	DATA "POINT <> ON CROSS   "
	DATA "HOLD AIM: WAIT      "
	DATA "SPEEDING UP: AIM!   "
	DATA "BUTTON: SEPARATE!   "
	DATA "SEPARATED: TURNING  "
	DATA "TAP BUTTON: MOVE IN "
	DATA "TOO FAST! B = BRAKE "
	DATA "GOOD SPEED: AIM <>  "
	DATA "DOCKED! LM HELD     "
	DATA "BUMP! COME IN SLOWER"
	DATA "MISSED! LINE UP <>  "
	DATA "PULLING THE LM FREE "
	DATA "BUTTON: TURN AROUND "
	DATA "TURNING ENGINE FIRST"
	DATA "MOON AHEAD: AIM <>  "
	DATA "LOSING EARTH & RADIO"
	DATA "RADIO LOST: ALONE   "
	DATA "BRAKING: HOLD AIM!  "
	DATA "EARTHRISE!          "
	DATA "IN ORBIT! 70 MILES  "
	DATA "ALARM! BUTTON: CLEAR"
	DATA "FALLING: HOLD BUTTON"
	DATA "BOULDERS! STEER TO X"
	DATA "LOW FUEL: LAND NOW! "
	DATA "                    "
	DATA "TIPPING OVER: GROUND"
	DATA "KEEP X ON THE CROSS "
	DATA "YOU FLY: HOLD = SLOW"
	DATA "EASE IT DOWN ON X   "
	DATA "DUST! STAY ON THE X "
	DATA "CONTACT! TOUCHING   "
	DATA "THE EAGLE HAS LANDED"
	DATA "5/8 LANDING         "
	DATA "6/8 LIFT OFF        "
	DATA "COMMAND MODULE IN   "
	DATA "CLIMBING: HOLD AIM! "
	DATA "ENGINE OFF: COASTING"
	DATA "COMMAND MODULE AHEAD"
	DATA "DOCKED! ALL TOGETHER"
	DATA "LM LEFT BEHIND      "
	DATA "    PRESS BUTTON    "
	DATA "     WELCOME TO     "
	DATA "  TRANQUILITY BASE  "
	DATA "                    "
	DATA "EARTH FILLS THE VIEW"
	DATA "EARTH AHEAD: AIM <> "
	DATA "DRIFT! HOLD BUTTON  "
	DATA "LET GO IN THE GREEN "
	DATA "LINED UP WITH EARTH!"
	DATA "BUTTON: DROP ENGINES"
	DATA "BUTTON: SMALL CHUTES"
	DATA "BUTTON: BIG CHUTES  "
	DATA "TOO STEEP! DISC UP  "
	DATA "TOO FLAT! DISC DOWN "
	DATA "TURNING SHIELD FIRST"
	DATA "NEEDLE IN THE GREEN!"
	DATA "RADIO BACK: HOUSTON!"
	DATA "3 BIG CHUTES OPEN!  "
	DATA "    SPLASHDOWN!     "
	DATA "    WELCOME HOME    "
	DATA "SMALL CHUTES OPEN   "

	SEGMENT 3
	' Briefing pages, 11 lines each
text_page:
	DATA "    STAGE 1 OF 8    "
	DATA "      LIFTOFF       "
	DATA "                    "
	DATA "RIDE THE ROCKET INTO"
	DATA "ORBIT AROUND EARTH. "
	DATA "                    "
	DATA "DISC: KEEP THE GREEN"
	DATA "<> ON THE CROSSHAIR."
	DATA "                    "
	DATA "BUTTON: WHEN THE BAR"
	DATA "SAYS BUTTON.        "
	DATA "    YOUR COCKPIT    "
	DATA "                    "
	DATA "BALL  NOSE UP/DOWN  "
	DATA "DIAL  G = SEAT PUSH "
	DATA "GREEN HEIGHT, SPEED "
	DATA "      AND CLOCK     "
	DATA "LIGHT DO IT NOW     "
	DATA "RED   ALARM LAMP    "
	DATA "4X    CLOCK SPED UP "
	DATA "LINE  YOUR TRIP     "
	DATA "KEYPAD  TRIP MAP    "
	DATA "    STAGE 2 OF 8    "
	DATA " LEAVE EARTH ORBIT  "
	DATA "                    "
	DATA "FIRE THE ENGINE TO  "
	DATA "BREAK OUT OF ORBIT  "
	DATA "TOWARD THE MOON.    "
	DATA "DISC: KEEP <> ON THE"
	DATA "CROSSHAIR.          "
	DATA "BUTTON: LIGHT THE   "
	DATA "ENGINE, THEN STOP IT"
	DATA "IN THE GREEN.       "
	DATA "    STAGE 3 OF 8    "
	DATA "  DOCK WITH THE LM  "
	DATA "                    "
	DATA "LUNAR MODULE (LM) IS"
	DATA "ON THE ROCKET. TURN "
	DATA "AND GET IT NOSE-ON. "
	DATA "DISC: KEEP <> ON THE"
	DATA "CROSSHAIR.          "
	DATA "TOP BUTTON: SPEED UP"
	DATA "LOW BUTTON/B: BRAKE "
	DATA "TOUCH AT 1.0 OR LESS"
	DATA "    STAGE 4 OF 8    "
	DATA " BRAKE AT THE MOON  "
	DATA "                    "
	DATA "TURN ENGINE FIRST.  "
	DATA "BEHIND THE MOON YOU "
	DATA "LOSE THE RADIO.     "
	DATA "DISC: KEEP <> ON THE"
	DATA "CROSSHAIR.          "
	DATA "BUTTON: TURN, LIGHT "
	DATA "ENGINE, THEN STOP IT"
	DATA "IN THE GREEN.       "
	DATA "    STAGE 5 OF 8    "
	DATA "  LAND ON THE MOON  "
	DATA "                    "
	DATA "LUNAR MODULE COCKPIT"
	DATA "TAPE A = HEIGHT,    "
	DATA "TAPE D = FALL SPEED."
	DATA "DISC: KEEP THE X ON "
	DATA "THE CROSSHAIR.      "
	DATA "AT 400 FT YOU FLY:  "
	DATA "HOLD BUTTON TO SLOW."
	DATA "TOUCH DOWN GENTLY.  "
	DATA "    STAGE 6 OF 8    "
	DATA "LIFT OFF AND MEET UP"
	DATA "                    "
	DATA "THE COMMAND MODULE  "
	DATA "COMES OVERHEAD. GO  "
	DATA "WHEN TOLD. AIM <>.  "
	DATA "CLIMB TO ORBIT, STOP"
	DATA "THE ENGINE IN GREEN."
	DATA "LOOK UP: HOLD B TO  "
	DATA "SLOW DOWN, TAP TO   "
	DATA "MOVE IN. AIM <>.    "
	DATA "    STAGE 7 OF 8    "
	DATA "     HEAD HOME      "
	DATA "                    "
	DATA "BEHIND THE MOON, NO "
	DATA "RADIO. LIGHT ENGINE,"
	DATA "AIM <>, STOP IN THE "
	DATA "GREEN. THEN AIM AT  "
	DATA "EARTH. IF YOU DRIFT:"
	DATA "HOLD BUTTON, LET GO "
	DATA "WHEN THE NEEDLE IS  "
	DATA "IN THE GREEN.       "
	DATA "    STAGE 8 OF 8    "
	DATA "      RE-ENTRY      "
	DATA "                    "
	DATA "HIT THE AIR AT THE  "
	DATA "RIGHT ANGLE. TOO    "
	DATA "STEEP: YOU BURN UP. "
	DATA "TOO FLAT: YOU SKIP  "
	DATA "BACK INTO SPACE.    "
	DATA "DISC: KEEP NEEDLE IN"
	DATA "GREEN. THEN BUTTON  "
	DATA "WHEN THE BAR SAYS.  "

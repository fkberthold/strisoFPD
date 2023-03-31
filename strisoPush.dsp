import("stdfaust.lib");
SR = ma.SR;

maxmsp = library("maxmsp.lib");

fast = library("fast.lib");
K_f0 = fast.K_f0;
HPF = fast.HPF;
LPF = fast.LPF;
BPF = fast.BPF;
note2freq = fast.note2freq;

voicecount = 6;

halftime2fac(x) = 0.5^(1./(SR*x));
halftime2fac_fast(x) = 1-0.7*(1./(SR*x));

//smooth(c)        = *(1-c) : +~*(c);
smooth(x) = maxmsp.line(x,2);

envdecay(c) = (max:_ * c) ~ _;

dotpart(x) = x - int(x);

oscss(freq, even_harm) = even_harm*saw-(1-even_harm)*square
with {
    square = os.lf_squarewave(freq)*0.5;
    saw = os.saw2(freq);
};

note = vslider("[0]note[style:knob]",69,0,127,.01);
pres = vslider("[1]pres[style:knob]",0,0,1,0.01);
vpres = vslider("[2]vpres[style:knob]",0,-1,1,0.01);
but_x = vslider("but_x[style:knob]",0,-1,1,0.01);
but_y = vslider("but_y[style:knob]",0,-1,1,0.01);

acc_abs = vslider("v:accelerometer/acc_abs[style:knob]",1,0,4,0.01) : LPF(K_f0(40),1.31) : LPF(K_f0(40),0.54);
acc_x = vslider("v:accelerometer/acc_x[style:knob]",0,-1,1,0.01);
acc_y = vslider("v:accelerometer/acc_y[style:knob]",0,-1,1,0.01);
acc_z = vslider("v:accelerometer/acc_z[style:knob]",-1,-1,1,0.01);

rot_x = vslider("v:gyroscope/rot_x[style:knob]",0,-1,1,0.01);
rot_y = vslider("v:gyroscope/rot_y[style:knob]",0,-1,1,0.01);
rot_z = vslider("v:gyroscope/rot_z[style:knob]",0,-1,1,0.01);

posDecay = hslider("v:[0]config/posDecay[style:knob]",0.1,0,1,0.01):halftime2fac;
negDecay = hslider("v:[0]config/negDecay[style:knob]",0.2,0,1,0.01):halftime2fac;
pDecay = hslider("v:[0]config/pDecay[style:knob]",0.05,0,1,0.01):halftime2fac;
accDecay = hslider("v:[0]config/accDecay[style:knob]",0.10,0,1,0.01):halftime2fac;

wpos = hslider("v:[0]config/wpos[style:knob]",0.05,0,1,0.01);
wneg = hslider("v:[0]config/wneg[style:knob]",0.0,0,1,0.01);
wpres = hslider("v:[0]config/wpres[style:knob]",0.9,0,1,0.01);

filtQ = hslider("v:[1]config2/filtQ[style:knob]",1,0,10,0.01);
filtFF = hslider("v:[1]config2/filtFF[style:knob]",1,0,16,0.01);
bendRange = hslider("v:[1]config2/bendRange[style:knob]",0.5,0,2,0.01);
minFreq = hslider("v:[1]config2/minFreq[style:knob]",200,0,1000,1);
bodyFreq = hslider("v:[1]config2/bodyFreq[style:knob]",1000,0,2000,1);
filt2Freq = hslider("v:[1]config2/filt2Freq[style:knob]",3000,0,10000,1);
filt2Q = hslider("v:[1]config2/filt2Q[style:knob]",2,0.01,10,0.01);
filt2level = hslider("v:[1]config2/filt2Level[style:knob]",0.8,0,50,0.01);

B = hslider("v:[2]config3/brightness[style:knob]", 0.5, 0, 1, 0.01);// 0-1
t60 = hslider("v:[2]config3/decaytime_T60[style:knob]", 10, 0, 10, 0.01);  // -60db decay time (sec)
resfact = hslider("v:[2]config3/resfact[style:knob]", 0.03, 0, 1, 0.01);
ppOffset = hslider("v:[2]config3/ppOffset[style:knob]", 48, 0, 100, 0.1);
ppRange = hslider("v:[2]config3/ppRange[style:knob]", 18, 0, 36, 0.1);

bfQ1 = hslider("v:[2]config3/bfQ1[style:knob]",5,0.3,20,0.01);
bfQ2 = hslider("v:[2]config3/bfQ2[style:knob]",8,0.3,20,0.01);
bfQ3 = hslider("v:[2]config3/bfQ3[style:knob]",8,0.3,20,0.01);
bflevel = hslider("v:[2]config3/bflevel[style:knob]",6,0.1,20,0.01);


DECR = 0;
INCR = 1;
NEG = 0;
POS = 1;
LOW = 0;
MID = 1;
HIGH = 2;

base_accel = 0.000000001 * hslider("base_accel", 5, 0.01, 100, 0.01);

max_inc = 40;

xstates_fun(y) = (0.1, 0.2,
              1, 0.5, 4,
              rising_toward, rising_away,
              falling_toward, 5,
              falling_limit, 20, 20) with {
    rising_toward = 30 - (y * 20);
    rising_away = min(40, 10 + (y * 60));
    falling_toward = 0.01 + (y * 0.8);
    falling_limit = 0.1 + (y * 8);
};

xstates_fun(1.0);

velRec(lastVal, lastTime, lastVel, valIn) = newVal, newTime, newVel with {
    time = ba.time/ma.SR;
    timeDiff = time - lastTime;
    tick = timeDiff >= 0.05;
    newTime = ba.if(tick, time, lastTime);
    newVal = ba.if(tick, valIn, lastVal);
    newVel = ba.if(tick, 20 * (newVal - lastVal), lastVel);
};

velocity = (velRec~(_,_,_)) : (!, !, _);

moverec(prev_pos, prev_vel,
    low_lvl, high_lvl, low_acc, mid_acc, high_acc, rising_toward, rising_away, falling_toward, falling_away, falling_limit, mid_limit, rising_limit,
    pos_in) = (new_pos, new_vel) with {
    new_pos = max(prev_pos + prev_vel, 0);
    relative_pos = prev_pos - pos_in;
    is_positive = relative_pos > 0;
    is_rising = prev_vel > 0;
    is_escaping = ((is_positive == 0) & (prev_vel < 0)) | ((is_positive == 1) & (prev_vel > 0)); 
    cur_lvl = ba.if(abs(relative_pos) <= low_lvl, LOW, ba.if(abs(relative_pos) <= high_lvl, MID, HIGH));
    limit = (ba.if(is_rising, rising_limit, falling_limit) / ma.SR);
    direction_mod = ba.if(is_rising, ba.if(is_escaping, rising_away, rising_toward), ba.if(is_escaping, falling_away, falling_toward));
    abs_acc = base_accel * (select3(cur_lvl, low_acc, mid_acc, high_acc) * direction_mod);
    acc = ba.if(is_positive, -abs_acc, abs_acc);
    acceled_vel = (prev_vel + acc);
    limited_vel = ba.if(acceled_vel > 0, min(limit, acceled_vel), max(-limit, acceled_vel));
    new_vel = limited_vel;
};

findPos = (calcPos ~ (_,_)) : (_,!);

movement = (moverec~(_,_)) : (_, !);

easeInOutQuad(x) = ba.if(x < 0.5, 2 * x * x, 1 - ((-2 * x + 2)^2) / 2);

easeInOutSine(x) = (cos(ma.PI * x) - 1) / -2;

easeInSine(x) = 1 - cos((x * ma.PI) / 2);

id(x) = x;

voice(note,pres,vpres,but_x,but_y1) = (vol : _ * 2 : easeInSine : min(1)) * vosc
with {
    vol =  (xstates, pres) : movement : min(_, 0.99);
    freq = note2freq(note);
    //vosc = oscss(freq, even_harm);
    vosc = os.osc(freq);
    resetni = abs(note-note')<1.0;

    but_y = but_y1 : LPF(K_f0(20),0.71);
    pluck = but_y^2 : envdecay(select2(pres==0, halftime2fac_fast(0.01), 1));
    // decaytime = max(max(min(pluck * 2 - 0.4, 0.5+pluck), min(pres * 16, 0.5+pres)), 0.05) * 64 / note;
    decaytime = max(min(pres * 16, 0.5+pres*0.5), 0.05) * 64 / note;
    vpres1 = max(vpres - 0.02, 0);
    vplev = vpres1 / (0.5+vpres1);// + min(pres, 0.001);
    rotlev = min(pres * 2, max(rot_y^2+rot_z^2 - 0.005, 0));
    // level = max(vplev : envdecay(resetni*halftime2fac_fast(decaytime)), rotlev) : LPF(K_f0(100), 1);// / (0.2 + note/24);
    level = (vplev : envdecay(resetni*halftime2fac_fast(decaytime))) + 1.0 * pres^2 : LPF(K_f0(100), 1);// / (0.2 + note/24);

};

vmeter(x) = attach(x, envelop(x) : vbargraph("[2]level", 0, 1));
envelop = abs : max ~ -(20.0/SR);

process = hgroup("strisy",
        sum(n, voicecount, vgroup("v%n", (note,pres,vpres,but_x,but_y)) : voice : vgroup("v%n", vmeter)));
        

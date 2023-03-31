import("stdfaust.lib");

DECR = 0;
INCR = 1;
NEG = 0;
POS = 1;
LOW = 0;
MID = 1;
HIGH = 2;

base_accel = 0.000000001 * hslider("base_accel", 5, 0.01, 100, 0.01);

max_inc = 40;


xstates_old = xstates_fun_down(abs(y)) with {
    y = my_sus(1.5, hslider("Push", 0, -1, 1, 0.01));
};


y_in = my_sus(1.5, hslider("Push", 0, -1, 1, 0.01));
dn = y_in < 0;
y_pos = abs(y_in);
low_lvl = 0.1;
high_lvl = ba.if(dn, 0.2, 0.2 + (0.2 * y_pos));
low_acc = 1.0;
mid_acc = ba.if(dn, 0.5, 0.5 + (0.5 * y_pos));
high_acc = 4.0;
rising_toward = ba.if(dn, 20 + (10 * y_pos), 20 - (10.0 * y_pos));
rising_away = ba.if(dn, 40 - (30 * y_pos), 40 - (30.0 * y_pos));
falling_toward = ba.if(dn, 0.41 - (y_pos * 0.4), 0.41 + (9.59 * y_pos));
falling_away = ba.if(dn, 5.0, 5.0 + (5.0 * y_pos));
falling_limit = ba.if(dn, 4 - (y_pos * 3.7), 4 + (1.0 * y_pos));
mid_limit = ba.if(dn, 20.0, 20.0 - (19.0 * y_pos));
rising_limit = ba.if(dn, 20.0, 20.0 - (15.0 * y_pos));


my_sus(reset_time_sec, val_in) = (ba.time, val_in) : (my_sus_rec~(_,_)) : (!,_) with {
    reset_time = reset_time_sec * ma.SR;
    my_sus_rec(last_timeout, last_out, cur_time, val_in) = (new_timeout, val_out) with {
        val_reset = val_in;
        val_cont = last_out;
        timeout_reset = cur_time + reset_time;
        timeout_cont = last_timeout;
        sign_changed = (ma.signum(last_out) != ma.signum(val_in)) & (val_in != 0);
        bigger = abs(last_out) <= abs(val_in);
        times_up = cur_time >= last_timeout;
        val_out = ba.if(sign_changed | times_up | bigger, val_reset, val_cont);
        new_timeout = ba.if(sign_changed | times_up | bigger, timeout_reset, timeout_cont);
    };
};


velRec(lastVal, lastTime, lastVel, valIn) = newVal, newTime, newVel with {
    time = ba.time/ma.SR;
    timeDiff = time - lastTime;
    tick = timeDiff >= 0.05;
    newTime = ba.if(tick, time, lastTime);
    newVal = ba.if(tick, valIn, lastVal);
    newVel = ba.if(tick, 20 * (newVal - lastVal), lastVel);
};

velocity = (velRec~(_,_,_)) : (!, !, _);


moverec(prev_pos, prev_vel, pos_in) = (new_pos, new_vel) with {
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

       
process = (hslider("Position", 0, 0, 1, 0.001)) : movement : min(_, 0.99);

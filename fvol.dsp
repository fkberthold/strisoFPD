import("stdfaust.lib");

INIT = 0;
ATTACK = 1;
DECAY = 2;
SUSTAIN = 3;
RELEASE = 4;
QUICK_RELEASE = 5;

DECR = 0;
INCR = 1;
NEG = 0;
POS = 1;

// The time to remain in each state
ATTACK_TIME = (hslider("Attack", 0, 0.01, 1.0, 0.001)) * ma.SR;
DECAY_TIME = (hslider("Decay", 0, 0.01, 1.0, 0.001)) * ma.SR;
RELEASE_TIME = (hslider("Release", 0, 0.01, 1.0, 0.001)) * ma.SR;
QUICK_RELEASE_TIME = (hslider("Quick", 0, 0.01, 1.0, 0.001)) * ma.SR;

// How much attack goes over the target.
ATTACK_MOD = 1.2;

// When to go from Decay to Release
RELEASE_THRESHOLD = 0.0;

get_state(prev_state, time_since, pressure, amplitude) = next_state with {
    // State transitions.
    from_init = ba.if(pressure > 0, ATTACK, INIT);
    from_attack = ba.if(time_since >= ATTACK_TIME, DECAY, ATTACK);
    from_decay = ba.if((time_since >= DECAY_TIME) | (pressure > amplitude), SUSTAIN, ba.if(pressure <= RELEASE_THRESHOLD, RELEASE, DECAY));
    from_sustain = ba.if(pressure < amplitude, DECAY, ba.if(pressure > amplitude, ATTACK, SUSTAIN));
    from_release = ba.if((pressure <= 0) & (amplitude <= 0), INIT, ba.if(pressure > amplitude, QUICK_RELEASE, RELEASE));
    from_quick_release = ba.if(time_since >= QUICK_RELEASE_TIME, INIT, QUICK_RELEASE);

    next_state = ba.if(prev_state==INIT, from_init,
                 ba.if(prev_state==ATTACK, from_attack,
                 ba.if(prev_state==DECAY, from_decay,
                 ba.if(prev_state==SUSTAIN, from_sustain,
                 ba.if(prev_state==RELEASE, from_release, from_quick_release)))));
};

direction(prev_val, cur_val) = dir with {
    dir = ba.if(cur_val > prev_val, POS, ba.if(cur_val < prev_val, NEG, dir));
};

inflection(prev_dir, cur_dir) = inflect with {
    inflect = ba.if(prev_dir != cur_dir, 1, 0);
};

// The attack curve should target the amplitude of the maximum pressure + 10% since
//  the start of the attack.  It does this by tracking the time that attack started
//  and the current time, and figuring the time remaining as a new attack when the
//  height shifts, and havingn to complete the curve in that time.
attack_curve(pressure, min_pressure, max_pressure, time_since) = new_amp with {
    new_amp = min(max_pressure, min_pressure + ((max_pressure - min_pressure) * (time_since / ATTACK_TIME)));
};

decay_curve(pressure, min_pressure, max_pressure, time_since) = new_amp with {
    new_amp = max(min_pressure, min_pressure + ((max_pressure - min_pressure) * (1 - (time_since / DECAY_TIME))));
};

release_curve(pressure, min_pressure, max_pressure, time_since) = new_amp with {
    new_amp = max(0, max_pressure * (1 - (time_since / RELEASE_TIME)));
};

quick_release_curve(pressure, min_pressure, max_pressure, time_since) = new_amp with {
    new_amp = max(0, max_pressure * (1 - (time_since / QUICK_RELEASE_TIME)));
};

// For as long as the state reamains the same, read in the current value and
//  return the max and min across the lifetime of that state.
amp_range(st,pres,amp) = (st, pres, amp) : range_rec ~ (_, _, _)  with {
    range_rec(prev_state, prev_min, prev_max, cur_state, cur_pres, cur_amp) = (cur_state, new_min, new_max) with {
        attack_pres = cur_pres * ATTACK_MOD;
        new_min = ba.if(cur_state==INIT, cur_pres, ba.if(prev_state == cur_state, min(min(prev_min, cur_pres),cur_amp), min(cur_pres, cur_amp)));
        new_max = ba.if(cur_state==INIT, cur_pres, 
            ba.if(cur_state == ATTACK,
                ba.if(prev_state == cur_state, max(max(prev_max, attack_pres),cur_amp), max(attack_pres, cur_amp)),
                ba.if(prev_state == cur_state, max(max(prev_max, cur_pres),cur_amp), max(cur_pres, cur_amp))));
    };
};

// Indicates the tick when the state began.
time_changed(state) = (state, ba.time) : lock_on_state_change;

lock_on_state_change(state, val) = (state, val) : (locker~(_, _)) : (!, _) with {
    locker(prev_state, prev_val, cur_state, cur_val) = (cur_state, lock_val) with {
        lock_val = ba.if(prev_state != cur_state, cur_val, prev_val);
    };
};

get_amplitude = (get_amplitude_rec ~ (_, _)) : (!, _) with {
    get_amplitude_rec(prev_state, prev_amp, pressure, throttle) = (new_state, amplitude) with {
        pressures = amp_range(prev_state:stateout, pressure, prev_amp);
        min_pressure = pressures : (!, _, !) : hbargraph("min_bg", 0, 1);
        max_pressure = pressures : (!, !, _) : hbargraph("max_bg", 0, 1);
        start_time = time_changed(prev_state);
        time_since = (ba.time - start_time);
        full_pressure = max_pressure;

        amplitude = ba.selectn(6, prev_state, 0,
                                    attack_curve(pressure, min_pressure, full_pressure, time_since),
                                    decay_curve(pressure, min_pressure, full_pressure, time_since),
                                    pressure,
                                    release_curve(pressure, min_pressure, full_pressure, time_since),
                                    quick_release_curve(pressure, min_pressure, full_pressure, time_since));
        
        new_state = get_state(prev_state, time_since, pressure, prev_amp);
    };
};

amp_in = hslider("Amplitude", 0, 0, 1.0, 0.01);
throttle_in = hslider("Throttle", 0, 0, 1.0, 0.01);

stateout = hbargraph("state out", 0, 6);
ampout = hbargraph("amp out", 0, 1);


process = (amp_in, throttle_in) : get_amplitude : ampout : _ * os.osc(440);


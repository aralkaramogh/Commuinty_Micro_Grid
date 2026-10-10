function results = plant_fallback(p, scenario, t_end)
% PLANT_FALLBACK  Pure-MATLAB discrete plant simulation (no Simulink needed).
% Models bus capacitor dynamics, PV, storage emulator, tiered loads with inrush.
% Integration: Forward-Euler at Ts_plant. FSM called every Ts_fsm.
%
% PERFORMANCE NOTES (behaviour-identical to the earlier version, verified against
% _to_delete/plant_fallback_ref.m): all p.* constants hoisted out of the 20 us loop,
% PV model inlined, irradiance looked up once per FSM tick (profile breakpoints are
% tick-aligned), per-step FSM-driven signals filled in blocks, ADC noise vectorised.
%
% Returns: results struct with time vectors for all signals.

if nargin < 3; t_end = p.sim.T_end; end

Ts = p.ctrl.Ts_plant;  % 20 us
N  = round(t_end / Ts);
Ts_fsm  = p.ctrl.Ts_fsm;
fsm_ratio = round(Ts_fsm  / Ts);
adc_ratio = round(p.adc.Ts / Ts);

% ---- Pre-allocate output arrays ---------------------------------------
t_vec   = (0:N-1)*Ts;
Vb_vec  = zeros(1,N);
Is_vec  = zeros(1,N);
Il_vec  = zeros(1,N);
Vpv_vec = zeros(1,N);
Ppv_vec = zeros(1,N);
duty_vec= zeros(1,N);
soc_vec = zeros(1,N);
mask_vec= zeros(1,N);
state_vec= zeros(1,N);
fault_vec= zeros(1,N,'logical');

% ---- Hoisted constants -------------------------------------------------
Cbus   = p.bus.C;
V_nom  = p.V_nom;
V_oc   = p.stor.V_oc;   R_ser = p.stor.R_series;  I_inr_max = p.stor.I_inrush_max;
curt_hi = 1.08*V_nom;   curt_w = 0.05*V_nom;
T_cell = p.sim.T_cell_def;
pvVd   = p.pv.V_diode;  pvRs = p.pv.R_s;  pvRsh = p.pv.R_sh;  pvI0 = p.pv.I_0_ref;
pv_Iph_k = p.pv.I_ph_ref * (1 + p.pv.k_T_Isc/100*(T_cell-p.pv.T_ref)) / p.pv.G_ref;
pv_Vt    = p.pv.Vt_ref * (T_cell+273.15)/(p.pv.T_ref+273.15);
pv_Voc_k = p.pv.Voc * (1 + p.pv.k_T_Voc/100*(T_cell-p.pv.T_ref));
ld_R   = [p.load(1).R p.load(2).R p.load(3).R p.load(4).R];
ld_inr = [p.load(1).inrush p.load(2).inrush p.load(3).inrush p.load(4).inrush];
ld_ti  = [p.load(1).t_inrush p.load(2).t_inrush p.load(3).t_inrush p.load(4).t_inrush];
alpha  = p.filt.alpha_sens;

fault_inject = 'none';
if isfield(scenario,'fault_inject'); fault_inject = scenario.fault_inject; end
if strcmp(fault_inject,'bad_rfid_x3'); p.sim.auto_auth = false; end   % RFID required
fi_stuck  = strcmp(fault_inject,'stuck_open_SRC');
fi_short  = strcmp(fault_inject,'short_T2');
fi_frozen = strcmp(fault_inject,'frozen_Vbus');
fi_rfid   = strcmp(fault_inject,'bad_rfid_x3');

% ADC model constants
n_os   = p.sens.acs712.n_oversample;
adc_noise = p.adc.noise_lsb * p.adc.LSB;
adc_c = struct('n',n_os,'noise',adc_noise,'Vref',p.adc.V_ref,'cmax',p.adc.counts_max,'LSB',p.adc.LSB, ...
               'sens',p.sens.acs712.sensitivity,'Voff',p.sens.acs712.V_offset,'div',p.sens.acs712.div_ratio);
vdiv = p.sens.vsens.div_ratio;  igain = p.sens.acs712.gain_adc;

% ---- Initial conditions ------------------------------------------------
Vb  = 0;
log_struct = struct('time',{},'from',{},'to',{},'reason',{});
fsm_s = init_fsm_state_local(p);
fsm_s.n_shed_events = 0;
duty_sw = 0; pv_sw = 0; load_mask = 0;
ld_on = false(1,4); ld_tc = zeros(1,4);     % local copies for the inrush model
k_fsm = 0;
sf_Vb = 0; sf_Vpv = 0; sf_Is = 0; sf_Il = 0;   % IIR filter states
G = 0; Iph = 0; Voc_G = 0; G_lt1 = true; % updated each FSM tick
Vpv_raw = 0; Ipv_new = 0; Is_raw = 0; Il_raw = 0;
cur_state = fsm_s.state; cur_soc = fsm_s.SOC; cur_fault = fsm_s.fault_latched;
sil_log = zeros(ceil(N/fsm_ratio)+1, 11);   % per-FSM-tick record of what the FSM saw/did (for SIL)

tic;
for k = 1:N
    t = (k-1)*Ts;

    % ---- FSM tick (start of each Ts_fsm block) -------------------------
    % NOTE: original ordering ran the FSM AFTER the plant/sensor update within the
    % same step; to stay identical we run the plant first and the FSM at the end of
    % the step (see below). Irradiance, however, is looked up here per block.
    if mod(k-1, fsm_ratio) == 0
        G = get_irradiance(t, scenario);
        G_lt1 = G < 1;
        Iph   = pv_Iph_k * G;
        Voc_G = pv_Voc_k * log(G/10 + 1)/log(101);
    end

    % ---- PV --------------------------------------------------------------
    if G_lt1
        Vpv_raw = 0;
    elseif ~pv_sw
        Vpv_raw = max(0, Voc_G);
    elseif Vb > 0
        Vpv_raw = Vb + pvVd;
    else
        Vpv_raw = max(0, Voc_G);
    end
    if pv_sw
        Ipv_new = Iph - pvI0*(exp((Vpv_raw+0.1*pvRs)/pv_Vt)-1) - Vpv_raw/pvRsh;
        Ipv_new = max(0, min(Iph, Ipv_new));
        % PV curtailment (models the PV-side OVP/shunt clamp the hardware needs):
        % full current below 1.03*Vnom, ramps to zero by 1.08*Vnom.
        Ipv_new = Ipv_new * min(1, max(0, (curt_hi - Vb) / curt_w));
    else
        Ipv_new = 0;
    end

    % ---- Storage emulator: Thevenin --------------------------------------
    duty_eff = duty_sw;
    if fi_stuck && t > 15; duty_eff = 0; end   % SRC_SW welds open
    Is_raw = duty_eff * (V_oc - Vb) / R_ser;
    Is_raw = min(I_inr_max, max(0, Is_raw));

    % ---- Load currents (with inrush model) -------------------------------
    Il_raw = 0;
    for i = 1:4
        if ld_on(i)
            if (t - ld_tc(i)) < ld_ti(i); R_eff = ld_R(i)/ld_inr(i); else; R_eff = ld_R(i); end
            R_eff = max(R_eff, 0.1);
            if i == 2 && fi_short && t > 12; R_eff = 0.5; end   % T2 short
            Il_raw = Il_raw + Vb / R_eff;
        end
    end

    % ---- Bus capacitor ---------------------------------------------------
    Vb = max(0, Vb + ((Is_raw + Ipv_new - Il_raw) / Cbus) * Ts);

    % ---- Sensor simulation with noise (at ADC sample rate) ---------------
    if mod(k, adc_ratio) == 0
        Vb_meas  = adc_sample(Vb,      vdiv,  adc_c, true);
        Vpv_meas = adc_sample(Vpv_raw, vdiv,  adc_c, true);
        Is_meas  = adc_sample(Is_raw,  igain, adc_c, false);
        Il_meas  = adc_sample(Il_raw,  igain, adc_c, false);
        if ~(fi_frozen && t > 10)   % frozen ADC: no update
            sf_Vb = sf_Vb + alpha * (Vb_meas - sf_Vb);
        end
        sf_Vpv = sf_Vpv + alpha * (Vpv_meas - sf_Vpv);
        sf_Is  = sf_Is  + alpha * (Is_meas  - sf_Is);
        sf_Il  = sf_Il  + alpha * (Il_meas  - sf_Il);
    end

    % ---- Store per-step plant signals ------------------------------------
    Vb_vec(k)  = Vb;     Is_vec(k)  = Is_raw;  Il_vec(k) = Il_raw;
    Vpv_vec(k) = Vpv_raw; Ppv_vec(k) = Vpv_raw * Ipv_new;

    % ---- FSM tick (Ts_fsm) -----------------------------------------------
    if mod(k-1, fsm_ratio) == 0
        k_fsm = k_fsm + 1;
        if fi_rfid
            fsm_s.rfid_event = 0;
            if any(abs(t - [2.0 2.5 3.0]) < Ts_fsm/2); fsm_s.rfid_event = -1; end
        end
        rfid_in = fsm_s.rfid_event;   % event presented to the FSM this tick (for SIL replay)
        s_in = struct('V_bus', sf_Vb, 'V_pv', sf_Vpv, 'I_src', sf_Is, 'I_load', sf_Il);
        [fsm_s, gates, log_struct] = blackstart_fsm(t, s_in, fsm_s, log_struct, p);
        duty_sw   = gates.src_duty;
        sil_log(k_fsm,:) = [t, s_in.V_bus, s_in.V_pv, s_in.I_src, s_in.I_load, ...
                            fsm_s.state, gates.load_mask, gates.src_duty, fsm_s.SOC, ...
                            rfid_in, double(p.sim.auto_auth)];
        pv_sw     = gates.pv_sw;
        old_mask  = load_mask;
        load_mask = gates.load_mask;
        for i = 1:4
            was_on = bitand(old_mask, bitshift(1,i-1)) > 0;
            now_on = bitand(load_mask, bitshift(1,i-1)) > 0;
            if now_on && ~was_on
                fsm_s.load_connect_time(i) = t;
                ld_tc(i) = t;
            end
            ld_on(i) = now_on;
        end
        cur_state = fsm_s.state; cur_soc = fsm_s.SOC; cur_fault = fsm_s.fault_latched;
        % FSM-driven signals are constant until the next tick: fill whole block
        % (the original wrote post-tick values at every step k >= tick step)
        kb = k:min(k+fsm_ratio-1, N);
        duty_vec(kb) = duty_sw; mask_vec(kb) = load_mask;
        soc_vec(kb) = cur_soc;  state_vec(kb) = cur_state; fault_vec(kb) = cur_fault;
    end
end
elapsed = toc;
fprintf('[plant_fallback] Done: %.1fs sim in %.1fs wall-clock\n', t_end, elapsed);

results.sil     = sil_log(1:k_fsm,:);
results.t       = t_vec;
results.Vb      = Vb_vec;
results.Is      = Is_vec;
results.Il      = Il_vec;
results.Vpv     = Vpv_vec;
results.Ppv     = Ppv_vec;
results.duty    = duty_vec;
results.SOC     = soc_vec;
results.mask    = mask_vec;
results.state   = state_vec;
results.fault   = fault_vec;
results.event_log = log_struct;
results.n_shed  = fsm_s.n_shed_events;
results.tier_locked = fsm_s.tier_locked;
results.wall_s  = elapsed;
results.scenario= scenario;
results.p       = p;
end

function G = get_irradiance(t, scenario)
if ~isfield(scenario,'G_profile') || isempty(scenario.G_profile)
    G = scenario.G_const;
    return;
end
G = interp1(scenario.G_profile(:,1), scenario.G_profile(:,2), t, 'previous', scenario.G_profile(end,2));
end

function val = adc_sample(true_val, scale, c, is_voltage)
% ADC with per-sample noise + n-fold oversampling (matches ESP32 firmware).
% Vectorised: randn(n,1) consumes the RNG stream in the same order as n scalar calls.
if is_voltage
    adc_v = true_val * scale;
else
    adc_v = (true_val * c.sens + c.Voff) * c.div;
end
adc_v  = adc_v + randn(c.n,1) * c.noise;
counts = max(0, min(c.cmax, round(adc_v / c.Vref * c.cmax)));
adc_avg = sum(counts) * c.LSB / c.n;
if is_voltage
    val = adc_avg / scale;
else
    val = (adc_avg / c.div - c.Voff) / c.sens;
end
end

function s = init_fsm_state_local(p)
s.state=0; s.src_duty=0; s.pv_sw=0; s.load_mask=0; s.src_connected=false;
s.SOC=p.stor.SOC_init; s.rfid_event=0; s.bad_scan_count=0; s.lockout_remaining=0;
s.fault_latched=false; s.fault_code=''; s.retry_count=0;
s.t_blackout_timer=0; s.t_stable_timer=0; s.t_softstart_timer=0;
s.t_dwell_timer=0; s.t_fault_timer=0; s.t_last_step=-inf;
s.I_src_offset=0; s.I_load_offset=0; s.mppt_I_ref=0; s.P_pv_prev=0; s.t_mppt_last=-inf;
s.restoration_complete=false; s.load_state=[false false false false];
s.t_last_shed=[-inf -inf -inf -inf]; s.I2t_accum=0; s.t_oc_confirm=0; s.t_sw_mismatch=0; s.t_Vb_still=0; s.Vb_last=-1;
s.tier_strikes=zeros(1,4); s.tier_locked=false(1,4); s.last_conn_idx=0; s.t_conn=-inf(1,4); s.t_blame=-inf;
s.load_connect_time=[0 0 0 0]; s.n_shed_events=0;
s.event_log=struct('time',{},'from',{},'to',{},'reason',{});
end

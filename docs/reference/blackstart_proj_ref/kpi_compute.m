function kpi = kpi_compute(results, scenario, p)
% KPI_COMPUTE  Extracts key performance indicators from a simulation results struct.
% Produces a single struct 'kpi' and prints a summary.

t  = results.t;
Vb = results.Vb;
Is = results.Is;
Il = results.Il;
Vpv= results.Vpv;
Ppv= results.Ppv;
SOC= results.SOC;
st = results.state;
mask = results.mask;
fault = results.fault;

dt = mean(diff(t));
V_nom = p.V_nom;

% Time to bus energised (V_bus first crosses 90% nominal)
idx_bus_up = find(Vb >= 0.90*V_nom, 1, 'first');
if isempty(idx_bus_up); kpi.t_bus_up = inf; else; kpi.t_bus_up = t(idx_bus_up) - t(1); end

% Time to restore each tier
for tier = 1:4
    bit = bitshift(1, tier-1);
    idx_tier = find(bitand(mask, bit) > 0, 1, 'first');
    if ~isempty(idx_tier)
        kpi.t_tier_restored(tier) = t(idx_tier) - t(1);
    else
        kpi.t_tier_restored(tier) = inf;
    end
end

% Peak inrush current
kpi.I_peak_inrush = max(Is);

% Max voltage dip from nominal (when bus is up)
idx_stable = t > kpi.t_bus_up + 2;   % empty if bus never came up
if any(idx_stable)
    kpi.V_dip_max_pct = (V_nom - min(Vb(idx_stable))) / V_nom * 100;
    kpi.V_ripple_pct  = (max(Vb(idx_stable)) - min(Vb(idx_stable))) / V_nom / 2 * 100;
else
    kpi.V_dip_max_pct = NaN;
    kpi.V_ripple_pct  = NaN;
end

% Energy served [Wh]
kpi.E_served_Wh = sum(Vb .* Il) * dt / 3600;
% PV utilisation
kpi.E_pv_Wh     = sum(Ppv) * dt / 3600;
kpi.PV_util_pct = kpi.E_pv_Wh / max(eps, p.pv.Pmax * (t(end)-t(1))/3600) * 100;

% SOC used
kpi.SOC_used = SOC(1) - SOC(end);

% Shed events and retries
kpi.n_shed   = results.n_shed;
if isempty(results.event_log); kpi.n_retries = 0; kpi.final_state = st(end);
else; kpi.n_retries= sum(strcmp({results.event_log.reason},'FAULT_RETRY')); end
kpi.final_state = st(end);
kpi.final_mask  = mask(end);
if isfield(results,'tier_locked'); kpi.tier_locked = results.tier_locked; else; kpi.tier_locked = false(1,4); end
kpi.max_mask    = max(mask);
kpi.ever_energised = any(results.duty > 0);

% Fault occurred?
kpi.fault_occurred = any(fault);

% Pass criteria (scenario-specific)
kpi.pass = eval_pass(kpi, scenario, p);

fprintf('[kpi %s] bus_up=%.2fs | T1=%.2fs | Ipeak=%.3fA | Vdip=%.1f%% | shed=%d | pass=%d\n', ...
    scenario.id, kpi.t_bus_up, kpi.t_tier_restored(1), kpi.I_peak_inrush, ...
    kpi.V_dip_max_pct, kpi.n_shed, kpi.pass);
end

function ok = eval_pass(kpi, scenario, p)
ok = true;
if isfield(scenario.expected,'locked_tier')   % T7: faulty branch isolated, others kept
    ok = ok && kpi.tier_locked(scenario.expected.locked_tier) && kpi.final_mask == scenario.expected.final_mask ...
            && kpi.final_state == 7;
end
if isfield(scenario.expected,'max_tier_restored')   % T3 low SOC
    ok = ok && all(isinf(kpi.t_tier_restored(scenario.expected.max_tier_restored+1:end)));
end
if isfield(scenario.expected,'lockout_occurs') && scenario.expected.lockout_occurs  % T9
    ok = ok && kpi.final_state == 9 && ~kpi.ever_energised;
end
if isfield(scenario.expected,'detected') && scenario.expected.detected   % T6
    ok = ok && kpi.fault_occurred && kpi.final_state == 9;
end
if isfield(scenario.expected,'T1_T2_restored') && scenario.expected.T1_T2_restored  % T2
    ok = ok && all(~isinf(kpi.t_tier_restored(1:2)));
end
if isfield(scenario.expected,'bus_up_time_max')
    ok = ok && kpi.t_bus_up <= scenario.expected.bus_up_time_max;
end
if isfield(scenario.expected,'V_band_pct')
    ok = ok && kpi.V_dip_max_pct <= scenario.expected.V_band_pct * 2; % allow 2x in dip
end
if isfield(scenario.expected,'inrush_max')
    ok = ok && kpi.I_peak_inrush <= scenario.expected.inrush_max * 1.1;
end
if isfield(scenario.expected,'no_false_trip') && scenario.expected.no_false_trip
    ok = ok && ~kpi.fault_occurred;
end
if isfield(scenario.expected,'safe_lockout') && scenario.expected.safe_lockout
    ok = ok && kpi.fault_occurred && kpi.final_state == 9; % must end in alarm lockout
end
end

function mc_results = montecarlo(p, N_runs, use_parallel)
% MONTECARLO  Monte Carlo simulation: N_runs with randomised parameters.
% Varies: load R �20%, PV irradiance �15%, bus C �10%, ADC gain �3%, SOC_init
% Reports: pass rate, KPI distributions.

if nargin < 2; N_runs = p.mc.N_runs; end
addpath(genpath(fileparts(mfilename('fullpath'))));
scenarios = define_scenarios(p);
T1 = scenarios(1); % Use T1 as baseline

results_mc = cell(N_runs,1);
pass_vec   = false(N_runs,1);
soc_vec    = zeros(N_runs,1);
gf_vec     = zeros(N_runs,1);

% Parallel mode: auto-enabled on machines with >=8 cores and a Parallel Computing
% Toolbox licence (a 30 s run is only ~2 s now, so a pool start-up is not worth it
% on a laptop). Force with montecarlo(p,N,true/false).
if nargin < 3
    use_parallel = feature('numcores') >= 8 && license('test','Distrib_Computing_Toolbox');
end

fprintf('[MC] Running %d Monte Carlo runs (%s)...\n', N_runs, ternary_str(use_parallel,'parallel','serial'));
if use_parallel
    if isempty(gcp('nocreate')); parpool('Processes'); end
    parfor ir = 1:N_runs
        [pass_vec(ir), results_mc{ir}, soc_vec(ir), gf_vec(ir)] = mc_one(p, T1, ir);
    end
else
    for ir = 1:N_runs
        [pass_vec(ir), results_mc{ir}, soc_vec(ir), gf_vec(ir)] = mc_one(p, T1, ir);
    end
end
for ir = 1:N_runs
    fprintf('[MC run %d/%d] pass=%d SOC=%.2f G_f=%.2f\n', ir, N_runs, pass_vec(ir), soc_vec(ir), gf_vec(ir));
end

pass_rate = sum(pass_vec) / N_runs;
fprintf('[MC] Pass rate: %.1f%% (required >=%.0f%%)\n', pass_rate*100, p.mc.pass_rate_req*100);
mc_results.pass_rate = pass_rate;
mc_results.pass_vec  = pass_vec;
mc_results.N_runs    = N_runs;
mc_results.kpi_all   = results_mc;
mc_results.req_met   = pass_rate >= p.mc.pass_rate_req;

% Save table
tbl = table((1:N_runs)', pass_vec, 'VariableNames',{'Run','Pass'});
writetable(tbl, fullfile('results','tables','montecarlo_results.csv'));
fprintf('[MC] Results saved to results/tables/montecarlo_results.csv\n');
end

% =========================================================================
function [ok, kpi_i, soc0, G_factor] = mc_one(p, T1, run)
% One Monte Carlo realisation (self-contained so it can run inside parfor).
rng(run); % reproducible
p_mc = p;
for i = 1:4
    p_mc.load(i).R = p.load(i).R * (1 + p.mc.load_var*(2*rand-1));
    p_mc.load(i).P_nom = p_mc.V_nom^2 / p_mc.load(i).R;
end
G_factor  = 1 + p.mc.pv_var*(2*rand-1);
p_mc.pv.Isc  = p.pv.Isc  * G_factor;
p_mc.pv.Pmax = p.pv.Pmax * G_factor;
p_mc.bus.C   = p.bus.C   * (1 + p.mc.RC_var*(2*rand-1));
p_mc.adc.LSB = p.adc.LSB * (1 + p.mc.adc_gain_var*(2*rand-1));
p_mc.stor.SOC_init = p.mc.SOC_range(1) + rand*(p.mc.SOC_range(2)-p.mc.SOC_range(1));
soc0 = p_mc.stor.SOC_init;
sc = T1;
sc.SOC_init = soc0;
sc.G_const  = 800 * G_factor;
try
    res_i = plant_fallback(p_mc, sc, 30);
    kpi_i = kpi_compute(res_i, sc, p_mc);
    ok = kpi_i.pass && ~res_i.fault(end);
catch ME
    fprintf('[MC run %d] ERROR: %s\n', run, ME.message);
    ok = false;
    kpi_i = struct('t_bus_up',inf,'V_dip_max_pct',100,'I_peak_inrush',inf,'n_shed',0,'pass',false);
end
end

function s = ternary_str(c,a,b); if c; s=a; else; s=b; end; end

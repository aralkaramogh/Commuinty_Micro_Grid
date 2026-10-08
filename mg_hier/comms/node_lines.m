function out = node_lines(op, varargin)
% NODE_LINES  Text lines between MATLAB and the node ESP32s (see docs/node_protocol.md).
%   s = node_lines('enc_L', seq, cmd, meter)   MATLAB -> load node
%   x = node_lines('dec_L', s)                  (parsed as the node sees it)
%   s = node_lines('enc_l', seq, r)             load node -> MATLAB (reply)
%   r = node_lines('dec_l', s)
%   'enc_B' / 'dec_B' / 'enc_b' / 'dec_b'       same for the solar+BESS node
%   s = node_lines('enc_P', seq, m) / 'dec_P'   PCC meter frame (main controller input)
% Number formats fix the rounding, so MATLAB and the C++ firmware see identical values.
switch op
    case 'enc_L'
        [seq, c, m] = varargin{:};
        out = sprintf('L,%d,%d,%d,%d,%.3f,%.4f,%.2f,%.2f,%.2f,%.2f,%d', seq, c.valid, c.enable, ...
            c.flex_allow, m.v, m.i, m.p_load, m.q_load, m.p_pv, m.q_pv, m.card_uid);
    case 'dec_L'
        v = parse(varargin{1}, 'L', 11);
        out = cell2struct(num2cell(v), {'seq','valid','enable','flex_allow','v','i','p_load', ...
                                        'q_load','p_pv','q_pv','card_uid'}, 2);
    case 'enc_l'
        [seq, r] = varargin{:};
        out = sprintf('l,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.3f,%.4f,%.2f,%.2f,%.2f,%.2f,%d', seq, r.tie, ...
            r.flex, r.hstate, r.strikes, r.comm_lost, r.e_imp, r.e_exp, r.v, r.i, r.p_load, r.q_load, ...
            r.p_pv, r.q_pv, r.card_uid);
    case 'dec_l'
        v = parse(varargin{1}, 'l', 15);
        out = cell2struct(num2cell(v), {'seq','tie','flex','hstate','strikes','comm_lost','e_imp', ...
                                        'e_exp','v','i','p_load','q_load','p_pv','q_pv','card_uid'}, 2);
    case 'enc_B'
        [seq, c, m] = varargin{:};
        out = sprintf('B,%d,%d,%.1f,%.1f,%d,%.6f,%.2f,%.2f,%d,%.3f,%.4f,%.2f', seq, c.valid, c.p_set, ...
            c.q_set, c.sync, m.soc, m.p_bess, m.q_bess, m.bess_status, m.v_c, m.f_mg, m.p_cpv);
    case 'dec_B'
        v = parse(varargin{1}, 'B', 12);
        out = cell2struct(num2cell(v), {'seq','valid','p_set','q_set','sync','soc','p_bess', ...
                                        'q_bess','bess_status','v_c','f_mg','p_cpv'}, 2);
    case 'enc_b'
        [seq, r] = varargin{:};
        out = sprintf('b,%d,%.1f,%.1f,%d,%d,%d,%.6f,%.2f,%.2f,%d,%.3f,%.4f,%.2f', seq, r.p, r.q, ...
            r.sync, r.clamped, r.comm_lost, r.soc, r.p_bess, r.q_bess, r.bess_status, r.v_c, r.f_mg, r.p_cpv);
    case 'dec_b'
        v = parse(varargin{1}, 'b', 13);
        out = cell2struct(num2cell(v), {'seq','p','q','sync','clamped','comm_lost','soc','p_bess', ...
                                        'q_bess','bess_status','v_c','f_mg','p_cpv'}, 2);
    case 'enc_P'
        [seq, m] = varargin{:};
        out = sprintf('P,%d,%.3f,%.4f,%.3f,%.4f,%.3f,%.2f,%.2f', seq, m.v_grid, m.f_grid, m.v_c, ...
            m.f_mg, m.dtheta, m.p_pcc, m.q_pcc);
    case 'dec_P'
        v = parse(varargin{1}, 'P', 8);
        out = cell2struct(num2cell(v), {'seq','v_grid','f_grid','v_c','f_mg','dtheta','p_pcc','q_pcc'}, 2);
    otherwise
        error('node_lines: unknown op %s', op);
end
end

function v = parse(s, tag, nf)
s = char(s);
assert(numel(s) > 2 && s(1) == tag && s(2) == ',', 'expected a "%s" line, got: %s', tag, s);
v = sscanf(s(3:end), '%f,').';
assert(numel(v) == nf, '"%s" line: expected %d fields, got %d', tag, nf, numel(v));
end

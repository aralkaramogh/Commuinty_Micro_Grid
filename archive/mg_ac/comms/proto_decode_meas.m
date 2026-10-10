function m = proto_decode_meas(s, n)
% PROTO_DECODE_MEAS  Parse an M line (exactly what the ESP32 sees).
v = sscanf(s(3:end), '%f,');
assert(numel(v) == 23 + 6*n, 'M frame: expected %d fields, got %d', 23 + 6*n, numel(v));
f = {'seq','t_ms','v_grid','f_grid','v_c','f_mg','dtheta','p_pcc','q_pcc','p_bess','q_bess', ...
     'soc','bess_status','p_cl','q_cl','p_cpv','fb','card_house','card_uid', ...
     'ai_valid','ai_p','ai_mask','ai_price'};
for i = 1:numel(f), m.(f{i}) = v(i); end
r = reshape(v(24:end), 6, n);
m.v_h = r(1,:); m.i_h = r(2,:); m.p_load = r(3,:); m.q_load = r(4,:); m.p_pv = r(5,:); m.q_pv = r(6,:);
end

function [cmd, o] = proto_decode_cmd(s, n)
% PROTO_DECODE_CMD  Parse a C line into plant commands and controller outputs.
v = sscanf(s(3:end), '%f,');
assert(numel(v) == 8 + 2*n, 'C frame: expected %d fields, got %d', 8 + 2*n, numel(v));
o.seq = v(1); o.bits = v(2); o.mode = v(3); o.p_set = v(4); o.q_set = v(5);
o.flags = v(6); o.ai_status = v(7); o.price = v(8);
o.bal = v(9:2:end).'; o.hcode = v(10:2:end).';
b = o.bits;
cmd.bits = b;
cmd.breaker = double(bitand(b, 1) > 0);
cmd.sync    = double(bitand(b, 2) > 0);
cmd.tie = zeros(1,n); cmd.flex = zeros(1,n);
for k = 1:n
    cmd.tie(k)  = double(bitand(b, 2^(2 + 2*(k-1))) > 0);
    cmd.flex(k) = double(bitand(b, 2^(3 + 2*(k-1))) > 0);
end
cmd.p_set = o.p_set; cmd.q_set = o.q_set;
end

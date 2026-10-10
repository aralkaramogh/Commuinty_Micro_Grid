function s = proto_encode_cmd(seq, o)
% PROTO_ENCODE_CMD  ESP32 -> MATLAB command line (MATLAB twin of the firmware printf).
s = sprintf('C,%d,%d,%d,%.1f,%.1f,%d,%d,%.3f', seq, o.bits, o.mode, o.p_set, o.q_set, ...
            o.flags, o.ai_status, o.price);
s = [s, sprintf(',%.4f,%d', [o.bal; o.hcode])];
end

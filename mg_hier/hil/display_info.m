function v = display_info(op, mode, total_w)
% DISPLAY_INFO  System-wide values only the LCD firmware needs (the nodes' control
% logic never uses them): the main controller's operating mode (last tick) and
% the total community demand. run_hier sets them each tick; node_exchange_twin
% sends them as a "D" line to boards running the LCD sketch.
persistent s
if isempty(s), s = struct('mode', 0, 'total_w', 0); end
if strcmp(op, 'set'), s.mode = mode; s.total_w = total_w; end
v = s;
end

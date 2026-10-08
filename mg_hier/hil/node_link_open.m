function link = node_link_open(port, P)
% NODE_LINK_OPEN  Open one node ESP32 on a USB serial port and reset it.
link.port = port;
link.sp = serialport(port, P.sim.baud, 'Timeout', P.sim.timeout_s);
configureTerminator(link.sp, 'LF');
pause(2.0);                                 % the ESP32 reboots when the port opens
flush(link.sp);
writeline(link.sp, 'R');
t0 = tic; ok = false;
while toc(t0) < 5
    s = strtrim(readline(link.sp));
    if strcmp(s, 'READY'), ok = true; break; end
end
assert(ok, 'node on %s did not answer READY (sketch flashed? right port?)', port);
end

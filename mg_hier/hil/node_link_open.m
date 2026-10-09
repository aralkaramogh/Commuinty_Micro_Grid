function link = node_link_open(port, P)
% NODE_LINK_OPEN  Open one node ESP32 on a USB serial port and reset it.
% Sends 'R' up to 8 times (1 s apart) and waits for READY; tolerates silence
% (readline returns [] on timeout) and boot chatter. Says which port failed.
link.port = port;
fprintf('Opening node on %s ... ', port);
link.sp = serialport(port, P.sim.baud, 'Timeout', 1);
configureTerminator(link.sp, 'LF');
pause(2.5);                                 % the ESP32 reboots when the port opens (LCD init adds time)
flush(link.sp);
ok = false; heard = strings(0);
ws = warning('off', 'all');                 % silence the readline timeout warnings while probing
for attempt = 1:8
    writeline(link.sp, 'R');
    t0 = tic;
    while toc(t0) < 1
        s = readline(link.sp);
        if isempty(s), break; end
        s = strtrim(string(s));
        if s == "READY", ok = true; break; end
        if strlength(s) > 0, heard(end+1) = s; end %#ok<AGROW>
    end
    if ok, break; end
end
warning(ws);
link.sp.Timeout = P.sim.timeout_s;
if ok, fprintf('READY\n'); return; end
delete(link.sp);
if isempty(heard), what = 'nothing'; else, what = strjoin(heard(max(1,end-2):end), ' | '); end
error('node on %s did not answer READY after 8 tries (heard: %s).\nCheck: right COM port for this role? sketch mg_node / mg_node_lcd flashed? baud %d? Arduino Serial Monitor closed?', ...
      port, what, P.sim.baud);
end

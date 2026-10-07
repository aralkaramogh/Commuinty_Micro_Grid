function link = esp32_open(port, P)
% ESP32_OPEN  Open the USB serial link to the ESP32 and reset its controller.
%   link = esp32_open("COM5", ac_params())
% Find the port with serialportlist("available") or Device Manager.
link.sp = serialport(port, P.sim.baud, 'Timeout', P.sim.timeout_s);
configureTerminator(link.sp, 'LF');
pause(2.0);                       % ESP32 reboots when the port opens
flush(link.sp);
writeline(link.sp, 'R');
t0 = tic;
while toc(t0) < 5
    s = strtrim(readline(link.sp));
    if strcmp(s, 'READY'), break; end
end
assert(strcmp(s, 'READY'), 'ESP32 did not answer READY on %s', port);
link.tfile = fopen(fullfile(fileparts(mfilename('fullpath')), '..', 'results', 'logs', ...
    sprintf('esp32_telemetry_%s_%s.jsonl', regexprep(char(port), '\W', ''), datestr(now, 'yyyymmdd_HHMMSS'))), 'w');
end

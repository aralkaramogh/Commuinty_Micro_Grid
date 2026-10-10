function Cline = esp32_exchange(link, Mline, seq)
% ESP32_EXCHANGE  Send one M frame, return the matching C frame.
% Telemetry lines ("T{...}") are saved to results/logs/*.jsonl on the way.
writeline(link.sp, Mline);
while true
    s = readline(link.sp);
    if isempty(s), error('ESP32 timeout at tick %d', seq); end
    s = strtrim(char(s));
    if startsWith(s, 'C,')
        v = sscanf(s(3:end), '%f,', 1);
        if v == seq, Cline = s; return; end
    elseif startsWith(s, 'T')
        fprintf(link.tfile, '%s\n', s(2:end));
    elseif startsWith(s, 'E,')
        error('ESP32 reported %s at tick %d', s, seq);
    end
end
end

function esp32_close(link)
% ESP32_CLOSE  Close the serial port and the telemetry log.
try, fclose(link.tfile); catch, end
clear link
end

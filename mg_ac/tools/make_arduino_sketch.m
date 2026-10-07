function make_arduino_sketch()
% MAKE_ARDUINO_SKETCH  Copy the firmware into firmware_arduino/mg_ac_controller/
% so it opens directly in the Arduino IDE (main.cpp becomes the .ino).
% run_all calls this after regenerating config.h; re-run it after any change.
root = fileparts(fileparts(mfilename('fullpath')));
dst = fullfile(root, 'firmware_arduino', 'mg_ac_controller');
if ~exist(dst, 'dir'), mkdir(dst); end
fw = fullfile(root, 'firmware');
copyfile(fullfile(fw, 'src', 'main.cpp'), fullfile(dst, 'mg_ac_controller.ino'));
for f = {'controller.cpp', 'protocol.cpp'}, copyfile(fullfile(fw, 'src', f{1}), fullfile(dst, f{1})); end
for f = {'controller.h', 'protocol.h', 'config.h'}, copyfile(fullfile(fw, 'include', f{1}), fullfile(dst, f{1})); end
end

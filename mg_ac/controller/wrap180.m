function a = wrap180(a)
% WRAP180  Wrap an angle in degrees to [-180, 180). Same formula as the firmware.
a = a - 360 * floor((a + 180) / 360);
end

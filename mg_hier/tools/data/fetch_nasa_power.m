function file = fetch_nasa_power(P)
% FETCH_NASA_POWER  Download one year of HOURLY solar + weather data for the site
% from NASA POWER (power.larc.nasa.gov, free, no account) into data/raw/nasa_power.
%   Parameters asked for (all hourly, UTC time stamps):
%     ALLSKY_SFC_SW_DWN  global horizontal irradiance, GHI   [Wh/m2 per hour = mean W/m2]
%     CLRSKY_SFC_SW_DWN  same, if the sky had been clear       [Wh/m2 per hour]
%     T2M                air temperature at 2 m                [degC]
%     WS2M               wind speed at 2 m                     [m/s]
% The raw file is never edited; tools/data/import_solar.m reads it.
if nargin < 1, P = hier_params(); end
d = fullfile(P.data.dir, 'raw', 'nasa_power'); if ~exist(d, 'dir'), mkdir(d); end
file = fullfile(d, sprintf('nasa_power_%.2fN_%.2fE_%d_UTC.csv', P.data.lat, P.data.lon, P.data.year));
url = sprintf(['https://power.larc.nasa.gov/api/temporal/hourly/point?' ...
    'parameters=ALLSKY_SFC_SW_DWN,CLRSKY_SFC_SW_DWN,T2M,WS2M&community=RE' ...
    '&longitude=%.4f&latitude=%.4f&start=%d0101&end=%d1231&format=CSV&time-standard=UTC'], ...
    P.data.lon, P.data.lat, P.data.year, P.data.year);
fprintf('Downloading NASA POWER %d for %s ...\n', P.data.year, P.data.site);
websave(file, url, weboptions('Timeout', 120));
fprintf('  saved %s (%.0f kB)\n', file, dir(file).bytes / 1e3);
end

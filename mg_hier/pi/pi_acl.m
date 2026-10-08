function R = pi_acl()
% PI_ACL  Who may read / write which MQTT topics on the Pi broker. The SAME table
% writes the real Mosquitto files (tools/make_mosquitto_files.m) and is used by
% the simulation (pi/acl_allows.m), so the tested rules are the deployed rules.
%   user '*' = pattern line (applies to every user, %u = that user's name)
R = struct('user', {}, 'access', {}, 'topic', {});
add = @(R, u, a, t) [R, struct('user', u, 'access', a, 'topic', t)];
% main controller (MATLAB): publishes everything, reads requests
R = add(R, 'mgctl', 'write', 'mg/state');
R = add(R, 'mgctl', 'write', 'mg/node/#');
R = add(R, 'mgctl', 'write', 'mg/house/#');
R = add(R, 'mgctl', 'write', 'mg/event');
R = add(R, 'mgctl', 'write', 'mg/ack/#');
R = add(R, 'mgctl', 'read',  'mg/cmd/#');
R = add(R, 'mgctl', 'read',  'mg/sim/#');      % demo bench knobs (grid plug, sun)
% main microgrid dashboard (operator): sees everything, may send operator requests
R = add(R, 'dash', 'read',  'mg/#');
R = add(R, 'dash', 'write', 'mg/cmd/op/#');
R = add(R, 'dash', 'write', 'mg/sim/#');       % demo only: 'pull the grid plug' button
% AI service: sees everything, may send advice only
R = add(R, 'ai', 'read',  'mg/#');
R = add(R, 'ai', 'write', 'mg/cmd/ai/#');
R = add(R, 'ai', 'write', 'mg/ai/#');        % its own results (forecasts, alerts, carbon) for the dashboard
% every household user (user name = house id, e.g. H1): only its own data
R = add(R, '*', 'read',  'mg/house/%u/#');
R = add(R, '*', 'read',  'mg/ack/user/%u/#');
R = add(R, '*', 'write', 'mg/cmd/user/%u/#');
end

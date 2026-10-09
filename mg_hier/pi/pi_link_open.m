function link = pi_link_open(host, user, pass, port)
% PI_LINK_OPEN  Live MQTT link from the MATLAB main controller to the Pi broker.
%   link = pi_link_open('192.168.1.50', 'mgctl', '<password>')     (port 1883)
% link.publish(topic, json)  sends one message (QoS 0)
% link.fetch()               returns the requests received since the last call
%                            (struct array: topic, data) - only mg/cmd/# is subscribed
% link.close()               disconnects
% Needs the Industrial Communication Toolbox (mqttclient).
if nargin < 4, port = 1883; end
cfg = struct('host', string(host), 'port', port, 'user', string(user), 'pass', string(pass));
[mq, why] = connect(cfg);
if isempty(mq)
    error(['Could not connect to the Pi broker at %s:%d as %s.\n  Reason: %s\n' ...
           '  Check: Pi on the SAME Wi-Fi as this laptop? IP still %s (hostname -I on the Pi)? ' ...
           'Mosquitto running (docker ps)? password for %s correct?'], host, port, user, why, host, user);
end
H = containers.Map();                     % handle: lets publish/fetch swap in a reconnected client
H('mq') = mq; H('fails') = 0; H('t_retry') = tic;
link.mq = mq;
link.publish = @(topic, json) safe_publish(H, cfg, topic, json);
link.fetch = @() fetch_all(H);
link.close = @() clear_link(H('mq'));
fprintf('Connected to the Pi broker %s:%d as %s (subscribed to mg/cmd/#)\n', host, port, user);
end

function [mq, why] = connect(cfg)
% open the client and subscribe; [] (and the reason) if the broker cannot be reached
mq = []; why = '';
try
    c = mqttclient("tcp://" + cfg.host, Port = cfg.port, Username = cfg.user, ...
                   Password = cfg.pass, ClientID = "mgctl-matlab-" + string(randi(1e6)));
    if ~c.Connected, why = 'client created but not connected'; return; end
    subscribe(c, "mg/cmd/#", QualityOfService = 0);
    subscribe(c, "mg/sim/#", QualityOfService = 0);   % demo bench knobs
    mq = c;
catch e
    why = e.message;
end
end

function safe_publish(H, cfg, topic, json)
% publish; if the broker link is down, keep the simulation running, warn, and
% try to reconnect at most every 5 s (messages during the gap are dropped)
try
    write(H('mq'), string(topic), string(json));
    if H('fails') > 0
        fprintf('MQTT: publishing again after %d failed messages\n', H('fails')); H('fails') = 0;
    end
catch e
    H('fails') = H('fails') + 1;
    if H('fails') == 1, fprintf(2, 'MQTT: publish failed (%s). Sim keeps running; reconnecting...\n', e.message); end
    if toc(H('t_retry')) > 5
        H('t_retry') = tic;
        try, delete(H('mq')); catch, end
        mq = connect(cfg);
        if ~isempty(mq), H('mq') = mq; fprintf('MQTT: reconnected to %s\n', cfg.host);
        else, fprintf(2, 'MQTT: broker %s still unreachable (%d messages dropped)\n', cfg.host, H('fails')); end
    end
end
end

function rx = fetch_all(H)
rx = struct('topic', {}, 'data', {});
try, tt = read(H('mq')); catch, return; end     % link down: no requests this tick
for k = 1:height(tt)
    rx(end+1) = struct('topic', char(tt.Topic(k)), 'data', char(tt.Data(k))); %#ok<AGROW>
end
end

function clear_link(mq)
try, unsubscribe(mq); catch, end
delete(mq);
end

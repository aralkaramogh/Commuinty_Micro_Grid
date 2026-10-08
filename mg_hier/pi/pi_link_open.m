function link = pi_link_open(host, user, pass, port)
% PI_LINK_OPEN  Live MQTT link from the MATLAB main controller to the Pi broker.
%   link = pi_link_open('192.168.1.50', 'mgctl', '<password>')     (port 1883)
% link.publish(topic, json)  sends one message (QoS 0)
% link.fetch()               returns the requests received since the last call
%                            (struct array: topic, data) - only mg/cmd/# is subscribed
% link.close()               disconnects
% Needs the Industrial Communication Toolbox (mqttclient).
if nargin < 4, port = 1883; end
mq = mqttclient("tcp://" + string(host), Port = port, Username = string(user), ...
                Password = string(pass), ClientID = "mgctl-matlab-" + string(randi(1e6)));
assert(mq.Connected, 'could not connect to the Pi broker at %s:%d as %s', host, port, user);
subscribe(mq, "mg/cmd/#", QualityOfService = 0);
subscribe(mq, "mg/sim/#", QualityOfService = 0);   % demo bench knobs
link.mq = mq;
link.publish = @(topic, json) write(mq, string(topic), string(json));
link.fetch = @() fetch_all(mq);
link.close = @() clear_link(mq);
fprintf('Connected to the Pi broker %s:%d as %s (subscribed to mg/cmd/#)\n', host, port, user);
end

function rx = fetch_all(mq)
rx = struct('topic', {}, 'data', {});
tt = read(mq);                                  % everything received since the last read
for k = 1:height(tt)
    rx(end+1) = struct('topic', char(tt.Topic(k)), 'data', char(tt.Data(k))); %#ok<AGROW>
end
end

function clear_link(mq)
try, unsubscribe(mq); catch, end
delete(mq);
end

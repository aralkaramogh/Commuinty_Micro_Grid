function c = pi_cmd(t, sender, topic, varargin)
% PI_CMD  A request published on the Pi broker (for scenarios).
%   t      : simulated time it is published [s]
%   sender : MQTT user that publishes it ('dash', 'ai', 'H1', ...)
%   topic  : e.g. 'mg/cmd/op/restrict', 'mg/cmd/user/H1/user_flex', 'mg/cmd/ai/ai_advice'
%   name/value pairs -> JSON payload (id, target, value, ttl, t_sent, p_bess, shed_mask, price)
p = struct(varargin{:});
if ~isfield(p, 't_sent'), p.t_sent = t; end
c = struct('t', t, 'sender', sender, 'topic', topic, 'payload', p);
end

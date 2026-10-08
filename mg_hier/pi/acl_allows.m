function ok = acl_allows(user, access, topic, R)
% ACL_ALLOWS  true if MQTT user may 'read' (receive) or 'write' (publish) topic.
% Anonymous users (empty name) get nothing (allow_anonymous false).
if nargin < 4, R = pi_acl(); end
ok = false;
if isempty(user), return; end
for k = 1:numel(R)
    if ~strcmp(R(k).access, access), continue; end
    if strcmp(R(k).user, '*')
        f = strrep(R(k).topic, '%u', user);
    elseif strcmp(R(k).user, user)
        f = R(k).topic;
    else
        continue;
    end
    if topic_match(f, topic), ok = true; return; end
end
end

function ok = topic_match(filter, topic)
% MQTT filter matching: '+' = one level, '#' = this level and everything below
f = strsplit(filter, '/'); t = strsplit(topic, '/');
ok = false;
for i = 1:numel(f)
    if strcmp(f{i}, '#'), ok = true; return; end
    if i > numel(t), return; end
    if ~(strcmp(f{i}, '+') || strcmp(f{i}, t{i})), return; end
end
ok = numel(t) == numel(f);
end

function [link, box] = pi_link_fake()
% PI_LINK_FAKE  In-memory stand-in for pi_link_open (tests without a Pi).
%   box.push(topic, json)  queues a request as if a dashboard had sent it
%   box.sent()             everything the controller published: struct array topic, data
q = struct('topic', {}, 'data', {}); out = struct('topic', {}, 'data', {});
    function publish(topic, json), out(end+1) = struct('topic', char(topic), 'data', char(json)); end
    function rx = fetch(), rx = q; q = struct('topic', {}, 'data', {}); end
    function push(topic, json), q(end+1) = struct('topic', topic, 'data', json); end
    function s = sent(), s = out; end
link = struct('publish', @publish, 'fetch', @fetch, 'close', @() []);
box = struct('push', @push, 'sent', @sent);
end

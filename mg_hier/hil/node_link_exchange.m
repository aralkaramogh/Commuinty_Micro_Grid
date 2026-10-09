function reply = node_link_exchange(link, line, seq)
% NODE_LINK_EXCHANGE  Send one L/B line, return the matching l/b reply.
writeline(link.sp, line);
want = lower(line(1));
t0 = tic;
while true
    s = readline(link.sp);
    assert(~isempty(s), 'node on %s: no reply at tick %d', link.port, seq);
    s = char(strtrim(s));
    if numel(s) > 2 && s(1) == want && s(2) == ','
        v = sscanf(s(3:end), '%f', 1);
        if v == seq, reply = s; return; end
    end
    assert(~startsWith(s, 'E,') || strcmp(s, 'E,unknown'), 'node on %s: %s at tick %d', link.port, s, seq);
    assert(toc(t0) < 5, 'node on %s: wrong replies at tick %d', link.port, seq);
end
end

function f = node_exchange_twin(lk, id, P, lcd)
% NODE_EXCHANGE_TWIN  Exchange function for one real node: talks to the board and
% runs the MATLAB twin on the same line; counts any difference (node_twin_count).
% lcd = true: the board runs firmware_node/mg_node_lcd; before every L/B line it also
% gets a D line (mode, total demand, its role) for the display. No reply to D.
if nargin < 4, lcd = false; end
role = find(strcmp([P.load_id, {'SB'}], id));
if strcmp(id, 'SB'), st = node_sb_init(); else, st = node_load_init(); end
lost = false; lost_at = 0; RETRY_TICKS = 40;   % board dropped: the twin stands in, retry every 40 ticks
    function reply = xch(line, seq)
        if lost
            if seq - lost_at >= RETRY_TICKS, try_reconnect(seq); end
            if lost, reply = twin_only(line, seq); return; end
        end
        if strcmp(line, 'R')                     % technician reset: board and twin start over
            writeline(lk.sp, 'R'); t0 = tic;
            while toc(t0) < 3 && ~strcmp(strtrim(readline(lk.sp)), 'READY'), end
            if strcmp(id, 'SB'), st = node_sb_init(); else, st = node_load_init(); end
            reply = 'READY'; return;
        end
        if lcd
            di = display_info('get');
            writeline(lk.sp, sprintf('D,%d,%d,%.1f,%d', seq, di.mode, di.total_w, role));
        end
        es_panel = 0;                            % live-panel E-stop button for this node -> board (S line, no reply)
        try, li = live_inputs('get'); es_panel = double(li.estop(role) > 0); catch, end
        try, writeline(lk.sp, sprintf('S,%d', es_panel)); catch, end
        try
            reply = node_link_exchange(lk, line, seq);
        catch e
            fprintf(2, '\n*** %s board on %s lost at tick %d (%s).\n    MATLAB twin stands in for it; reconnect tried every %d ticks.\n', ...
                    id, lk.port, seq, e.message, RETRY_TICKS);
            lost = true; lost_at = seq;
            reply = twin_only(line, seq); return;
        end
        % the E-stop button is on the board, so the twin learns it from the reply
        % (hstate 3 / clamped 2) and must then behave identically
        if line(1) == 'L'
            es = sscanf(reply(3:end), '%f,', 4); es = numel(es) == 4 && es(4) == 3;
            [st, r] = node_load_step(st, node_lines('dec_L', line), P.node, P.sim.dt, es);
            ref = node_lines('enc_l', seq, r);
        else
            es = sscanf(reply(3:end), '%f,', 5); es = numel(es) == 5 && es(5) == 2;
            [st, r] = node_sb_step(st, node_lines('dec_B', line), P.node, P.bess, es);
            ref = node_lines('enc_b', seq, r);
        end
        node_twin_count('add', ~strcmp(reply, ref));
        if ~strcmp(reply, ref) && node_twin_count('get') <= 5
            fprintf('  %s tick %d differs\n    board: %s\n    twin : %s\n', id, seq, reply, ref);
        end
    end
    function reply = twin_only(line, seq)
        % board missing: the twin answers alone (same rules, no E-stop button)
        if strcmp(line, 'R')
            if strcmp(id, 'SB'), st = node_sb_init(); else, st = node_load_init(); end
            reply = 'READY'; return;
        end
        if line(1) == 'L'
            [st, r] = node_load_step(st, node_lines('dec_L', line), P.node, P.sim.dt, false);
            reply = node_lines('enc_l', seq, r);
        else
            [st, r] = node_sb_step(st, node_lines('dec_B', line), P.node, P.bess, false);
            reply = node_lines('enc_b', seq, r);
        end
    end
    function try_reconnect(seq)
        lost_at = seq; port = lk.port;
        try, delete(lk.sp); catch, end
        if ~any(serialportlist("available") == port)
            fprintf(2, '    %s: %s not present yet (replug USB?)\n', id, port); return;
        end
        try
            lk = node_link_open(port, P);            % board answers READY = fresh state
            if strcmp(id, 'SB'), st = node_sb_init(); else, st = node_load_init(); end
            lost = false;
            fprintf('    %s board on %s back at tick %d (node state restarted: counters, lockouts)\n', id, port, seq);
        catch e
            fprintf(2, '    %s: reconnect failed (%s)\n', id, e.message);
        end
    end
f = @xch;
end

function f = node_exchange_twin(lk, id, P, lcd)
% NODE_EXCHANGE_TWIN  Exchange function for one real node: talks to the board and
% runs the MATLAB twin on the same line; counts any difference (node_twin_count).
% lcd = true: the board runs firmware_node/mg_node_lcd; before every L/B line it also
% gets a D line (mode, total demand, its role) for the display. No reply to D.
if nargin < 4, lcd = false; end
role = find(strcmp([P.load_id, {'SB'}], id));
if strcmp(id, 'SB'), st = node_sb_init(); else, st = node_load_init(); end
    function reply = xch(line, seq)
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
        reply = node_link_exchange(lk, line, seq);
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
f = @xch;
end

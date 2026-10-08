function v = node_twin_count(op, x)
% NODE_TWIN_COUNT  Counter of real-board replies that differ from the MATLAB twin.
persistent nbad ntot
if isempty(nbad), nbad = 0; ntot = 0; end
v = 0;
switch op
    case 'reset', nbad = 0; ntot = 0;
    case 'add', ntot = ntot + 1; nbad = nbad + x;
    case 'get', v = nbad;
    case 'n', v = ntot;
end
end

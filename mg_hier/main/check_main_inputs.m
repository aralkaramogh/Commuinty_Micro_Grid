function check_main_inputs(in)
% CHECK_MAIN_INPUTS  Error if the main controller input has any field outside
% main_inputs_spec (or misses one).
S = main_inputs_spec();
same = @(s, f) isequal(sort(fieldnames(s)), sort(f(:)));
assert(isstruct(in) && same(in, S.top), 'main input: top-level fields not allowed');
assert(same(in.pcc, S.pcc), 'main input: pcc fields not allowed');
assert(same(in.load, S.load), 'main input: load-node report fields not allowed');
assert(same(in.sb, S.sb), 'main input: SB-node report fields not allowed');
assert(isempty(in.inbox) || same(in.inbox, S.inbox), 'main input: inbox fields not allowed');
end

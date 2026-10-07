function T = ac_ledger(L, P)
% AC_LEDGER  Peer-to-peer energy ledger [Wh]: each tick, sellers (houses with
% surplus, plus the community PV plant as seller "C") share their surplus with
% buyers pro rata. What is left over goes to / comes from the BESS and grid.
% T.matrix(i, j) = Wh sold by participant i to house j  (rows: H1..Hn, C)
n = P.n_house; Wh = P.sim.dt / 3600;
pnet = L.p_load - L.p_pv;                      % houses: + = buys
e = [max(-pnet, 0), L.p_cpv];                  % sellers' surplus (community PV is all surplus
d = max(pnet, 0);                              %  after the community load is fed below)
e(:, end) = max(L.p_cpv - L.p_cl, 0);
E = sum(e, 2); D = sum(d, 2); S = min(E, D);
M = zeros(n + 1, n);
for t = find(S > 0).'
    M = M + (e(t,:).' / E(t)) * (d(t,:) / D(t)) * S(t);
end
T.matrix = M * Wh;
T.names = [{P.house.id}, {'C'}];
T.sold_Wh = sum(T.matrix, 2).'; T.bought_Wh = sum(T.matrix, 1);
T.to_store_Wh = sum(E - S) * Wh; T.from_store_Wh = sum(D - S) * Wh;
end

function T = ledger_h(L, P)
% LEDGER_H  Peer-to-peer energy ledger [Wh] from the log: each tick, sellers
% (houses with surplus, plus the community PV plant "C" after feeding the
% community load) share their surplus with buyers pro rata. The rest goes to /
% comes from the BESS and grid. T.matrix(i, j) = Wh sold by i to house j.
n = P.n_house; Wh = P.sim.dt / 3600;
pnet = L.p_load - L.p_pv;                      % houses: + = buys
e = [max(-pnet, 0), max(L.p_cpv - L.p_cl, 0)];
d = max(pnet, 0);
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

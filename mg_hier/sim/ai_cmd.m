function a = ai_cmd(valid, p_bess, shed_mask, price)
% AI_CMD  An AI-advisor request (published by the AI service on mg/cmd/ai/ai_advice).
%   valid 0/1, p_bess [W] (+ discharge), shed_mask (bit0 = H1, bit1 = H2, bit2 = CL
%   flexible load), price [Rs/kWh]. ai_cmd() = no request.
if nargin == 0, valid = 0; p_bess = 0; shed_mask = 0; price = 0; end
a = struct('valid', valid, 'p_bess', p_bess, 'shed_mask', shed_mask, 'price', price);
end

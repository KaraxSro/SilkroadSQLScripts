USE [SRO_VT_SHARD]
GO
-- Reset everything, _SetSoXRndDropRate works based on the values in _RefDropClassSel_RareEquip table
EXEC _ResetSoXRndDropRate
GO
/*
If start and end are different, you can increase or decrase the droprate by each monster level, if same it will be constant
Example: Sos start 0.02 means lv 1 monster sos droprate will be 2%
If I set Sos end 0.01 means lv 110 monster sos droprate will be 1%
Everything inbetween will be calculated to slowly decrase it
*/
EXEC _SetSoXRndDropRate 
	0.02, -- Sos start
	0.02, -- Sos end
	0.006, -- Som start
	0.006, -- Som end
	0.002, -- Sun start
	0.002, -- Sun end
	110 -- Max monster level

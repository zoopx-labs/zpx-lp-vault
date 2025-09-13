Phase 2 runbook (short)

Env variables used by scripts
- FACTORY_ADDR: address of deployed Factory
- SPOKE_ASSET: asset address (ERC20)
- SPOKE_ADMIN: admin for the SpokeVault
- ROUTER_ADMIN: admin for the Router
- ADAPTER_ADDR: messaging adapter address
- FEE_COLLECTOR: (optional) fee sink, use 0x0 to skip
- KEEPER_ADDR: (optional) keeper to grant KEEPER_ROLE, use 0x0 to skip

Quick local dry-run (foundry)
1) Deploy MockAdapter
   forge script script/Deploy_MockAdapter.s.sol --fork-url <URL> -vvvv

2) Deploy Factory (if not deployed)
   use existing Deploy.s.sol or deploy a new Factory via a script.

3) Deploy a spoke via factory
   export FACTORY_ADDR=<factory>
   export SPOKE_ASSET=<token>
   export SPOKE_ADMIN=<admin>
   export ROUTER_ADMIN=<routerAdmin>
   export ADAPTER_ADDR=<mockAdapter>
   forge script script/Deploy_Phase2_Spoke.s.sol --fork-url <URL> -vvvv

Post-deploy
- Set per-spoke borrow caps: call SpokeVault.setBorrowCap
- Set maxUtilizationBps: call SpokeVault.setMaxUtilizationBps
- Grant KEEPER_ROLE to keepers (optional)
- Unpause vault & router when ready: SpokeVault.unpause(); Router.unpause();

Feed rotation / haircut changes
- Admin can call Hub.setFeed(...) and Hub.setHaircutBps(...)
- Make sure to run dry-run deposit flows after changing feeds to validate pps stability.

Emergency ops
- Pause Hub & SpokeVaults using PAUSER_ROLE
- Halt rebalances by pausing Router

Contact
- See repository README for Phase 1 runbook and more details.

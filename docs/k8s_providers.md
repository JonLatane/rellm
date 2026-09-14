# Managed Kubernetes provider comparison

Pricing snapshot as of September 2026. Compute tiers use the closest available instance in each provider's lineup with roughly a 1:2 vCPU-to-RAM ratio; where a provider's product line doesn't scale evenly, the actual vCPU/RAM of the matched instance is noted. The hyperscalers (AWS/GCP/Azure) are "bare minimum" numbers: cheapest on-demand list price, no committed-use/reserved discounts, single region, no free-tier credits beyond what's noted.

## All-in-one comparison

"N domain cost" = the matching compute tier + N × 6GB of block storage + the cheapest LoadBalancer tier (1 LB regardless of N) + the control plane cost actually incurred (Free for the first 5 providers; for the hyperscalers, whichever control-plane cost applies at bare-minimum settings — see Control plane column).

| Provider | 1 vCPU / 2GB | 2 vCPU / 4GB | 4 vCPU / 8GB | 8 vCPU / 16GB | Block storage | LoadBalancer | Control plane | 1 domain | 5 domains | 15 domains | 50 domains |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **DigitalOcean** (Basic droplet) | $12.00/mo | $24.00/mo | $48.00/mo | $96.00/mo | $0.10/GB/mo | $12/mo (regional, per node) | Free | $24.60/mo | $39.00/mo | $69.00/mo | $138.00/mo |
| **Linode / Akamai (LKE)** (Shared CPU) | $12.00/mo | $24.00/mo (2 vCPU) | $48.00/mo (4 vCPU) | $96.00/mo *(actual: 6 vCPU/16GB — true 8 vCPU is the $192 32GB plan)* | $0.10/GB/mo (10GB min) | $10/mo (NodeBalancer) | Free | $22.60/mo | $37.00/mo | $67.00/mo | $136.00/mo |
| **Civo** | $10.86/mo | $21.73/mo | $43.45/mo | $86.91/mo *(actual: 6 vCPU/16GB — true 8 vCPU is the $173.81 32GB plan)* | $0.11/GB/mo | ~$10.86/mo per 10k concurrent reqs | Free | $22.38/mo | $35.89/mo | $64.21/mo | $130.77/mo |
| **OVHcloud** (C3 compute-optimized) | $7.08/mo *(Discovery d2-2, a cheaper burstable line, not C3)* | $33.51/mo (c3-4, 12-mo plan) | $66.89/mo (c3-8, 12-mo plan) | $133.66/mo (c3-16, 12-mo plan) | ~$0.048/GB/mo (Classic) | ~$6.94/mo (S) – ~$168.19/mo (XL) | Free | $14.31/mo | $41.89/mo | $78.15/mo | $155.00/mo |
| **Scaleway** (Basic2, prev-gen) | €6.55/mo *(DEV1-S, actually 2 vCPU/2GB — no true 1vCPU/2GB tier exists)* | €16.79/mo | €37.74/mo | €75.48/mo | ~€0.095/GB/mo (5k IOPS) | ~€16.79/mo (LB-S) – ~€686/mo (LB-GP-XL) | Free | €23.91/mo | €36.43/mo | €63.08/mo | €120.77/mo |
| **AWS EKS** (c6i compute-optimized) | $15.18/mo *(t3.small, burstable 2 vCPU/2GB — no true 1vCPU/2GB EC2 type)* | $62.05/mo (c6i.large) | $124.10/mo (c6i.xlarge) | $248.20/mo (c6i.2xlarge) | $0.08/GB/mo (EBS gp3) | ~$16.20/mo base (NLB) + usage | **$73/mo always** (no free tier) | $104.86/mo | $153.65/mo | $220.50/mo | $361.40/mo |
| **Google GKE** (e2 family) | $12.23/mo (e2-small) | $24.46/mo (e2-medium, exact match) | $97.84/mo *(e2-standard-4, actual 4 vCPU/16GB — no exact 8GB SKU)* | $195.67/mo *(e2-standard-8, actual 8 vCPU/32GB — no exact 16GB SKU)* | ~$0.17/GB/mo (PD-SSD) | ~$18.25/mo base (per forwarding rule) + usage | **$0/mo for 1 cluster** (first zonal/Autopilot cluster covered by $74.40/mo credit), $73/mo per cluster after that | $31.50/mo | $47.81/mo | $131.39/mo | $264.92/mo |
| **Azure AKS** (F-series compute-optimized) | $15.30/mo (B1ms, burstable — no F-series that small) | $61.76/mo (F2s_v2) | $123.37/mo (F4s_v2) | $246.74/mo (F8s_v2) | ~$0.075/GB/mo (Standard SSD) | ~$18.25/mo base (Standard LB) + usage | **$0/mo (Free tier, no SLA)**; $73/mo for Standard tier w/ SLA | $34.00/mo | $82.26/mo | $148.37/mo | $287.49/mo |

Notes:

- Civo is the cleanest 1:2 vCPU:RAM scaler at most tiers and the cheapest USD option among the small providers at nearly every domain-count tier, but it has the same gap as Linode at the top end: no true 8vCPU/16GB instance (its 16GB tier is 6 vCPU; genuine 8 vCPU means jumping to 32GB/$173.81).
- Linode's shared-CPU line doesn't hit 8 vCPU until the 32GB/$192 plan — its 16GB tier is only 6 vCPU. Dedicated-CPU 16GB (8 vCPU, guaranteed) runs ~$144/mo instead. The 8vCPU/16GB and 50-domain columns above use the $96 (6vCPU) plan for consistency with the rest of the table.
- OVH's default B3 general-purpose line runs a 1:4 ratio (e.g. b3-16 = 4 vCPU/16GB); the C3 compute-optimized line above is the actual 1:2 match for the 3 larger tiers. OVH has no 1vCPU/2GB C3 instance at all — the 1 vCPU/2GB and 1-domain figures use their separate Discovery (d2) burstable line instead, which isn't guaranteed-CPU like C3. OVH's 12-month committed pricing is shown; on-demand hourly billing is somewhat higher.
- Scaleway's current-gen BASIC3 line is also 1:2 but pricier (~€28.79/€57.67/€129.70); BASIC2 (previous gen) is the cheaper match shown above. Scaleway has no 1vCPU/2GB Basic tier either — DEV1-S (2vCPU/2GB) is the closest by RAM. Scaleway prices in EUR only.
- The hyperscalers are dramatically more expensive at small scale mainly *because of the control plane fee*, not the compute: AWS charges $73/mo per cluster unconditionally, forever — there's no free tier at all. GKE and AKS both let you avoid that fee entirely at bare-minimum scale (GKE's $74.40/mo credit covers exactly one zonal/Autopilot cluster; AKS's Free tier has no control-plane charge at all, just no financially-backed SLA), which is why their domain-cost columns above look much closer to the small providers than AWS does.
- Neither GKE nor AKS has a predefined instance exactly matching 4vCPU/8GB or 8vCPU/16GB in their general-purpose/compute-optimized lines shown; the GKE figures use the next-size-up e2-standard instance (extra RAM, no extra cost control). Azure's F-series (compute-optimized, guaranteed vCPU) happens to hit both those tiers exactly.

## Caveats

- OVH and Scaleway prices are in EUR; not currency-adjusted against the USD figures above.
- All five smaller providers ship a CNCF-conformant Kubernetes control plane with a cloud-controller-manager (auto-provisioned LoadBalancers) and CSI driver (dynamic block storage), so cert-manager and standard ingress setups behave the same way across all of them — the differences here are purely price/tier shape, not capability. The same is true of EKS/GKE/AKS — cert-manager works identically there too.
- HA control planes (if you want one) beyond what's in the table: DigitalOcean ~$40/mo, Linode ~$60/mo; Civo, OVH, and Scaleway control planes are free regardless. AWS's extended-support tier (for clusters running an EOL Kubernetes version) jumps the control plane fee to $0.60/hr (~$438/mo).
- Hyperscaler compute prices shown are on-demand, single-AZ, no reserved/committed-use discounts or spot pricing — those can cut the compute columns by 30-70% but complicate a direct "bare minimum sticker price" comparison, so they're intentionally excluded here.

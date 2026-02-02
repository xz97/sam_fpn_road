# CityScale Metrics (Official-Mode)

We standardize CityScale APLS to **official-mode** to avoid mismatched implementations/params.

## APLS (official-mode)
Prereq: official repo is cloned at `~/repos/sam_road_official`.

Run:
```bash
bash tools/eval_cityscale_apls_official.sh save/save/cityscale_toponet_16x16_stageB_cldice /mnt/data/outputs/YYYYMMDD_cityscale_apls_OFFICIALMODE.log

# CityScale Metrics (Official-Mode)

We standardize CityScale APLS to **official-mode** to avoid mismatched implementations/params.

## APLS (official-mode)

**Prereq**
- Official repo cloned at `~/repos/sam_road_official`
- Python venv: `~/venvs/road`
- Go available in PATH: `go version`

**Run**
```bash
source ~/venvs/road/bin/activate
cd ~/repos/sam_road

bash tools/eval_cityscale_apls_official.sh \
  save/save/cityscale_toponet_16x16_stageB_cldice \
  /mnt/data/outputs/$(date +%Y%m%d)_cityscale_stageB_cldice_apls_OFFICIALMODE.log


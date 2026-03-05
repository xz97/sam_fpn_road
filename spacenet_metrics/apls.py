import numpy as np
import os
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument('--dir', type=str)

args = parser.parse_args()

apls = []
output_apls = []
# resolve pred dir robustly (accept abs or rel)
base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
pred_dir = args.dir
if not os.path.isabs(pred_dir):
    pred_dir = os.path.abspath(os.path.join(base, pred_dir))
apls_dir = os.path.join(pred_dir, "results", "apls")
name_list = os.listdir(apls_dir)
name_list.sort()
for file_name in name_list :
    with open(os.path.join(apls_dir, file_name)) as f:
        lines = f.readlines()
    # print(file_name,lines[0].split(' ')[-1])
    # print(lines[0].split(' '))
    if 'NaN' in lines[0]:
        pass
        # apls.append(0)
        # output_apls.append([file_name,0])
    else:
        apls.append(float(lines[0].split(' ')[-1]))
        output_apls.append([file_name,float(lines[0].split(' ')[-1])])

apls_np = np.array(apls, dtype=float)
valid = np.isfinite(apls_np)
print('APLS', float(np.nanmean(apls_np)))
print('APLS_valid', int(valid.sum()), '/', int(len(apls_np)))
os.makedirs(os.path.join(pred_dir, 'results'), exist_ok=True)
results_json = os.path.join(pred_dir, 'results', 'apls.json')
with open(results_json, 'w') as jf:
    json.dump({'apls':output_apls,'final_APLS':np.mean(apls)},jf)